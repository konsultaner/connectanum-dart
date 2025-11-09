//! Tokio based runtime that backs the connectanum native transport.

use std::{
    collections::{HashMap, VecDeque},
    io::{self, Cursor},
    net::{SocketAddr, ToSocketAddrs},
    ops::Deref,
    sync::{
        atomic::{AtomicU32, Ordering},
        Arc, Mutex, OnceLock,
    },
    time::Duration,
};

use bytes::{Buf, Bytes, BytesMut};
use h3::server::RequestStream as H3RequestStream;
use h3_quinn::Connection as H3QuinnConnection;
use http::{
    header::{HeaderName, HeaderValue, CONTENT_LENGTH},
    Request as HttpRequest, Response as HttpResponse, StatusCode,
};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt, BufReader},
    net::tcp::{OwnedReadHalf, OwnedWriteHalf},
    runtime::Runtime,
    sync::{
        mpsc::{self, error::TryRecvError, UnboundedReceiver, UnboundedSender},
        oneshot,
    },
    task::JoinHandle,
    time,
};

mod config;
mod platform;
mod protocol;
mod rawsocket;
mod wamp;

use config::{HttpRouteMatch, TransportProtocol};
use quinn::{
    Connection as QuinnConnection, Endpoint as QuinnEndpoint, ServerConfig as QuinnServerConfig,
    VarInt,
};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls_pemfile::{certs as load_certs, pkcs8_private_keys, rsa_private_keys};

pub use config::{EndpointRuntimeConfig, HttpRouteResolution};
pub use platform::{Runtime as PlatformRuntime, UnsupportedPlatform};
pub use protocol::{Http2Handshake, Http3Handshake, HttpHandshake, WebSocketHandshake};
pub use rawsocket::Serializer as RawSocketSerializer;
pub use wamp::{
    parse_message, ParseError as WampParseError, ParsedMessage, Payload as WampPayload, WampMessage,
};

static RUNTIME_MANAGER: OnceLock<RuntimeManager> = OnceLock::new();

const MAX_FRAME_LEN: u64 = 1 << 24;
const HTTP3_DEFAULT_BODY_LIMIT: u64 = 4 * 1024 * 1024;

/// Unique identifier for a registered listener.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct ListenerId(pub u32);

/// Unique identifier for an accepted connection.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct ConnectionId(pub u32);

/// Transport protocol negotiated for a connection.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum ConnectionProtocol {
    RawSocket,
    WebSocket,
    Http,
    Http2,
    Http3,
}

#[derive(Debug, Clone)]
pub struct HttpBodyHandle {
    payload: Arc<HttpBodyPayload>,
}

#[derive(Debug)]
enum HttpBodyPayload {
    Inline(Arc<[u8]>),
}

#[derive(Debug)]
pub struct HttpBodySlice {
    pub ptr: *const u8,
    pub len: usize,
}

impl HttpBodyHandle {
    pub fn empty() -> Self {
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(Arc::<[u8]>::from(&[][..]))),
        }
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(bytes.into_boxed_slice().into())),
        }
    }

    pub fn from_arc(bytes: Arc<[u8]>) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(bytes)),
        }
    }

    pub fn len(&self) -> usize {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => bytes.len(),
        }
    }

    pub fn as_arc(&self) -> Arc<[u8]> {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => Arc::clone(bytes),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn inline_bytes(&self) -> Option<&Arc<[u8]>> {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => Some(bytes),
        }
    }

    pub fn slice(&self, offset: usize, length: usize) -> Option<HttpBodySlice> {
        let total = self.len();
        if offset > total {
            return None;
        }
        let end = total.min(offset.saturating_add(length));
        let slice_len = end.saturating_sub(offset);
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => {
                let ptr = unsafe { bytes.as_ptr().add(offset) };
                Some(HttpBodySlice {
                    ptr,
                    len: slice_len,
                })
            }
        }
    }
}

pub struct HttpRequestSummary {
    pub method: String,
    pub target: String,
    pub path: String,
    pub query: Option<String>,
    pub protocol: String,
    pub version: u8,
    pub headers: Vec<(String, String)>,
    pub body: HttpBodyHandle,
    pub realm: Option<String>,
    pub procedure: Option<String>,
    pub route: Option<HttpRouteResolution>,
}

impl HttpRequestSummary {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        method: String,
        target: String,
        path: String,
        query: Option<String>,
        protocol: String,
        version: u8,
        headers: Vec<(String, String)>,
        body: HttpBodyHandle,
        realm: Option<String>,
        procedure: Option<String>,
        route: Option<HttpRouteResolution>,
    ) -> Self {
        Self {
            method,
            target,
            path,
            query,
            protocol,
            version,
            headers,
            body,
            realm,
            procedure,
            route,
        }
    }
}

pub struct HttpResponseHandle {
    connection_id: ConnectionId,
    sender: oneshot::Sender<HttpResponseDispatch>,
}

impl HttpResponseHandle {
    fn new(connection_id: ConnectionId, sender: oneshot::Sender<HttpResponseDispatch>) -> Self {
        Self {
            connection_id,
            sender,
        }
    }

