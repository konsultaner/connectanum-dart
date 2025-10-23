//! Tokio based runtime that backs the connectanum native transport.

use std::{
    collections::HashMap,
    io,
    net::{SocketAddr, ToSocketAddrs},
    sync::{
        atomic::{AtomicU32, Ordering},
        Arc, Mutex, OnceLock,
    },
    time::Duration,
};

use bytes::{Bytes, BytesMut};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::tcp::{OwnedReadHalf, OwnedWriteHalf},
    runtime::Runtime,
    sync::mpsc::{self, error::TryRecvError, UnboundedReceiver, UnboundedSender},
    task::JoinHandle,
    time,
};

mod config;
mod platform;
mod rawsocket;
mod wamp;

pub use config::EndpointRuntimeConfig;
pub use platform::{Runtime as PlatformRuntime, UnsupportedPlatform};
pub use rawsocket::Serializer as RawSocketSerializer;
pub use wamp::{
    parse_message, ParseError as WampParseError, ParsedMessage, Payload as WampPayload, WampMessage,
};

static RUNTIME_MANAGER: OnceLock<RuntimeManager> = OnceLock::new();

const MAX_FRAME_LEN: u64 = 1 << 24;

/// Unique identifier for a registered listener.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct ListenerId(pub u32);

/// Unique identifier for an accepted connection.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct ConnectionId(pub u32);

/// Errors that can occur when interacting with the runtime.
#[derive(Debug, Error)]
pub enum Error {
    /// The runtime has not been initialised yet.
    #[error("runtime not started")]
    RuntimeNotStarted,
    /// Attempted to start the runtime twice without shutting it down.
    #[error("runtime already started")]
    RuntimeAlreadyStarted,
    /// Native runtime is not supported on this platform.
    #[error("native runtime unsupported on this platform")]
    UnsupportedPlatform,
    /// Provided backlog value is invalid.
    #[error("backlog must be positive")]
    InvalidBacklog,
    /// No listener with the provided identifier exists.
    #[error("listener {0:?} not found")]
    ListenerNotFound(ListenerId),
    /// The accept channel was already consumed.
    #[error("accept channel already taken for listener {0:?}")]
    AcceptChannelAlreadyTaken(ListenerId),
    /// Socket address resolution failed.
    #[error("failed to resolve address {0}:{1}")]
    AddressResolution(String, u16),
    /// Listener requested for a host/port not present in the applied config.
    #[error("endpoint {0}:{1} is not configured")]
    EndpointNotConfigured(String, u16),
    /// Router configuration could not be parsed or applied.
    #[error("router configuration invalid: {0}")]
    RouterConfigInvalid(String),
    /// Connection for the provided identifier was not registered.
    #[error("connection {0:?} not found")]
    ConnectionNotFound(ConnectionId),
    /// Wrapper around I/O errors.
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

struct RuntimeManager {
    state: Mutex<Option<RuntimeState>>,
}

struct RuntimeState {
    runtime: Runtime,
    handle: tokio::runtime::Handle,
    registry: Arc<ListenerRegistry>,
}

struct RuntimeView {
    handle: tokio::runtime::Handle,
    registry: Arc<ListenerRegistry>,
}

#[derive(Default)]
struct ListenerRegistry {
    listeners: Mutex<HashMap<ListenerId, ListenerEntry>>,
    connections: Mutex<HashMap<ConnectionId, ConnectionEntry>>,
    next_listener_id: AtomicU32,
    next_connection_id: AtomicU32,
}

struct ListenerEntry {
    addr: SocketAddr,
    receiver: Mutex<Option<mpsc::Receiver<ConnectionId>>>,
    _sender: mpsc::Sender<ConnectionId>,
    task: JoinHandle<()>,
    #[allow(dead_code)]
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
}

struct ConnectionEntry {
    #[allow(dead_code)]
    listener_id: ListenerId,
    #[allow(dead_code)]
    peer_addr: SocketAddr,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    #[allow(dead_code)]
    serializer: rawsocket::Serializer,
    max_exponent: u32,
    frames: Mutex<mpsc::Receiver<wamp::ParsedMessage>>,
    reader_task: JoinHandle<()>,
    writer_task: JoinHandle<()>,
    send_tx: UnboundedSender<OutboundFrame>,
}

impl RuntimeManager {
    fn global() -> &'static Self {
        RUNTIME_MANAGER.get_or_init(|| RuntimeManager {
            state: Mutex::new(None),
        })
    }

