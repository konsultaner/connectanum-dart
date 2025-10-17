//! Tokio based runtime that backs the connectanum native transport.

use std::{
    collections::HashMap,
    net::{SocketAddr, ToSocketAddrs},
    sync::{
        atomic::{AtomicU32, Ordering},
        Arc, Mutex, OnceLock,
    },
    time::Duration,
};

use thiserror::Error;
use tokio::{net::TcpStream as TokioTcpStream, runtime::Runtime, sync::mpsc, task::JoinHandle};

mod config;
mod platform;

pub use config::EndpointRuntimeConfig;
pub use platform::{Runtime as PlatformRuntime, UnsupportedPlatform};

static RUNTIME_MANAGER: OnceLock<RuntimeManager> = OnceLock::new();

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
    stream: Mutex<Option<TokioTcpStream>>,
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
        let entries: Vec<ListenerEntry> = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .drain()
            .map(|(_, entry)| entry)
            .collect();
        for entry in entries {
            entry.task.abort();
        }
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .clear();
    }

    fn register_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        stream: TokioTcpStream,
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
                    endpoint_config,
                    stream: Mutex::new(Some(stream)),
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

    fn take_stream(&self, connection_id: ConnectionId) -> Result<TokioTcpStream, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        let mut guard = entry.stream.lock().unwrap();
        guard.take().ok_or(Error::ConnectionNotFound(connection_id))
    }
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
                            let connection_id = accept_registry.next_connection_id();
                            let _ = stream.set_nodelay(true);
                            accept_registry.register_connection(
                                listener_id,
                                connection_id,
                                Arc::clone(&runtime_config_for_task),
                                stream,
                                addr,
                            );
                            if tx.send(connection_id).await.is_err() {
                                break;
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
    connection_runtime_config(connection_id).map(|config| config.max_rawsocket_size_exponent)
}

/// Takes ownership of the accepted TCP stream for the given connection.
pub fn take_connection_stream(connection_id: ConnectionId) -> Result<TokioTcpStream, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_stream(connection_id))
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
    use tokio::sync::mpsc::error::TryRecvError;

    fn test_guard() -> std::sync::MutexGuard<'static, ()> {
        static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
        GUARD.get_or_init(|| Mutex::new(())).lock().unwrap()
    }

    #[test]
    fn apply_router_config_stores_config() {
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
        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
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

        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        drop(stream);

        let connection_id = receiver.recv().await.expect("connection delivered");
        let config = connection_runtime_config(connection_id).expect("config available");
        assert_eq!(config.max_rawsocket_size_exponent, 30);
        assert_eq!(config.max_rawsocket_size, 1u64 << 30);
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
    async fn connection_stream_can_be_taken_once() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","idle_timeout_ms":1000,"max_rawsocket_size_exponent":16}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let client = tokio::net::TcpStream::connect(addr).await.unwrap();

        let connection_id = receiver.recv().await.expect("connection delivered");
        let stream = take_connection_stream(connection_id).expect("stream available");
        let peer = stream.peer_addr().unwrap();
        assert_eq!(peer, client.local_addr().unwrap());

        drop(stream);
        drop(client);

        let err = take_connection_stream(connection_id).expect_err("second take fails");
        assert!(matches!(err, Error::ConnectionNotFound(ConnectionId(_))));

        shutdown().unwrap();
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