    pub fn respond(self, response: HttpResponseDispatch) -> Result<(), Error> {
        self.sender
            .send(response)
            .map_err(|_| Error::Http3ResponseSend(self.connection_id))
    }
}

#[derive(Debug)]
pub struct HttpResponseDispatch {
    pub status: i32,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

/// Handle representing an accepted HTTP/3 bidirectional stream.
pub struct Http3BidiStream {
    id: u64,
    send: quinn::SendStream,
    recv: quinn::RecvStream,
}

impl Http3BidiStream {
    fn new(send: quinn::SendStream, recv: quinn::RecvStream) -> Self {
        let id = recv.id().index();
        Self { id, send, recv }
    }

    /// Returns the QUIC stream identifier.
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Splits the stream into its send/receive halves.
    pub fn into_parts(self) -> (quinn::SendStream, quinn::RecvStream) {
        (self.send, self.recv)
    }
}

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
    /// Operation not supported for negotiated protocol.
    #[error("connection {0:?} protocol {1:?} does not support this operation")]
    UnsupportedProtocol(ConnectionId, ConnectionProtocol),
    /// Connection handshake already consumed.
    #[error("connection {0:?} handshake already consumed")]
    HandshakeAlreadyTaken(ConnectionId),
    /// HTTP/3 connection handle is unavailable.
    #[error("connection {0:?} handle unavailable")]
    ConnectionHandleUnavailable(ConnectionId),
    /// HTTP/3 response channel closed or failed.
    #[error("failed to send http/3 response for connection {0:?}")]
    Http3ResponseSend(ConnectionId),
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
    tasks: Vec<JoinHandle<()>>,
    #[allow(dead_code)]
    http3_addr: Option<SocketAddr>,
    http3_endpoint: Option<QuinnEndpoint>,
    #[allow(dead_code)]
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
}

struct ConnectionEntry {
    #[allow(dead_code)]
    listener_id: ListenerId,
    #[allow(dead_code)]
    peer_addr: SocketAddr,
    protocol: ConnectionProtocol,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    record: ConnectionRecord,
}

enum ConnectionRecord {
    RawSocket {
        serializer: rawsocket::Serializer,
        max_exponent: u32,
        frames: Mutex<mpsc::Receiver<wamp::ParsedMessage>>,
        reader_task: JoinHandle<()>,
        writer_task: JoinHandle<()>,
        send_tx: UnboundedSender<OutboundFrame>,
    },
    WebSocketPending {
        handshake: Mutex<Option<protocol::WebSocketHandshake>>,
    },
    HttpPending {
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
    },
    Http2Pending {
        handshake: Mutex<Option<protocol::Http2Handshake>>,
    },
    Http3Pending {
        handshake: Mutex<Option<protocol::Http3Handshake>>,
        connection: Mutex<Option<Arc<quinn::Connection>>>,
        streams: Arc<Http3StreamChannels>,
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
    },
}

struct Http3StreamChannels {
    streams: Mutex<VecDeque<Http3BidiStream>>,
}

impl Http3StreamChannels {
    fn new() -> Self {
        Self {
            streams: Mutex::new(VecDeque::new()),
        }
    }

    fn push(&self, stream: Http3BidiStream) {
        self.streams.lock().unwrap().push_back(stream);
    }

    fn try_recv(&self) -> Option<Http3BidiStream> {
        self.streams.lock().unwrap().pop_front()
    }
}

struct QueuedHttpRequest {
    summary: HttpRequestSummary,
    response: HttpResponseHandle,
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

    fn http3_addr(&self, id: ListenerId) -> Result<Option<SocketAddr>, Error> {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&id)
            .map(|entry| entry.http3_addr)
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
        for mut entry in listener_entries {
            for task in entry.tasks {
                task.abort();
            }
            if let Some(endpoint) = entry.http3_endpoint.take() {
                endpoint.close(VarInt::from_u32(0), b"shutdown");
            }
        }