    fn with_state<F, T>(&self, f: F) -> Result<T, Error>
    where
        F: FnOnce(&RuntimeView) -> Result<T, Error>,
    {
        let view = {
            let guard = self
                .state
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            let state = guard.as_ref().ok_or(Error::RuntimeNotStarted)?;
            state.view()
        };
        f(&view)
    }
}

impl RuntimeState {
    fn view(&self) -> RuntimeView {
        RuntimeView {
            handle: self.handle.clone(),
            registry: Arc::clone(&self.registry),
        }
    }

    fn shutdown(self) {
        self.registry.shutdown();
        let runtime = self.runtime;
        let _ = std::thread::spawn(move || {
            runtime.shutdown_timeout(Duration::from_secs(1));
        })
        .join();
    }
}

impl ListenerRegistry {
    fn next_listener_id(&self) -> ListenerId {
        let id = self.next_listener_id.fetch_add(1, Ordering::SeqCst);
        ListenerId(id + 1)
    }

    fn next_connection_id(&self) -> ConnectionId {
        let id = self
            .next_connection_id
            .fetch_add(1, Ordering::SeqCst)
            .wrapping_add(1);
        ConnectionId(id)
    }

    fn insert(&self, id: ListenerId, entry: ListenerEntry) {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(id, entry);
    }

    fn local_addr(&self, id: ListenerId) -> Result<SocketAddr, Error> {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&id)
            .map(|entry| entry.addr)
            .ok_or(Error::ListenerNotFound(id))
    }

    fn take_receiver(&self, id: ListenerId) -> Result<mpsc::Receiver<ConnectionId>, Error> {
        let listeners = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = listeners.get(&id).ok_or(Error::ListenerNotFound(id))?;
        let mut guard = entry.receiver.lock().unwrap();
        guard.take().ok_or(Error::AcceptChannelAlreadyTaken(id))
    }

    fn shutdown(&self) {
        let listener_entries: Vec<ListenerEntry> = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .drain()
            .map(|(_, entry)| entry)
            .collect();
        for entry in listener_entries {
            entry.task.abort();
        }

        let connection_entries: Vec<ConnectionEntry> = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .drain()
            .map(|(_, entry)| entry)
            .collect();
        for entry in connection_entries {
            entry.reader_task.abort();
            entry.writer_task.abort();
        }
    }

    fn register_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        negotiated: rawsocket::NegotiatedSession,
        peer_addr: SocketAddr,
    ) {
        let (frame_tx, frame_rx) = mpsc::channel(1024);
        let (send_tx, send_rx) = mpsc::unbounded_channel();
        let serializer = negotiated.serializer;
        let max_exponent = negotiated.max_message_size_exponent;
        let reader_task = spawn_connection_reader(
            connection_id,
            Arc::clone(&endpoint_config),
            negotiated.reader,
            serializer,
            max_exponent,
            frame_tx,
            send_tx.clone(),
        );
        let writer_task = spawn_connection_writer(connection_id, negotiated.writer, send_rx);

        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    endpoint_config,
                    serializer,
                    max_exponent,
                    frames: Mutex::new(frame_rx),
                    reader_task,
                    writer_task,
                    send_tx,
                },
            );
    }

    fn connection_config(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Arc<config::EndpointRuntimeConfig>, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| Arc::clone(&entry.endpoint_config))
            .ok_or(Error::ConnectionNotFound(connection_id))
    }

    fn connection_exponent(&self, connection_id: ConnectionId) -> Result<u32, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| entry.max_exponent)
            .ok_or(Error::ConnectionNotFound(connection_id))
    }

    fn poll_message(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<wamp::ParsedMessage>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        let mut receiver = entry.frames.lock().unwrap();
        match receiver.try_recv() {
            Ok(message) => Ok(Some(message)),
            Err(TryRecvError::Empty) => Ok(None),
            Err(TryRecvError::Disconnected) => Ok(None),
        }
    }

    fn enqueue_frame(
        &self,
        connection_id: ConnectionId,
        frame: OutboundFrame,
    ) -> Result<(), Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        entry
            .send_tx
            .send(frame)
            .map_err(|_| Error::ConnectionNotFound(connection_id))
    }
}