        let connection_entries: Vec<ConnectionEntry> = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .drain()
            .map(|(_, entry)| entry)
            .collect();
        for entry in connection_entries {
            match entry.record {
                ConnectionRecord::RawSocket {
                    reader_task,
                    writer_task,
                    ..
                } => {
                    reader_task.abort();
                    writer_task.abort();
                }
                ConnectionRecord::WebSocketPending { .. }
                | ConnectionRecord::HttpPending { .. }
                | ConnectionRecord::Http2Pending { .. }
                | ConnectionRecord::Http3Pending { .. } => {}
            }
        }
    }

    fn register_rawsocket_connection(
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
                    protocol: ConnectionProtocol::RawSocket,
                    endpoint_config,
                    record: ConnectionRecord::RawSocket {
                        serializer,
                        max_exponent,
                        frames: Mutex::new(frame_rx),
                        reader_task,
                        writer_task,
                        send_tx,
                    },
                },
            );
    }

    fn register_websocket_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        handshake: protocol::WebSocketHandshake,
        peer_addr: SocketAddr,
    ) {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::WebSocket,
                    endpoint_config,
                    record: ConnectionRecord::WebSocketPending {
                        handshake: Mutex::new(Some(handshake)),
                    },
                },
            );
    }

    fn register_http_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        peer_addr: SocketAddr,
    ) {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::Http,
                    endpoint_config,
                    record: ConnectionRecord::HttpPending {
                        pending_requests: Mutex::new(VecDeque::new()),
                    },
                },
            );
    }

    fn register_http2_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        handshake: protocol::Http2Handshake,
        peer_addr: SocketAddr,
    ) {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::Http2,
                    endpoint_config,
                    record: ConnectionRecord::Http2Pending {
                        handshake: Mutex::new(Some(handshake)),
                    },
                },
            );
    }

    fn register_http3_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        handshake: protocol::Http3Handshake,
        connection: Option<Arc<QuinnConnection>>,
        peer_addr: SocketAddr,
    ) -> Arc<Http3StreamChannels> {
        let streams = Arc::new(Http3StreamChannels::new());
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::Http3,
                    endpoint_config,
                    record: ConnectionRecord::Http3Pending {
                        handshake: Mutex::new(Some(handshake)),
                        connection: Mutex::new(connection),
                        streams: Arc::clone(&streams),
                        pending_requests: Mutex::new(VecDeque::new()),
                    },
                },
            );
        streams
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

    fn listener_config(
        &self,
        listener_id: ListenerId,
    ) -> Result<Arc<config::EndpointRuntimeConfig>, Error> {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&listener_id)
            .map(|entry| Arc::clone(&entry.endpoint_config))
            .ok_or(Error::ListenerNotFound(listener_id))
    }

    fn connection_exponent(&self, connection_id: ConnectionId) -> Result<u32, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::RawSocket { max_exponent, .. } => Ok(*max_exponent),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn connection_protocol(
        &self,
        connection_id: ConnectionId,
    ) -> Result<ConnectionProtocol, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| entry.protocol)
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
        match &entry.record {
            ConnectionRecord::RawSocket { frames, .. } => {
                let mut receiver = frames.lock().unwrap();
                match receiver.try_recv() {
                    Ok(message) => Ok(Some(message)),
                    Err(TryRecvError::Empty) => Ok(None),
                    Err(TryRecvError::Disconnected) => Ok(None),
                }
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
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
        match &entry.record {
            ConnectionRecord::RawSocket { send_tx, .. } => send_tx
                .send(frame)
                .map_err(|_| Error::ConnectionNotFound(connection_id)),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn take_websocket_handshake(
        &self,
        connection_id: ConnectionId,
    ) -> Result<protocol::WebSocketHandshake, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::WebSocketPending { handshake } => {
                let mut guard = handshake.lock().unwrap();
                guard
                    .take()
                    .ok_or(Error::HandshakeAlreadyTaken(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn take_http2_handshake(
        &self,
        connection_id: ConnectionId,
    ) -> Result<protocol::Http2Handshake, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http2Pending { handshake } => {
                let mut guard = handshake.lock().unwrap();
                guard
                    .take()
                    .ok_or(Error::HandshakeAlreadyTaken(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn take_http3_handshake(
        &self,
        connection_id: ConnectionId,
    ) -> Result<protocol::Http3Handshake, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http3Pending { handshake, .. } => {
                let mut guard = handshake.lock().unwrap();
                guard
                    .take()
                    .ok_or(Error::HandshakeAlreadyTaken(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn http3_connection(&self, connection_id: ConnectionId) -> Result<Arc<QuinnConnection>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http3Pending { connection, .. } => {
                let guard = connection.lock().unwrap();
                guard
                    .as_ref()
                    .cloned()
                    .ok_or(Error::ConnectionHandleUnavailable(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn poll_http3_stream(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<Http3BidiStream>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http3Pending { streams, .. } => Ok(streams.try_recv()),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn enqueue_http_request(
        &self,
        connection_id: ConnectionId,
        request: QueuedHttpRequest,
    ) -> Result<(), Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::HttpPending { pending_requests }
            | ConnectionRecord::Http3Pending {
                pending_requests, ..
            } => {
                pending_requests.lock().unwrap().push_back(request);
                Ok(())
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn poll_http_request(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<(HttpRequestSummary, HttpResponseHandle)>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::HttpPending { pending_requests }
            | ConnectionRecord::Http3Pending {
                pending_requests, ..
            } => Ok(pending_requests
                .lock()
                .unwrap()
                .pop_front()
                .map(|entry| (entry.summary, entry.response))),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }
}

fn start_http3_listener(
    listener_id: ListenerId,
    addr: SocketAddr,
    runtime_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
    sender: mpsc::Sender<ConnectionId>,
    handle: tokio::runtime::Handle,
) -> Result<(QuinnEndpoint, JoinHandle<()>, SocketAddr), Error> {
    let server_config = build_http3_server_config(&runtime_config)?;
    let endpoint = handle
        .block_on(async move { QuinnEndpoint::server(server_config, addr) })
        .map_err(Error::Io)?;
    let local_addr = endpoint.local_addr().map_err(Error::Io)?;

    let registry_for_task = Arc::clone(&registry);
    let runtime_for_task = Arc::clone(&runtime_config);
    let sender_for_task = sender.clone();
    let endpoint_for_task = endpoint.clone();
    let listener = handle.spawn(async move {
        loop {
            match endpoint_for_task.accept().await {
                Some(connecting) => match connecting.await {
                    Ok(connection) => {
                        let peer_addr = connection.remote_address();
                        let handshake = Http3Handshake::from_endpoint(&runtime_for_task);
                        let connection_id = registry_for_task.next_connection_id();
                        let connection = Arc::new(connection);
                        let streams = registry_for_task.register_http3_connection(
                            listener_id,
                            connection_id,
                            Arc::clone(&runtime_for_task),
                            handshake,
                            Some(Arc::clone(&connection)),
                            peer_addr,
                        );
                        let registry_for_connection = Arc::clone(&registry_for_task);
                        let endpoint_for_connection = Arc::clone(&runtime_for_task);
                        tokio::spawn(async move {
                            serve_http3_requests(
                                listener_id,
                                connection_id,
                                endpoint_for_connection,
                                registry_for_connection,
                                connection,
                                streams,
                            )
                            .await;
                        });
                        if sender_for_task.send(connection_id).await.is_err() {
                            break;
                        }
                    }
                    Err(err) => {
                        eprintln!(
                            "http3 connection failed for listener {:?}: {}",
                            listener_id, err
                        );
                    }
                },
                None => break,
            }
        }
    });

    Ok((endpoint, listener, local_addr))
}

fn build_http3_server_config(
    endpoint: &config::EndpointRuntimeConfig,
) -> Result<QuinnServerConfig, Error> {
    let (certs, key) = load_http3_identity(endpoint)?;
    QuinnServerConfig::with_single_cert(certs, key).map_err(|err| {
        Error::RouterConfigInvalid(format!(
            "endpoint {}:{} http3 certificate invalid: {}",
            endpoint.host, endpoint.port, err
        ))
    })
}

fn load_http3_identity(
    endpoint: &config::EndpointRuntimeConfig,
) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>), Error> {
    let cert_entry = endpoint.sni_certificates.first().ok_or_else(|| {
        Error::RouterConfigInvalid(format!(
            "endpoint {}:{} requires SNI certificate for http3",
            endpoint.host, endpoint.port
        ))
    })?;
    let mut cert_reader = Cursor::new(cert_entry.certificate_chain_pem.as_bytes());
    let certs = load_certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} failed to parse http3 certificate: {}",
                endpoint.host, endpoint.port, err
            ))
        })?;
    if certs.is_empty() {
        return Err(Error::RouterConfigInvalid(format!(
            "endpoint {}:{} http3 certificate chain empty",
            endpoint.host, endpoint.port
        )));
    }

    let private_key = {
        let mut key_reader = Cursor::new(cert_entry.private_key_pem.as_bytes());
        let mut keys = pkcs8_private_keys(&mut key_reader)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} failed to parse pkcs8 key for http3: {}",
                    endpoint.host, endpoint.port, err
                ))
            })?
            .into_iter()
            .map(|der| der.into())
            .collect::<Vec<_>>();
        if keys.is_empty() {
            let mut rsa_reader = Cursor::new(cert_entry.private_key_pem.as_bytes());
            keys = rsa_private_keys(&mut rsa_reader)
                .collect::<Result<Vec<_>, _>>()
                .map_err(|err| {
                    Error::RouterConfigInvalid(format!(
                        "endpoint {}:{} failed to parse rsa key for http3: {}",
                        endpoint.host, endpoint.port, err
                    ))
                })?
                .into_iter()
                .map(|der| der.into())
                .collect();
        }
        keys.into_iter().next().ok_or_else(|| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} http3 private key missing",
                endpoint.host, endpoint.port
            ))
        })?
    };

    Ok((certs, private_key))
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
    payload_len: usize,
    segments: Vec<Bytes>,
}

impl OutboundFrame {
    fn message(payload: Bytes) -> Self {
        let len = payload.len();
        Self {
            frame_type: 0,
            payload_len: len,
            segments: vec![payload],
        }
    }

    fn message_segments(segments: Vec<Bytes>) -> Self {
        let payload_len = segments.iter().map(|segment| segment.len()).sum();
        Self {
            frame_type: 0,
            payload_len,
            segments,
        }
    }

    fn control(frame_type: u8, payload: Bytes) -> Self {
        let len = payload.len();
        Self {
            frame_type,
            payload_len: len,
            segments: vec![payload],
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
            let header = match encode_frame_header(frame.frame_type, frame.payload_len) {
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

            for segment in frame.segments {
                if segment.is_empty() {
                    continue;
                }
                if let Err(err) = writer.write_all(&segment).await {
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
            let runtime_handle = view.handle.clone();
            let task = runtime_handle.clone().spawn(async move {
                let listener = tokio::net::TcpListener::from_std(std_listener)
                    .expect("failed to convert listener to tokio");
                let tx = async_sender;
                loop {
                    match listener.accept().await {
                        Ok((stream, addr)) => {
                            match protocol::negotiate_connection(stream, &runtime_config_for_task)
                                .await
                            {
                                Ok(protocol::NegotiatedConnection::RawSocket(negotiated)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_rawsocket_connection(
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
                                Ok(protocol::NegotiatedConnection::WebSocket(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_websocket_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        handshake,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::Http2(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http2_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        handshake,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::Http3(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http3_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        handshake,
                                        None,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::Http(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        addr,
                                    );
                                    let registry_for_connection = Arc::clone(&accept_registry);
                                    let endpoint_for_connection =
                                        Arc::clone(&runtime_config_for_task);
                                    let http_handle = runtime_handle.clone();
                                    http_handle.spawn(async move {
                                        serve_http_connection(
                                            listener_id,
                                            connection_id,
                                            handshake,
                                            endpoint_for_connection,
                                            registry_for_connection,
                                        )
                                        .await;
                                    });
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Err(protocol::NegotiationError::Timeout) => {
                                    eprintln!(
                                        "protocol negotiation timed out for connection from {}",
                                        addr
                                    );
                                }
                                Err(protocol::NegotiationError::Protocol(msg)) => {
                                    eprintln!(
                                        "protocol negotiation failed for connection from {}: {}",
                                        addr, msg
                                    );
                                }
                                Err(protocol::NegotiationError::Io(err)) => {
                                    eprintln!(
                                        "protocol negotiation IO error for connection from {}: {}",
                                        addr, err
                                    );
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }
            });

            let mut listener_tasks = vec![task];
            let mut http3_addr = None;
            let mut http3_endpoint = None;
            if runtime_config.supports_protocol(TransportProtocol::Http3) {
                let mut desired_addr = local_addr;
                if let Some(http_settings) = runtime_config.http_settings() {
                    if let Some(http3_settings) = &http_settings.http3 {
                        if let Some(port) = http3_settings.port {
                            desired_addr.set_port(port);
                        }
                    }
                }
                match start_http3_listener(
                    listener_id,
                    desired_addr,
                    Arc::clone(&runtime_config),
                    Arc::clone(&view.registry),
                    sender.clone(),
                    view.handle.clone(),
                ) {
                    Ok((endpoint, task, bound_addr)) => {
                        http3_addr = Some(bound_addr);
                        http3_endpoint = Some(endpoint);
                        listener_tasks.push(task);
                    }
                    Err(err) => {
                        eprintln!(
                            "failed to start http3 listener on {}: {}",
                            desired_addr, err
                        );
                    }
                }
            }

            let entry = ListenerEntry {
                addr: local_addr,
                receiver: Mutex::new(Some(receiver)),
                _sender: sender,
                tasks: listener_tasks,
                http3_addr,
                http3_endpoint,
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

/// Returns the bound HTTP/3 port for the given listener, if available.
pub fn listener_http3_port(listener_id: ListenerId) -> Result<Option<u16>, Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.http3_addr(listener_id))
        .map(|addr| addr.map(|socket| socket.port()))
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

/// Returns the negotiated transport protocol for a connection.
pub fn connection_protocol(connection_id: ConnectionId) -> Result<ConnectionProtocol, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_protocol(connection_id))
}

/// Retrieves and consumes a pending WebSocket handshake for a connection.
pub fn connection_take_websocket_handshake(
    connection_id: ConnectionId,
) -> Result<protocol::WebSocketHandshake, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_websocket_handshake(connection_id))
}

/// Retrieves and consumes a pending HTTP/2 handshake for a connection.
pub fn connection_take_http2_handshake(
    connection_id: ConnectionId,
) -> Result<protocol::Http2Handshake, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_http2_handshake(connection_id))
}

/// Retrieves and consumes a pending HTTP/3 handshake for a connection.
pub fn connection_take_http3_handshake(
    connection_id: ConnectionId,
) -> Result<protocol::Http3Handshake, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_http3_handshake(connection_id))
}

/// Registers a pending HTTP/3 handshake for testing and diagnostics.
pub fn register_http3_pending(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    handshake: protocol::Http3Handshake,
    peer_addr: SocketAddr,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let endpoint_config = state.registry.listener_config(listener_id)?;
        state.registry.register_http3_connection(
            listener_id,
            connection_id,
            endpoint_config,
            handshake,
            None,
            peer_addr,
        );
        Ok(())
    })
}

/// Provides a shared handle to the HTTP/3 connection for a given connection id.
pub fn connection_http3_connection(
    connection_id: ConnectionId,
) -> Result<Arc<QuinnConnection>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.http3_connection(connection_id))
}

/// Attempts to retrieve the next pending HTTP/3 bidirectional stream.
pub fn connection_http3_poll_stream(
    connection_id: ConnectionId,
) -> Result<Option<Http3BidiStream>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.poll_http3_stream(connection_id))
}

/// Attempts to retrieve the next pending HTTP request metadata.
pub fn connection_http_poll_request(
    connection_id: ConnectionId,
) -> Result<Option<(HttpRequestSummary, HttpResponseHandle)>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.poll_http_request(connection_id))
}

/// Attempts to retrieve the next pending HTTP/3 request metadata.
pub fn connection_http3_poll_request(
    connection_id: ConnectionId,
) -> Result<Option<(HttpRequestSummary, HttpResponseHandle)>, Error> {
    connection_http_poll_request(connection_id)
}

#[cfg(feature = "ffi-test")]
pub fn register_http_request(
    connection_id: ConnectionId,
    request: HttpRequestSummary,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
        let handle = state.handle.clone();
        handle.spawn(async move {
            let _ = rx.await;
        });
        let queued = QueuedHttpRequest {
            summary: request,
            response: HttpResponseHandle::new(connection_id, tx),
        };
        state.registry.enqueue_http_request(connection_id, queued)
    })
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

/// Sends an HTTP response to the client. Currently unsupported.
pub fn send_http_response(
    connection_id: ConnectionId,
    status: i32,
    headers: &[(String, String)],
    body: &[u8],
) -> Result<(), Error> {
    let _ = (status, headers, body);
    Err(Error::UnsupportedProtocol(
        connection_id,
        ConnectionProtocol::Http,
    ))
}

/// Enqueues a WAMP message composed of multiple payload segments.
pub fn send_wamp_segments(connection_id: ConnectionId, segments: Vec<Bytes>) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        state
            .registry
            .enqueue_frame(connection_id, OutboundFrame::message_segments(segments))
    })
}

pub fn spawn_http_response(
    handshake: protocol::HttpHandshake,
    status: i32,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    let version = handshake.version();
    manager.with_state(|state| {
        let handle = state.handle.clone();
        handle.spawn(async move {
            let stream = handshake.into_stream();
            if let Err(err) =
                protocol::write_http_response(stream, version, status, headers, body).await
            {
                eprintln!("failed to send http response: {}", err);
            }
        });
        Ok(())
    })
}

async fn serve_http_connection(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    handshake: protocol::HttpHandshake,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) {
    let (stream, request, body) = handshake.into_parts();
    let mut reader = BufReader::new(stream);
    let mut pending = Some((request, body));

    loop {
        let (request, body) = match pending.take() {
            Some(value) => value,
            None => match protocol::read_http_request(&mut reader, &endpoint_config).await {
                Ok(Some(value)) => value,
                Ok(None) => break,
                Err(err) => {
                    eprintln!(
                        "http/1 connection read error for listener {:?}: {:?}",
                        listener_id, err
                    );
                    break;
                }
            },
        };

        let protocol::HttpRequest {
            method,
            target,
            version,
            headers,
        } = request;
        let normalized_method = method.to_uppercase();
        let (path, query) = protocol::split_http_target(&target);
        let normalized_path = if path.is_empty() { "/" } else { path };
        let normalized_path_string = normalized_path.to_string();
        let query_owned = query.map(|value| value.to_string());
        let keep_alive = should_keep_alive(version, &headers);
        let protocol_label = format!("http/1.{}", version);

        match endpoint_config.match_http_route(
            &normalized_path_string,
            query,
            &normalized_method,
            &protocol_label,
        ) {
            HttpRouteMatch::Resolved(resolution) => {
                let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
                let body_handle = HttpBodyHandle::from_bytes(body);
                let summary = HttpRequestSummary::new(
                    method,
                    target,
                    normalized_path_string.clone(),
                    query_owned,
                    protocol_label.clone(),
                    version,
                    headers,
                    body_handle,
                    Some(resolution.realm.clone()),
                    Some(resolution.procedure.clone()),
                    Some(resolution),
                );
                let queued = QueuedHttpRequest {
                    summary,
                    response: HttpResponseHandle::new(connection_id, tx),
                };
                if let Err(err) = registry.enqueue_http_request(connection_id, queued) {
                    eprintln!(
                        "failed to enqueue http request for listener {:?}: {}",
                        listener_id, err
                    );
                    break;
                }
                match rx.await {
                    Ok(mut dispatch) => {
                        if let Err(err) =
                            send_http_dispatch(&mut reader, version, keep_alive, &mut dispatch)
                                .await
                        {
                            eprintln!(
                                "failed to send http response for listener {:?}: {}",
                                listener_id, err
                            );
                            break;
                        }
                    }
                    Err(_) => {
                        let _ = send_http_simple_response(
                            &mut reader,
                            version,
                            StatusCode::INTERNAL_SERVER_ERROR,
                            keep_alive,
                            b"http request cancelled",
                            &[],
                        )
                        .await;
                        break;
                    }
                }
            }
            HttpRouteMatch::MethodNotAllowed { allowed_methods } => {
                let allow_value = allowed_methods.join(", ");
                if let Err(err) = send_http_simple_response(
                    &mut reader,
                    version,
                    StatusCode::METHOD_NOT_ALLOWED,
                    keep_alive,
                    b"method not allowed",
                    &[("Allow", allow_value.as_str())],
                )
                .await
                {
                    eprintln!(
                        "failed to send 405 response for listener {:?}: {}",
                        listener_id, err
                    );
                    break;
                }
            }
            HttpRouteMatch::NotFound => {
                if let Err(err) = send_http_simple_response(
                    &mut reader,
                    version,
                    StatusCode::NOT_FOUND,
                    keep_alive,
                    b"route not found",
                    &[],
                )
                .await
                {
                    eprintln!(
                        "failed to send 404 response for listener {:?}: {}",
                        listener_id, err
                    );
                    break;
                }
            }
        }

        if !keep_alive {
            break;
        }
    }
}