#[derive(Debug)]
enum FrameReadError {
    Io(io::Error),
    Protocol(String),
}

impl From<io::Error> for FrameReadError {
    fn from(value: io::Error) -> Self {
        FrameReadError::Io(value)
    }
}

impl std::fmt::Display for FrameReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FrameReadError::Io(err) => write!(f, "io error: {}", err),
            FrameReadError::Protocol(msg) => write!(f, "protocol error: {}", msg),
        }
    }
}

impl std::error::Error for FrameReadError {}

enum InboundFrame {
    Message(Bytes),
    Ping(Bytes),
    Pong,
}

#[derive(Debug, Clone)]
struct OutboundFrame {
    frame_type: u8,
    payload: Bytes,
}

impl OutboundFrame {
    fn message(payload: Bytes) -> Self {
        Self {
            frame_type: 0,
            payload,
        }
    }

    fn control(frame_type: u8, payload: Bytes) -> Self {
        Self {
            frame_type,
            payload,
        }
    }
}

fn spawn_connection_reader(
    connection_id: ConnectionId,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    mut reader: OwnedReadHalf,
    serializer: rawsocket::Serializer,
    max_message_size_exponent: u32,
    frame_tx: mpsc::Sender<wamp::ParsedMessage>,
    send_tx: UnboundedSender<OutboundFrame>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let max_payload = 1u64 << max_message_size_exponent;
        let idle_timeout = endpoint_config.idle_timeout;

        loop {
            let read_future = read_inbound_frame(&mut reader, max_payload);
            let frame = if let Some(timeout) = idle_timeout {
                match time::timeout(timeout, read_future).await {
                    Ok(result) => result,
                    Err(_) => {
                        eprintln!(
                            "connection {:?} idle for {:?}, closing",
                            connection_id, timeout
                        );
                        break;
                    }
                }
            } else {
                read_future.await
            };

            let frame = match frame {
                Ok(frame) => frame,
                Err(FrameReadError::Io(err)) => {
                    if err.kind() != io::ErrorKind::UnexpectedEof {
                        eprintln!("connection {:?} io error: {}", connection_id, err);
                    }
                    break;
                }
                Err(FrameReadError::Protocol(reason)) => {
                    eprintln!(
                        "connection {:?} protocol violation: {}",
                        connection_id, reason
                    );
                    break;
                }
            };

            match frame {
                InboundFrame::Message(payload) => match wamp::parse_message(serializer, payload) {
                    Ok(parsed) => {
                        if frame_tx.send(parsed).await.is_err() {
                            break;
                        }
                    }
                    Err(err) => {
                        eprintln!(
                            "connection {:?} failed to parse WAMP message: {:?}",
                            connection_id, err
                        );
                        break;
                    }
                },
                InboundFrame::Ping(payload) => {
                    if send_tx.send(OutboundFrame::control(0x02, payload)).is_err() {
                        break;
                    }
                }
                InboundFrame::Pong => {
                    // No-op; router currently does not track round-trip times.
                }
            }
        }
    })
}