async fn send_http_dispatch(
    reader: &mut BufReader<tokio::net::TcpStream>,
    version: u8,
    keep_alive: bool,
    dispatch: &mut HttpResponseDispatch,
) -> Result<(), String> {
    ensure_connection_header(&mut dispatch.headers, keep_alive, version);
    protocol::write_http_response_shared(
        reader.get_mut(),
        version,
        dispatch.status,
        &dispatch.headers,
        &dispatch.body,
    )
    .await
    .map_err(|err| err.to_string())
}

async fn send_http_simple_response(
    reader: &mut BufReader<tokio::net::TcpStream>,
    version: u8,
    status: StatusCode,
    keep_alive: bool,
    body: &[u8],
    extra_headers: &[(&str, &str)],
) -> Result<(), String> {
    let mut headers: Vec<(String, String)> = extra_headers
        .iter()
        .map(|(name, value)| (name.to_string(), value.to_string()))
        .collect();
    ensure_connection_header(&mut headers, keep_alive, version);
    protocol::write_http_response_shared(
        reader.get_mut(),
        version,
        status.as_u16() as i32,
        &headers,
        body,
    )
    .await
    .map_err(|err| err.to_string())
}

fn ensure_connection_header(headers: &mut Vec<(String, String)>, keep_alive: bool, version: u8) {
    if headers
        .iter()
        .any(|(name, _)| name.eq_ignore_ascii_case("connection"))
    {
        return;
    }
    if keep_alive && version >= 1 {
        headers.push(("Connection".into(), "keep-alive".into()));
    } else {
        headers.push(("Connection".into(), "close".into()));
    }
}