fn spawn_connection_writer(
    connection_id: ConnectionId,
    mut writer: OwnedWriteHalf,
    mut rx: UnboundedReceiver<OutboundFrame>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        while let Some(frame) = rx.recv().await {
            let header = match encode_frame_header(frame.frame_type, frame.payload.len()) {
                Ok(header) => header,
                Err(err) => {
                    eprintln!(
                        "connection {:?} failed to encode outbound frame header: {}",
                        connection_id, err
                    );
                    continue;
                }
            };

            if let Err(err) = writer.write_all(&header).await {
                if err.kind() != io::ErrorKind::BrokenPipe {
                    eprintln!(
                        "connection {:?} failed to write frame header: {}",
                        connection_id, err
                    );
                }
                break;
            }

            if !frame.payload.is_empty() {
                if let Err(err) = writer.write_all(&frame.payload).await {
                    if err.kind() != io::ErrorKind::BrokenPipe {
                        eprintln!(
                            "connection {:?} failed to write frame payload: {}",
                            connection_id, err
                        );
                    }
                    break;
                }
            }
        }
    })
}

async fn read_inbound_frame(
    stream: &mut OwnedReadHalf,
    max_payload: u64,
) -> Result<InboundFrame, FrameReadError> {
    let mut header = [0u8; 4];
    stream.read_exact(&mut header).await?;

    let reserved = header[0] >> 4;
    if reserved != 0 {
        return Err(FrameReadError::Protocol(
            "reserved bits must be zero".into(),
        ));
    }

    let length_hi = (header[0] >> 3) & 0x01;
    let frame_type = header[0] & 0x07;

    let mut length = ((header[1] as u32) << 16) | ((header[2] as u32) << 8) | header[3] as u32;
    if length_hi == 1 {
        if length != 0 {
            return Err(FrameReadError::Protocol(
                "extended length bit set with non-zero length bytes".into(),
            ));
        }
        length = 1 << 24;
    }

    let length_u64 = length as u64;
    if length_u64 > max_payload {
        return Err(FrameReadError::Protocol(format!(
            "frame length {} exceeds negotiated maximum {}",
            length_u64, max_payload
        )));
    }
    if length_u64 > MAX_FRAME_LEN {
        return Err(FrameReadError::Protocol(format!(
            "frame length {} exceeds supported maximum {}",
            length_u64, MAX_FRAME_LEN
        )));
    }

    let payload = if length == 0 {
        Bytes::new()
    } else {
        let mut buf = BytesMut::with_capacity(length as usize);
        buf.resize(length as usize, 0);
        stream.read_exact(&mut buf).await?;
        buf.freeze()
    };

    match frame_type {
        0 => Ok(InboundFrame::Message(payload)),
        1 => Ok(InboundFrame::Ping(payload)),
        2 => Ok(InboundFrame::Pong),
        _ => Err(FrameReadError::Protocol(format!(
            "unsupported frame type {}",
            frame_type
        ))),
    }
}

fn encode_frame_header(frame_type: u8, payload_len: usize) -> Result<[u8; 4], FrameReadError> {
    if frame_type > 0x07 {
        return Err(FrameReadError::Protocol(format!(
            "invalid frame type {}",
            frame_type
        )));
    }
    if payload_len > MAX_FRAME_LEN as usize {
        return Err(FrameReadError::Protocol(format!(
            "payload length {} exceeds supported maximum {}",
            payload_len, MAX_FRAME_LEN as usize
        )));
    }

    let mut header = [0u8; 4];
    let mut first = frame_type & 0x07;
    if payload_len == (MAX_FRAME_LEN as usize) {
        first |= 0x08;
    } else {
        header[1] = ((payload_len >> 16) & 0xFF) as u8;
        header[2] = ((payload_len >> 8) & 0xFF) as u8;
        header[3] = (payload_len & 0xFF) as u8;
    }
    header[0] = first;
    Ok(header)
}

/// Initialises the multi-threaded tokio runtime if it has not been started yet.
pub fn start_runtime() -> Result<(), Error> {
    let manager = RuntimeManager::global();
    let mut guard = manager
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if guard.is_some() {
        return Err(Error::RuntimeAlreadyStarted);
    }

    // Ensure the platform allows native runtime creation.
    PlatformRuntime::new().map_err(|_| Error::UnsupportedPlatform)?;

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .thread_name("connectanum-rt")
        .enable_all()
        .build()?;

    let handle = runtime.handle().clone();
    let state = RuntimeState {
        runtime,
        handle,
        registry: Arc::new(ListenerRegistry::default()),
    };
    *guard = Some(state);
    Ok(())
}

/// Applies the router configuration JSON produced on the Dart side.
pub fn apply_router_config(bytes: &[u8]) -> Result<(), Error> {
    config::apply_router_config_bytes(bytes)
}

/// Gracefully shuts down the runtime and aborts all listener tasks.
pub fn shutdown() -> Result<(), Error> {
    let manager = RuntimeManager::global();
    let mut guard = manager
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if let Some(state) = guard.take() {
        state.shutdown();
    }
    Ok(())
}

/// Starts listening on the provided address and returns the allocated listener id.
pub fn listen(addr: &str, port: u16, backlog: i32) -> Result<ListenerId, Error> {
    if backlog <= 0 {
        return Err(Error::InvalidBacklog);
    }
    let manager = RuntimeManager::global();
    manager
        .with_state(|view| {
            let socket_addr = resolve_socket_addr(addr, port)?;
            let endpoint_config = config::find_endpoint(addr, port)
                .ok_or_else(|| Error::EndpointNotConfigured(addr.to_string(), port))?;
            let runtime_config = Arc::new(config::EndpointRuntimeConfig::try_from_endpoint(
                &endpoint_config,
            )?);
            let std_listener = create_listener(socket_addr, backlog as u32)?;
            let local_addr = std_listener.local_addr()?;

            let (sender, receiver) = mpsc::channel(1024);
            let listener_id = view.registry.next_listener_id();
            let accept_registry = Arc::clone(&view.registry);
            let async_sender = sender.clone();
            let runtime_config_for_task = Arc::clone(&runtime_config);
            let task = view.handle.spawn(async move {
                let listener = tokio::net::TcpListener::from_std(std_listener)
                    .expect("failed to convert listener to tokio");
                let tx = async_sender;
                loop {
                    match listener.accept().await {
                        Ok((stream, addr)) => {
                            match rawsocket::negotiate(stream, &runtime_config_for_task).await {
                                Ok(negotiated) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        negotiated,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Err(rawsocket::HandshakeError::HttpProbe) => {
                                    // HTTP probe handled; ignore connection.
                                }
                                Err(rawsocket::HandshakeError::Protocol(msg)) => {
                                    eprintln!(
                                        "rawsocket handshake failed for listener {:?}: {}",
                                        listener_id, msg
                                    );
                                }
                                Err(rawsocket::HandshakeError::Io(err)) => {
                                    eprintln!(
                                        "rawsocket handshake IO error for listener {:?}: {}",
                                        listener_id, err
                                    );
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }
            });

            let entry = ListenerEntry {
                addr: local_addr,
                receiver: Mutex::new(Some(receiver)),
                _sender: sender,
                task,
                endpoint_config: runtime_config,
            };
            view.registry.insert(listener_id, entry);

            Ok(listener_id)
        })
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the bound socket address for the given listener.
pub fn local_addr(listener_id: ListenerId) -> Result<SocketAddr, Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.local_addr(listener_id))
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the channel that streams accepted connection identifiers.
pub fn accept_channel(listener_id: ListenerId) -> Result<mpsc::Receiver<ConnectionId>, Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.take_receiver(listener_id))
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the runtime-ready endpoint configuration associated with a connection.
pub fn connection_runtime_config(
    connection_id: ConnectionId,
) -> Result<Arc<config::EndpointRuntimeConfig>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_config(connection_id))
}

/// Convenience helper exposing the RawSocket max message size exponent for a connection.
pub fn connection_rawsocket_max_exponent(connection_id: ConnectionId) -> Result<u32, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_exponent(connection_id))
}

/// Attempts to retrieve the next parsed WAMP message for a connection.
pub fn poll_connection_message(
    connection_id: ConnectionId,
) -> Result<Option<wamp::ParsedMessage>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.poll_message(connection_id))
}

/// Enqueues a WAMP message to be sent to the connection.
pub fn send_wamp_message(connection_id: ConnectionId, payload: Bytes) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        state
            .registry
            .enqueue_frame(connection_id, OutboundFrame::message(payload))
    })
}