fn should_keep_alive(version: u8, headers: &[(String, String)]) -> bool {
    let directive = headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("connection"))
        .map(|(_, value)| value.as_str());
    match version {
        0 => directive
            .map(|value| header_has_token(value, "keep-alive"))
            .unwrap_or(false),
        _ => directive
            .map(|value| !header_has_token(value, "close"))
            .unwrap_or(true),
    }
}

fn header_has_token(value: &str, needle: &str) -> bool {
    value
        .split(',')
        .map(|token| token.trim())
        .any(|token| token.eq_ignore_ascii_case(needle))
}

async fn serve_http3_requests(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
    connection: Arc<QuinnConnection>,
    streams: Arc<Http3StreamChannels>,
) {
    let mut h3_conn = match h3::server::builder()
        .build(H3QuinnConnection::new(connection.deref().clone()))
        .await
    {
        Ok(conn) => conn,
        Err(err) => {
            eprintln!(
                "http3 handshake failed for listener {:?}: {}",
                listener_id, err
            );
            return;
        }
    };

    loop {
        match h3_conn.accept().await {
            Ok(Some(resolver)) => match resolver.resolve_request().await {
                Ok((request, stream)) => {
                    if let Err(err) = process_http3_request(
                        connection_id,
                        request,
                        stream,
                        Arc::clone(&endpoint_config),
                        Arc::clone(&registry),
                    )
                    .await
                    {
                        eprintln!(
                            "http3 request error for listener {:?}: {}",
                            listener_id, err
                        );
                    }
                }
                Err(err) => {
                    eprintln!(
                        "http3 request resolve error for listener {:?}: {}",
                        listener_id, err
                    );
                }
            },
            Ok(None) => break,
            Err(err) => {
                eprintln!(
                    "http3 accept loop stopped for listener {:?}: {}",
                    listener_id, err
                );
                break;
            }
        }
    }

    drop(streams);
}