fn resolve_socket_addr(addr: &str, port: u16) -> Result<SocketAddr, Error> {
    let mut addrs = (addr, port)
        .to_socket_addrs()
        .map_err(|_| Error::AddressResolution(addr.to_string(), port))?;
    addrs
        .next()
        .ok_or_else(|| Error::AddressResolution(addr.to_string(), port))
}

fn create_listener(
    addr: SocketAddr,
    backlog: u32,
) -> Result<std::net::TcpListener, std::io::Error> {
    use socket2::{Domain, Socket, Type};

    let domain = if addr.is_ipv4() {
        Domain::IPV4
    } else {
        Domain::IPV6
    };
    let socket = Socket::new(domain, Type::STREAM, None)?;
    socket.set_reuse_address(true)?;
    socket.bind(&addr.into())?;
    socket.listen(backlog as i32)?;
    socket.set_nonblocking(true)?;
    Ok(socket.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::sync::mpsc::error::TryRecvError;

    fn test_guard() -> std::sync::MutexGuard<'static, ()> {
        static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
        GUARD.get_or_init(|| Mutex::new(())).lock().unwrap()
    }

    #[test]
    fn apply_router_config_stores_config() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":8080,"tls_mode":"native"}]}"#)
            .expect("config applies");
        let cfg = crate::config::current_config().expect("config stored");
        assert_eq!(cfg.endpoints.len(), 1);
        let endpoint = crate::config::find_endpoint("127.0.0.1", 8080).expect("endpoint");
        assert_eq!(endpoint.host, "127.0.0.1");
    }

    #[test]
    fn apply_router_config_rejects_invalid_rawsocket_exponent() {
        let _guard = test_guard();
        shutdown().ok();
        let err = super::apply_router_config(br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":8080,"tls_mode":"native","max_rawsocket_size_exponent":8}]}"#)
            .expect_err("exponent below minimum rejected");
        assert!(matches!(err, Error::RouterConfigInvalid(_)));

        let err = super::apply_router_config(br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":8080,"tls_mode":"native","max_rawsocket_size_exponent":31}]}"#)
            .expect_err("exponent above maximum rejected");
        assert!(matches!(err, Error::RouterConfigInvalid(_)));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn runtime_starts_only_once() {
        let _guard = test_guard();
        shutdown().ok();
        start_runtime().expect("first start succeeds");
        let err = start_runtime().expect_err("second start fails");
        assert!(matches!(err, Error::RuntimeAlreadyStarted));
        shutdown().expect("shutdown succeeds");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn listen_accept_and_shutdown() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        assert!(addr.port() > 0);

        let mut receiver = accept_channel(listener_id).unwrap();
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 16, None).await;
        drop(stream);

        let connection_id = receiver.recv().await.expect("receive connection");
        assert!(connection_id.0 > 0);
        assert!(matches!(receiver.try_recv(), Err(TryRecvError::Empty)));

        shutdown().unwrap();
        // Runtime can be started again after shutdown.
        start_runtime().unwrap();
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connection_runtime_config_exposes_rawsocket_settings() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","max_rawsocket_size_exponent":30}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 24, Some(30)).await;
        drop(stream);

        let connection_id = receiver.recv().await.expect("connection delivered");
        let config = connection_runtime_config(connection_id).expect("config available");
        assert_eq!(config.max_rawsocket_size_exponent, 30);
        assert_eq!(config.max_rawsocket_size, 1u64 << 30);
        assert_eq!(config.handshake_timeout, config::DEFAULT_HANDSHAKE_TIMEOUT);
        assert_eq!(
            connection_rawsocket_max_exponent(connection_id).unwrap(),
            30
        );

        let missing_err =
            connection_runtime_config(ConnectionId(9999)).expect_err("missing connection handled");
        assert!(matches!(
            missing_err,
            Error::ConnectionNotFound(ConnectionId(_))
        ));
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connection_messages_can_be_polled() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","max_rawsocket_size_exponent":16}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let mut client = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut client, 16, None).await;
        let hello = json!([1, "realm", {"roles": {"dealer": {}}}]);
        let payload = serde_json::to_vec(&hello).unwrap();
        send_json_frame(&mut client, &payload).await;

        let connection_id = receiver.recv().await.expect("connection delivered");

        let mut attempts = 0;
        let parsed = loop {
            if let Some(msg) = poll_connection_message(connection_id).expect("poll succeeds") {
                break msg;
            }
            attempts += 1;
            if attempts > 20 {
                panic!("message not delivered in time");
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        };

        match parsed.message {
            WampMessage::Hello { realm, .. } => assert_eq!(realm, "realm"),
            other => panic!("unexpected message: {:?}", other),
        }

        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn handshake_timeout_rejects_idle_clients() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","handshake_timeout_ms":100,"max_rawsocket_size_exponent":16}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        // Intentionally do not send handshake bytes.
        tokio::time::sleep(Duration::from_millis(150)).await;
        drop(stream);

        assert!(matches!(receiver.try_recv(), Err(TryRecvError::Empty)));
        shutdown().unwrap();
    }

    async fn perform_handshake(
        stream: &mut tokio::net::TcpStream,
        exponent: u32,
        upgrade: Option<u32>,
    ) {
        let clamped = exponent.clamp(9, 24);
        let handshake_byte = ((clamped - 9) as u8).min(15) << 4 | 0x01;
        stream
            .write_all(&[0x7F, handshake_byte, 0x00, 0x00])
            .await
            .expect("handshake write");
        let mut response = [0u8; 4];
        stream
            .read_exact(&mut response)
            .await
            .expect("handshake response");
        assert_eq!(response[0], 0x7F);
        if let Some(upgrade_exponent) = upgrade {
            let nibble = (upgrade_exponent.saturating_sub(25)).min(15) as u8;
            stream
                .write_all(&[0x3F, nibble])
                .await
                .expect("upgrade request");
            let mut upgrade_response = [0u8; 2];
            stream
                .read_exact(&mut upgrade_response)
                .await
                .expect("upgrade response");
            assert_eq!(upgrade_response[0], 0x3F);
        }
    }

    async fn send_json_frame(stream: &mut tokio::net::TcpStream, payload: &[u8]) {
        assert!(payload.len() <= super::MAX_FRAME_LEN as usize);
        let mut header = [0u8; 4];
        if payload.len() == super::MAX_FRAME_LEN as usize {
            header[0] = 0x08;
        } else {
            header[0] = 0x00;
            header[1] = ((payload.len() >> 16) & 0xFF) as u8;
            header[2] = ((payload.len() >> 8) & 0xFF) as u8;
            header[3] = (payload.len() & 0xFF) as u8;
        }
        stream.write_all(&header).await.unwrap();
        if !payload.is_empty() {
            stream.write_all(payload).await.unwrap();
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn accept_channel_only_once() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let _receiver = accept_channel(listener_id).unwrap();
        let err = accept_channel(listener_id).expect_err("second take fails");
        assert!(matches!(
            err,
            Error::AcceptChannelAlreadyTaken(ListenerId(_))
        ));
        shutdown().unwrap();
    }

    #[test]
    fn listen_without_runtime_fails() {
        let _guard = test_guard();
        shutdown().ok();
        let err = listen("127.0.0.1", 0, 128).expect_err("runtime missing");
        assert!(matches!(err, Error::RuntimeNotStarted));
    }

    #[test]
    fn invalid_backlog_is_rejected() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let err = listen("127.0.0.1", 0, 0).expect_err("invalid backlog");
        assert!(matches!(err, Error::InvalidBacklog));
        shutdown().unwrap();
    }

    #[test]
    fn unknown_listener_errors() {
        let _guard = test_guard();
        shutdown().ok();
        start_runtime().unwrap();
        let err = local_addr(ListenerId(999)).expect_err("missing listener");
        assert!(matches!(err, Error::ListenerNotFound(ListenerId(_))));
        shutdown().unwrap();
    }
}