async fn process_http3_request(
    connection_id: ConnectionId,
    request: HttpRequest<()>,
    mut stream: H3RequestStream<h3_quinn::BidiStream<Bytes>, Bytes>,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) -> Result<(), String> {
    let method = request.method().as_str().to_string();
    let normalized_method = method.to_uppercase();
    let target = request
        .uri()
        .path_and_query()
        .map(|pq| pq.as_str().to_string())
        .unwrap_or_else(|| request.uri().path().to_string());
    let (path, query) = split_target_components(&target);
    let headers = flatten_headers(request.headers());

    let max_body = endpoint_config
        .max_http_content_length
        .unwrap_or(HTTP3_DEFAULT_BODY_LIMIT);
    let mut body = Vec::new();
    while let Some(mut chunk) = stream
        .recv_data()
        .await
        .map_err(|err| format!("failed to read http3 body: {}", err))?
    {
        while chunk.has_remaining() {
            let slice = chunk.chunk();
            let new_len = body.len() as u64 + slice.len() as u64;
            if new_len > max_body {
                send_plain_response(
                    &mut stream,
                    StatusCode::PAYLOAD_TOO_LARGE,
                    b"payload too large",
                    &[],
                )
                .await?;
                return Ok(());
            }
            body.extend_from_slice(slice);
            let advance = slice.len();
            chunk.advance(advance);
        }
    }

    match endpoint_config.match_http_route(&path, query.as_deref(), &normalized_method, "http3") {
        HttpRouteMatch::Resolved(resolution) => {
            let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
            let body_handle = HttpBodyHandle::from_bytes(body);
            let summary = HttpRequestSummary::new(
                normalized_method,
                target,
                path,
                query,
                "http/3".to_string(),
                3,
                headers,
                body_handle,
                Some(resolution.realm.clone()),
                Some(resolution.procedure.clone()),
                Some(resolution),
            );
            let queued = QueuedHttpRequest {
                summary,
                response: HttpResponseHandle::new(connection_id, tx),
            };
            registry
                .enqueue_http_request(connection_id, queued)
                .map_err(|err| err.to_string())?;
            tokio::spawn(async move {
                let mut response_stream = stream;
                match rx.await {
                    Ok(dispatch) => {
                        if let Err(err) =
                            send_http3_response_from_dispatch(&mut response_stream, dispatch).await
                        {
                            eprintln!(
                                "failed to send http3 response for connection {:?}: {}",
                                connection_id, err
                            );
                        }
                    }
                    Err(_) => {
                        let _ = send_plain_response(
                            &mut response_stream,
                            StatusCode::INTERNAL_SERVER_ERROR,
                            b"http/3 request cancelled",
                            &[],
                        )
                        .await;
                    }
                }
            });
            Ok(())
        }
        HttpRouteMatch::MethodNotAllowed { allowed_methods } => {
            let allow_value = allowed_methods.join(", ");
            send_plain_response(
                &mut stream,
                StatusCode::METHOD_NOT_ALLOWED,
                b"method not allowed",
                &[("allow", allow_value.as_str())],
            )
            .await
        }
        HttpRouteMatch::NotFound => {
            send_plain_response(&mut stream, StatusCode::NOT_FOUND, b"route not found", &[]).await
        }
    }
}

fn flatten_headers(headers: &http::HeaderMap) -> Vec<(String, String)> {
    headers
        .iter()
        .map(|(name, value)| {
            let header_value = value
                .to_str()
                .map(|s| s.to_string())
                .unwrap_or_else(|_| String::new());
            (name.as_str().to_string(), header_value)
        })
        .collect()
}

fn split_target_components(target: &str) -> (String, Option<String>) {
    match target.split_once('?') {
        Some((path, query)) => (path.to_string(), Some(query.to_string())),
        None => (target.to_string(), None),
    }
}

#[allow(dead_code)]
fn http_summary_from_handshake(
    handshake: &protocol::HttpHandshake,
    route: &config::HttpRouteResolution,
) -> HttpRequestSummary {
    let (path, query) = protocol::split_http_target(&handshake.request.target);
    let normalized_path = if path.is_empty() { "/" } else { path };
    let body_handle = HttpBodyHandle::from_bytes(handshake.body.clone());
    HttpRequestSummary::new(
        handshake.request.method.clone(),
        handshake.request.target.clone(),
        normalized_path.to_string(),
        query.map(|value| value.to_string()),
        format!("http/1.{}", handshake.request.version),
        handshake.request.version,
        handshake
            .request
            .headers
            .iter()
            .map(|(name, value)| (name.clone(), value.clone()))
            .collect(),
        body_handle,
        Some(route.realm.clone()),
        Some(route.procedure.clone()),
        Some(route.clone()),
    )
}

async fn send_plain_response(
    stream: &mut H3RequestStream<h3_quinn::BidiStream<Bytes>, Bytes>,
    status: StatusCode,
    body: &[u8],
    headers: &[(&str, &str)],
) -> Result<(), String> {
    let mut builder = HttpResponse::builder().status(status);
    {
        let header_map = builder.headers_mut().expect("headers available");
        for (name, value) in headers {
            if let (Ok(name), Ok(value)) = (
                HeaderName::from_bytes(name.as_bytes()),
                HeaderValue::from_str(value),
            ) {
                header_map.insert(name, value);
            }
        }
        if let Ok(len_value) = HeaderValue::from_str(&body.len().to_string()) {
            header_map.insert(CONTENT_LENGTH, len_value);
        }
    }
    let response = builder.body(()).map_err(|err| err.to_string())?;
    stream
        .send_response(response)
        .await
        .map_err(|err| err.to_string())?;
    if !body.is_empty() {
        stream
            .send_data(Bytes::copy_from_slice(body))
            .await
            .map_err(|err| err.to_string())?;
    }
    stream.finish().await.map_err(|err| err.to_string())?;
    Ok(())
}

async fn send_http3_response_from_dispatch(
    stream: &mut H3RequestStream<h3_quinn::BidiStream<Bytes>, Bytes>,
    dispatch: HttpResponseDispatch,
) -> Result<(), String> {
    let clamped = dispatch.status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let mut builder = HttpResponse::builder().status(status_code);
    {
        let header_map = builder.headers_mut().expect("headers available");
        for (name, value) in &dispatch.headers {
            if let (Ok(name), Ok(value)) = (
                HeaderName::from_bytes(name.as_bytes()),
                HeaderValue::from_str(value),
            ) {
                header_map.insert(name, value);
            }
        }
        if let Ok(len_value) = HeaderValue::from_str(&dispatch.body.len().to_string()) {
            header_map.insert(CONTENT_LENGTH, len_value);
        }
    }
    let response = builder.body(()).map_err(|err| err.to_string())?;
    stream
        .send_response(response)
        .await
        .map_err(|err| err.to_string())?;
    if !dispatch.body.is_empty() {
        stream
            .send_data(Bytes::from(dispatch.body))
            .await
            .map_err(|err| err.to_string())?;
    }
    stream.finish().await.map_err(|err| err.to_string())?;
    Ok(())
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
