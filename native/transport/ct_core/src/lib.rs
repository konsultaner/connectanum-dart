//! Tokio based runtime that backs the connectanum native transport.

use std::{
    collections::{HashMap, VecDeque},
    io::{self, Cursor, Write},
    net::{SocketAddr, ToSocketAddrs},
    ops::Deref,
    sync::{
        atomic::{AtomicU32, AtomicU64, Ordering},
        Arc, Mutex, OnceLock,
    },
    time::{Duration, Instant},
};

use base64::{engine::general_purpose::STANDARD as Base64Engine, Engine as _};
use bytes::{Buf, Bytes, BytesMut};
use h2::{
    server::{self as h2_server, SendResponse as H2SendResponse},
    RecvStream as H2RecvStream,
};
use h3::{
    error::Code as H3ErrorCode, quic::BidiStream as H3BidiStreamTrait,
    server::RequestStream as H3RequestStream,
};
use h3_quinn::Connection as H3QuinnConnection;
use http::{
    header::{HeaderName, HeaderValue, CONTENT_LENGTH},
    Request as HttpRequest, Response as HttpResponse, StatusCode,
};
use http02::{
    header::{HeaderName as Http2HeaderName, HeaderValue as Http2HeaderValue},
    Request as Http2Request, Response as Http2Response, StatusCode as Http2StatusCode,
};
use sha1::{Digest, Sha1};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt, BufReader},
    net::{
        tcp::{OwnedReadHalf, OwnedWriteHalf},
        TcpStream as TokioTcpStream,
    },
    runtime::Runtime,
    sync::{
        mpsc::{self, error::TryRecvError, UnboundedReceiver, UnboundedSender},
        oneshot,
    },
    task::JoinHandle,
    time,
};

use crate::http_body::{spawn_http1_streaming_body, Http1BodyReclaim, StreamingError};

mod config;
mod http1_stream;
mod http_body;
mod http_stream;
mod platform;
mod protocol;
mod rawsocket;
mod wamp;

use config::{HttpRouteMatch, TransportProtocol};
use quinn::{
    Connection as QuinnConnection, Endpoint as QuinnEndpoint, ServerConfig as QuinnServerConfig,
    VarInt,
};
use quinn_proto::crypto::rustls::QuicServerConfig as QuinnRustlsServerConfig;
use rustls::{
    pki_types::{CertificateDer, PrivateKeyDer},
    ServerConfig as RustlsServerConfig,
};
use rustls_pemfile::{certs as load_certs, pkcs8_private_keys, rsa_private_keys};

type H3QuicBidiStream = h3_quinn::BidiStream<Bytes>;
type H3ServerStream<S> = H3RequestStream<S, Bytes>;
type H3ServerBidiStream = H3ServerStream<H3QuicBidiStream>;
type H3ServerSendStream =
    H3ServerStream<<H3QuicBidiStream as H3BidiStreamTrait<Bytes>>::SendStream>;
type H3ServerRecvStream =
    H3ServerStream<<H3QuicBidiStream as H3BidiStreamTrait<Bytes>>::RecvStream>;

const HTTP_STREAM_IDLE_FALLBACK: Duration = Duration::from_secs(10);
const HTTP_STREAM_TOTAL_FALLBACK: Duration = Duration::from_secs(40);
const HTTP_STREAM_TOTAL_MULTIPLIER: u32 = 4;

fn http_stream_timeouts(config: &config::EndpointRuntimeConfig) -> (Duration, Duration) {
    let idle = config.idle_timeout.unwrap_or(HTTP_STREAM_IDLE_FALLBACK);
    let total = idle
        .checked_mul(HTTP_STREAM_TOTAL_MULTIPLIER)
        .unwrap_or(HTTP_STREAM_TOTAL_FALLBACK);
    let total = if total.is_zero() {
        HTTP_STREAM_TOTAL_FALLBACK
    } else {
        total
    };
    (idle, total)
}

pub use config::{EndpointRuntimeConfig, HttpRouteResolution};
pub use http1_stream::HttpBodyPhase;
pub use http_body::StreamingBodyState;
pub use http_stream::{
    response_stream_channel, ResponseStreamError, ResponseStreamFrame, ResponseStreamReader,
    ResponseStreamWriter, RESPONSE_STREAM_BUFFER,
};

/// Reasons describing why an HTTP/2 or HTTP/3 connection closed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HttpConnectionCloseReason {
    Graceful,
    GoAway,
    IdleTimeout,
    BodyTimeout,
    ProtocolError,
    Internal,
}

/// Lifecycle event emitted whenever an HTTP/2 or HTTP/3 connection terminates.
#[derive(Debug, Clone)]
pub struct HttpConnectionEvent {
    pub connection_id: ConnectionId,
    pub protocol: ConnectionProtocol,
    pub reason: HttpConnectionCloseReason,
    pub request_count: u32,
    pub idle_timeouts: u32,
    pub body_timeouts: u32,
    pub backpressure_events: u32,
    pub max_backpressure_depth: u32,
    pub goaway_events: u32,
    pub detail: Option<String>,
}

#[derive(Debug)]
struct HttpConnectionStats {
    protocol: ConnectionProtocol,
    requests: AtomicU32,
    idle_timeouts: AtomicU32,
    body_timeouts: AtomicU32,
    backpressure_events: AtomicU32,
    max_backpressure_depth: AtomicU32,
    goaway_events: AtomicU32,
    close_reason: Mutex<Option<(HttpConnectionCloseReason, Option<String>)>>,
}

impl HttpConnectionStats {
    fn new(protocol: ConnectionProtocol) -> Arc<Self> {
        Arc::new(Self {
            protocol,
            requests: AtomicU32::new(0),
            idle_timeouts: AtomicU32::new(0),
            body_timeouts: AtomicU32::new(0),
            backpressure_events: AtomicU32::new(0),
            max_backpressure_depth: AtomicU32::new(0),
            goaway_events: AtomicU32::new(0),
            close_reason: Mutex::new(None),
        })
    }

    fn record_request(&self) {
        self.requests.fetch_add(1, Ordering::SeqCst);
    }

    fn record_idle_timeout(&self, detail: Option<String>) {
        self.idle_timeouts.fetch_add(1, Ordering::SeqCst);
        self.set_close_reason(HttpConnectionCloseReason::IdleTimeout, detail);
    }

    fn record_body_timeout(&self, detail: Option<String>) {
        self.body_timeouts.fetch_add(1, Ordering::SeqCst);
        self.set_close_reason(HttpConnectionCloseReason::BodyTimeout, detail);
    }

    fn record_backpressure(&self, depth: usize) {
        self.backpressure_events.fetch_add(1, Ordering::SeqCst);
        let depth_u32 = depth.min(u32::MAX as usize) as u32;
        let _ = self.max_backpressure_depth.fetch_update(
            Ordering::SeqCst,
            Ordering::SeqCst,
            |current| {
                if depth_u32 > current {
                    Some(depth_u32)
                } else {
                    None
                }
            },
        );
    }

    fn record_goaway(&self, detail: Option<String>) {
        self.goaway_events.fetch_add(1, Ordering::SeqCst);
        self.set_close_reason(HttpConnectionCloseReason::GoAway, detail);
    }

    fn set_close_reason(&self, reason: HttpConnectionCloseReason, detail: Option<String>) {
        let mut guard = self.close_reason.lock().unwrap();
        if guard.is_none() {
            *guard = Some((reason, detail));
        }
    }

    fn finalize(
        &self,
        connection_id: ConnectionId,
        fallback_reason: HttpConnectionCloseReason,
        fallback_detail: Option<String>,
    ) -> HttpConnectionEvent {
        let stored = self.close_reason.lock().unwrap().take();
        let (reason, detail) = stored.unwrap_or((fallback_reason, fallback_detail));
        HttpConnectionEvent {
            connection_id,
            protocol: self.protocol,
            reason,
            request_count: self.requests.load(Ordering::SeqCst),
            idle_timeouts: self.idle_timeouts.load(Ordering::SeqCst),
            body_timeouts: self.body_timeouts.load(Ordering::SeqCst),
            backpressure_events: self.backpressure_events.load(Ordering::SeqCst),
            max_backpressure_depth: self.max_backpressure_depth.load(Ordering::SeqCst),
            goaway_events: self.goaway_events.load(Ordering::SeqCst),
            detail,
        }
    }
}

#[derive(Default)]
struct HttpMetrics {
    total_events: AtomicU64,
    graceful: AtomicU64,
    goaway: AtomicU64,
    idle_timeouts: AtomicU64,
    body_timeouts: AtomicU64,
    protocol_errors: AtomicU64,
    internal_errors: AtomicU64,
    backpressure_events: AtomicU64,
    max_backpressure_depth: AtomicU32,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct HttpMetricsSnapshot {
    pub total_events: u64,
    pub graceful_events: u64,
    pub goaway_events: u64,
    pub idle_timeout_events: u64,
    pub body_timeout_events: u64,
    pub protocol_error_events: u64,
    pub internal_error_events: u64,
    pub backpressure_events: u64,
    pub max_backpressure_depth: u32,
}

impl HttpMetrics {
    fn record(&self, event: &HttpConnectionEvent) {
        self.total_events.fetch_add(1, Ordering::SeqCst);
        self.backpressure_events
            .fetch_add(event.backpressure_events as u64, Ordering::SeqCst);
        let depth = event.max_backpressure_depth;
        if depth > 0 {
            let _ = self.max_backpressure_depth.fetch_update(
                Ordering::SeqCst,
                Ordering::SeqCst,
                |current| {
                    if depth > current {
                        Some(depth)
                    } else {
                        None
                    }
                },
            );
        }
        match event.reason {
            HttpConnectionCloseReason::Graceful => {
                self.graceful.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::GoAway => {
                self.goaway.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::IdleTimeout => {
                self.idle_timeouts.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::BodyTimeout => {
                self.body_timeouts.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::ProtocolError => {
                self.protocol_errors.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::Internal => {
                self.internal_errors.fetch_add(1, Ordering::SeqCst);
            }
        }
    }

    fn snapshot(&self) -> HttpMetricsSnapshot {
        HttpMetricsSnapshot {
            total_events: self.total_events.load(Ordering::SeqCst),
            graceful_events: self.graceful.load(Ordering::SeqCst),
            goaway_events: self.goaway.load(Ordering::SeqCst),
            idle_timeout_events: self.idle_timeouts.load(Ordering::SeqCst),
            body_timeout_events: self.body_timeouts.load(Ordering::SeqCst),
            protocol_error_events: self.protocol_errors.load(Ordering::SeqCst),
            internal_error_events: self.internal_errors.load(Ordering::SeqCst),
            backpressure_events: self.backpressure_events.load(Ordering::SeqCst),
            max_backpressure_depth: self.max_backpressure_depth.load(Ordering::SeqCst),
        }
    }
}

static HTTP_METRICS: OnceLock<HttpMetrics> = OnceLock::new();

fn http_metrics() -> &'static HttpMetrics {
    HTTP_METRICS.get_or_init(HttpMetrics::default)
}

pub fn http_metrics_snapshot() -> HttpMetricsSnapshot {
    http_metrics().snapshot()
}

fn record_http_metrics(event: &HttpConnectionEvent) {
    http_metrics().record(event);
}

pub use platform::{Runtime as PlatformRuntime, UnsupportedPlatform};
pub use protocol::{Http2Handshake, Http3Handshake, HttpHandshake, WebSocketHandshake};
pub use rawsocket::Serializer as RawSocketSerializer;
pub use wamp::{
    parse_message, ParseError as WampParseError, ParsedMessage, Payload as WampPayload, WampMessage,
};

static RUNTIME_MANAGER: OnceLock<RuntimeManager> = OnceLock::new();

const MAX_FRAME_LEN: u64 = 1 << 24;
const HTTP3_DEFAULT_BODY_LIMIT: u64 = 4 * 1024 * 1024;
const WEBSOCKET_GUID: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const MAX_WEBSOCKET_MESSAGE_LEN: usize = 1 << 24;
const HTTP1_INLINE_BODY_LIMIT: usize = 64 * 1024;

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
    len: usize,
}

#[derive(Debug)]
enum HttpBodyPayload {
    Inline(Arc<[u8]>),
    Streaming(StreamingPayload),
}

#[derive(Debug)]
struct StreamingPayload {
    state: Arc<StreamingBodyState>,
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
            len: 0,
        }
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        let len = bytes.len();
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(bytes.into_boxed_slice().into())),
            len,
        }
    }

    pub fn from_arc(bytes: Arc<[u8]>) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        let len = bytes.len();
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(bytes)),
            len,
        }
    }

    pub fn streaming(state: Arc<StreamingBodyState>) -> Self {
        Self {
            payload: Arc::new(HttpBodyPayload::Streaming(StreamingPayload { state })),
            len: 0,
        }
    }

    pub fn len(&self) -> usize {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(_) => self.len,
            HttpBodyPayload::Streaming(payload) => payload.state.total_len(),
        }
    }

    pub fn as_arc(&self) -> Arc<[u8]> {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => Arc::clone(bytes),
            HttpBodyPayload::Streaming(_) => Arc::<[u8]>::from(&[][..]),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn inline_bytes(&self) -> Option<&Arc<[u8]>> {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => Some(bytes),
            HttpBodyPayload::Streaming(_) => None,
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
            HttpBodyPayload::Streaming(_) => None,
        }
    }

    pub fn stream_read(&self, len: usize) -> Result<Option<HttpBodySlice>, StreamingError> {
        match self.payload.as_ref() {
            HttpBodyPayload::Streaming(payload) => payload.state.take_slice(len),
            _ => Ok(None),
        }
    }

    pub fn request_finish(&self) {
        if let HttpBodyPayload::Streaming(payload) = self.payload.as_ref() {
            payload.state.request_finish();
        }
    }

    pub fn is_streaming(&self) -> bool {
        matches!(self.payload.as_ref(), HttpBodyPayload::Streaming(_))
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
    pub body: HttpResponseBody,
}

#[derive(Debug)]
pub enum HttpResponseBody {
    Buffered(Vec<u8>),
    Streaming(ResponseStreamReader),
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

struct ListenerRegistry {
    listeners: Mutex<HashMap<ListenerId, ListenerEntry>>,
    connections: Mutex<HashMap<ConnectionId, ConnectionEntry>>,
    connection_events: Mutex<VecDeque<HttpConnectionEvent>>,
    next_listener_id: AtomicU32,
    next_connection_id: AtomicU32,
}

impl Default for ListenerRegistry {
    fn default() -> Self {
        Self {
            listeners: Mutex::new(HashMap::new()),
            connections: Mutex::new(HashMap::new()),
            connection_events: Mutex::new(VecDeque::new()),
            next_listener_id: AtomicU32::new(0),
            next_connection_id: AtomicU32::new(0),
        }
    }
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
    stats: Option<Arc<HttpConnectionStats>>,
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
    WebSocket {
        serializer: rawsocket::Serializer,
        frames: Mutex<mpsc::Receiver<wamp::ParsedMessage>>,
        reader_task: JoinHandle<()>,
        writer_task: JoinHandle<()>,
        send_tx: UnboundedSender<OutboundFrame>,
    },
    HttpPending {
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
    },
    Http2Pending {
        handshake: Mutex<Option<protocol::Http2Handshake>>,
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
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
                ConnectionRecord::WebSocket {
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
                    stats: None,
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
                    stats: None,
                    record: ConnectionRecord::WebSocketPending {
                        handshake: Mutex::new(Some(handshake)),
                    },
                },
            );
    }

    fn accept_websocket_connection(
        &self,
        connection_id: ConnectionId,
        handshake: protocol::WebSocketHandshake,
        serializer: rawsocket::Serializer,
        protocol: Option<&str>,
    ) -> Result<(), Error> {
        let accept_value = websocket_accept_value(&handshake.sec_websocket_key);
        let mut std_stream = handshake.into_stream().into_std().map_err(Error::Io)?;
        write_websocket_handshake_response(&mut std_stream, &accept_value, protocol)
            .map_err(Error::Io)?;
        std_stream.set_nonblocking(true).map_err(Error::Io)?;
        let stream = TokioTcpStream::from_std(std_stream).map_err(Error::Io)?;
        stream.set_nodelay(true).map_err(Error::Io)?;
        let (reader, writer) = stream.into_split();

        let (frame_tx, frame_rx) = mpsc::channel(1024);
        let (send_tx, send_rx) = mpsc::unbounded_channel();

        let endpoint_config = {
            let connections = self
                .connections
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            let entry = connections
                .get(&connection_id)
                .ok_or(Error::ConnectionNotFound(connection_id))?;
            Arc::clone(&entry.endpoint_config)
        };

        let reader_task = spawn_websocket_reader(
            connection_id,
            serializer,
            endpoint_config,
            reader,
            frame_tx,
            send_tx.clone(),
        );
        let writer_task = spawn_websocket_writer(connection_id, serializer, writer, send_rx);

        let mut connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if let Some(entry) = connections.get_mut(&connection_id) {
            entry.record = ConnectionRecord::WebSocket {
                serializer,
                frames: Mutex::new(frame_rx),
                reader_task,
                writer_task,
                send_tx,
            };
        }
        Ok(())
    }

    fn reject_websocket_connection(
        &self,
        connection_id: ConnectionId,
        handshake: protocol::WebSocketHandshake,
        status: StatusCode,
        reason: Option<&str>,
    ) -> Result<(), Error> {
        let mut stream = handshake.into_stream().into_std().map_err(Error::Io)?;
        let body = reason.unwrap_or("websocket upgrade rejected");
        let response = format!(
            "HTTP/1.1 {} {}\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{}",
            status.as_u16(),
            status.canonical_reason().unwrap_or(""),
            body.len(),
            body
        );
        stream
            .write_all(response.as_bytes())
            .and_then(|_| stream.flush())
            .map_err(Error::Io)?;
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .remove(&connection_id);
        Ok(())
    }

    fn finish_http_connection(
        &self,
        connection_id: ConnectionId,
        reason: HttpConnectionCloseReason,
        detail: Option<String>,
    ) {
        let entry = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .remove(&connection_id);
        if let Some(entry) = entry {
            if let Some(stats) = entry.stats {
                let event = stats.finalize(connection_id, reason, detail);
                self.push_connection_event(event);
            }
        }
    }

    fn push_connection_event(&self, event: HttpConnectionEvent) {
        record_http_metrics(&event);
        self.connection_events
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .push_back(event);
    }

    fn poll_http_connection_event(&self) -> Option<HttpConnectionEvent> {
        self.connection_events
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .pop_front()
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
                    stats: None,
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
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http2);
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
                    stats: Some(Arc::clone(&stats)),
                    record: ConnectionRecord::Http2Pending {
                        handshake: Mutex::new(Some(handshake)),
                        pending_requests: Mutex::new(VecDeque::new()),
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
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http3);
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
                    stats: Some(Arc::clone(&stats)),
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

    fn connection_stats(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<Arc<HttpConnectionStats>>, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| entry.stats.clone())
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
            ConnectionRecord::RawSocket { frames, .. }
            | ConnectionRecord::WebSocket { frames, .. } => {
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
            ConnectionRecord::RawSocket { send_tx, .. }
            | ConnectionRecord::WebSocket { send_tx, .. } => send_tx
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
            ConnectionRecord::Http2Pending { handshake, .. } => {
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
            | ConnectionRecord::Http2Pending {
                pending_requests, ..
            }
            | ConnectionRecord::Http3Pending {
                pending_requests, ..
            } => {
                let stats = entry.stats.clone();
                let mut guard = pending_requests.lock().unwrap();
                let depth_before = guard.len();
                guard.push_back(request);
                if depth_before > 0 {
                    if let Some(stats) = stats.as_ref() {
                        stats.record_backpressure(depth_before + 1);
                    }
                }
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
            | ConnectionRecord::Http2Pending {
                pending_requests, ..
            }
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
    let mut crypto = RustlsServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} http3 certificate invalid: {}",
                endpoint.host, endpoint.port, err
            ))
        })?;
    let mut alpn = endpoint
        .http_settings()
        .map(|settings| {
            settings
                .alpn
                .iter()
                .filter(|token| token.eq_ignore_ascii_case("h3") || token.starts_with("h3-"))
                .map(|token| token.as_bytes().to_vec())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if alpn.is_empty() {
        alpn.push(b"h3".to_vec());
    }
    crypto.alpn_protocols = alpn;
    let server = QuinnServerConfig::with_crypto(Arc::new(
        QuinnRustlsServerConfig::try_from(crypto).map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} http3 rustls config invalid: {}",
                endpoint.host, endpoint.port, err
            ))
        })?,
    ));
    Ok(server)
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

fn spawn_websocket_reader(
    connection_id: ConnectionId,
    serializer: rawsocket::Serializer,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    mut reader: OwnedReadHalf,
    frame_tx: mpsc::Sender<wamp::ParsedMessage>,
    send_tx: UnboundedSender<OutboundFrame>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let idle_timeout = endpoint_config.idle_timeout;
        let mut accumulator = WebSocketMessageAccumulator::new();
        loop {
            let read_future = read_websocket_frame(&mut reader);
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
                Err(err) => {
                    eprintln!("connection {:?} websocket error: {}", connection_id, err);
                    break;
                }
            };

            match frame {
                WebSocketFrame::Data {
                    opcode,
                    fin,
                    payload,
                } => {
                    if let Err(err) = accumulator.push(opcode, fin, payload) {
                        eprintln!(
                            "connection {:?} websocket framing error: {}",
                            connection_id, err
                        );
                        break;
                    }
                    if let Some(message) = accumulator.take_complete() {
                        if let Err(err) =
                            handle_websocket_message(serializer, message, &frame_tx).await
                        {
                            eprintln!(
                                "connection {:?} failed to parse WAMP message: {}",
                                connection_id, err
                            );
                            break;
                        }
                    }
                }
                WebSocketFrame::Ping(payload) => {
                    let _ = send_tx.send(OutboundFrame::control(0x02, Bytes::from(payload)));
                }
                WebSocketFrame::Pong => {
                    // No-op.
                }
                WebSocketFrame::Close(code, reason) => {
                    let mut payload = Vec::new();
                    payload.extend_from_slice(&code.to_be_bytes());
                    payload.extend_from_slice(reason.as_bytes());
                    let _ = send_tx.send(OutboundFrame::control(0x02, Bytes::from(payload)));
                    break;
                }
            }
        }
    })
}

fn spawn_websocket_writer(
    connection_id: ConnectionId,
    serializer: rawsocket::Serializer,
    mut writer: OwnedWriteHalf,
    mut rx: UnboundedReceiver<OutboundFrame>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        while let Some(frame) = rx.recv().await {
            let mut payload = BytesMut::with_capacity(frame.payload_len);
            for segment in frame.segments {
                payload.extend_from_slice(&segment);
            }
            let opcode = match frame.frame_type {
                0 => match serializer {
                    rawsocket::Serializer::Json => 0x1,
                    _ => 0x2,
                },
                1 => 0x9,
                2 => 0xA,
                _ => continue,
            };
            if let Err(err) = write_websocket_frame(&mut writer, opcode, &payload).await {
                eprintln!(
                    "connection {:?} failed to write websocket frame: {}",
                    connection_id, err
                );
                break;
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

enum WebSocketFrame {
    Data {
        opcode: u8,
        fin: bool,
        payload: Vec<u8>,
    },
    Ping(Vec<u8>),
    Pong,
    Close(u16, String),
}

#[derive(Debug)]
struct WebSocketFrameError(String);

impl std::fmt::Display for WebSocketFrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for WebSocketFrameError {}

struct WebSocketMessageAccumulator {
    opcode: Option<u8>,
    buffer: Vec<u8>,
    complete: bool,
}

impl WebSocketMessageAccumulator {
    fn new() -> Self {
        Self {
            opcode: None,
            buffer: Vec::new(),
            complete: false,
        }
    }

    fn push(&mut self, opcode: u8, fin: bool, payload: Vec<u8>) -> Result<(), WebSocketFrameError> {
        if opcode == 0x0 {
            if self.opcode.is_none() {
                return Err(WebSocketFrameError(
                    "received continuation frame without initial opcode".into(),
                ));
            }
        } else if opcode == 0x1 || opcode == 0x2 {
            if self.opcode.is_some() {
                return Err(WebSocketFrameError(
                    "received new data frame before finishing continuation".into(),
                ));
            }
            self.opcode = Some(opcode);
        } else {
            return Err(WebSocketFrameError("unsupported data opcode".into()));
        }

        if self.buffer.len() + payload.len() > MAX_WEBSOCKET_MESSAGE_LEN {
            return Err(WebSocketFrameError(
                "websocket message exceeds supported length".into(),
            ));
        }

        if self.buffer.is_empty() {
            // Move the initial payload without copying so unmasked frames remain zero-copy.
            self.buffer = payload;
        } else {
            self.buffer.extend_from_slice(&payload);
        }
        if fin {
            self.complete = true;
        }
        Ok(())
    }

    fn take_complete(&mut self) -> Option<Vec<u8>> {
        if self.complete {
            let mut data = Vec::new();
            std::mem::swap(&mut data, &mut self.buffer);
            self.opcode = None;
            self.complete = false;
            Some(data)
        } else {
            None
        }
    }
}

async fn read_websocket_frame(
    reader: &mut OwnedReadHalf,
) -> Result<WebSocketFrame, WebSocketFrameError> {
    let mut header = [0u8; 2];
    reader
        .read_exact(&mut header)
        .await
        .map_err(|err| WebSocketFrameError(err.to_string()))?;
    let fin = header[0] & 0x80 != 0;
    let opcode = header[0] & 0x0F;
    let masked = header[1] & 0x80 != 0;
    let mut len = (header[1] & 0x7F) as u64;
    if len == 126 {
        let mut extended = [0u8; 2];
        reader
            .read_exact(&mut extended)
            .await
            .map_err(|err| WebSocketFrameError(err.to_string()))?;
        len = u16::from_be_bytes(extended) as u64;
    } else if len == 127 {
        let mut extended = [0u8; 8];
        reader
            .read_exact(&mut extended)
            .await
            .map_err(|err| WebSocketFrameError(err.to_string()))?;
        len = u64::from_be_bytes(extended);
    }
    if len as usize > MAX_WEBSOCKET_MESSAGE_LEN {
        return Err(WebSocketFrameError(
            "websocket frame exceeds supported length".into(),
        ));
    }
    let mut mask = [0u8; 4];
    if masked {
        reader
            .read_exact(&mut mask)
            .await
            .map_err(|err| WebSocketFrameError(err.to_string()))?;
    }
    let mut payload = vec![0u8; len as usize];
    if len > 0 {
        reader
            .read_exact(&mut payload)
            .await
            .map_err(|err| WebSocketFrameError(err.to_string()))?;
        if masked {
            for (index, byte) in payload.iter_mut().enumerate() {
                *byte ^= mask[index % 4];
            }
        }
    }
    match opcode {
        0x0 | 0x1 | 0x2 => Ok(WebSocketFrame::Data {
            opcode,
            fin,
            payload,
        }),
        0x8 => {
            let code = if payload.len() >= 2 {
                u16::from_be_bytes([payload[0], payload[1]])
            } else {
                1005
            };
            let reason = if payload.len() > 2 {
                String::from_utf8_lossy(&payload[2..]).to_string()
            } else {
                String::new()
            };
            Ok(WebSocketFrame::Close(code, reason))
        }
        0x9 => Ok(WebSocketFrame::Ping(payload)),
        0xA => Ok(WebSocketFrame::Pong),
        _ => Err(WebSocketFrameError("unsupported websocket opcode".into())),
    }
}

async fn write_websocket_frame(
    writer: &mut OwnedWriteHalf,
    opcode: u8,
    payload: &[u8],
) -> io::Result<()> {
    let mut header = Vec::with_capacity(2);
    header.push(0x80 | (opcode & 0x0F));
    if payload.len() < 126 {
        header.push(payload.len() as u8);
    } else if payload.len() <= 0xFFFF {
        header.push(126);
        header.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    } else {
        header.push(127);
        header.extend_from_slice(&(payload.len() as u64).to_be_bytes());
    }
    writer.write_all(&header).await?;
    if !payload.is_empty() {
        writer.write_all(payload).await?;
    }
    Ok(())
}

async fn handle_websocket_message(
    serializer: rawsocket::Serializer,
    data: Vec<u8>,
    frame_tx: &mpsc::Sender<wamp::ParsedMessage>,
) -> Result<(), String> {
    let payload = match serializer {
        rawsocket::Serializer::Json => {
            if std::str::from_utf8(&data).is_err() {
                return Err("websocket text frame payload is not valid UTF-8".into());
            }
            Bytes::from(data)
        }
        _ => Bytes::from(data),
    };
    match wamp::parse_message(serializer, payload) {
        Ok(parsed) => frame_tx
            .send(parsed)
            .await
            .map_err(|_| "failed to enqueue websocket message".into()),
        Err(err) => Err(format!("failed to parse WAMP message: {:?}", err)),
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
                                    let (stream, metadata) = handshake.split();
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http2_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        metadata,
                                        addr,
                                    );
                                    let registry_for_connection = Arc::clone(&accept_registry);
                                    let endpoint_for_connection =
                                        Arc::clone(&runtime_config_for_task);
                                    let http_handle = runtime_handle.clone();
                                    http_handle.spawn(async move {
                                        serve_http2_connection(
                                            listener_id,
                                            connection_id,
                                            stream,
                                            endpoint_for_connection,
                                            registry_for_connection,
                                        )
                                        .await;
                                    });
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

pub fn connection_accept_websocket(
    connection_id: ConnectionId,
    handshake: protocol::WebSocketHandshake,
    serializer: rawsocket::Serializer,
    protocol: Option<&str>,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let _enter = state.handle.enter();
        state.registry.accept_websocket_connection(
            connection_id,
            handshake,
            serializer,
            protocol,
        )
    })
}

pub fn connection_reject_websocket(
    connection_id: ConnectionId,
    handshake: protocol::WebSocketHandshake,
    status: StatusCode,
    reason: Option<&str>,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        state
            .registry
            .reject_websocket_connection(connection_id, handshake, status, reason)
    })
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

/// Attempts to retrieve connection lifecycle events for HTTP/2 and HTTP/3.
pub fn connection_poll_http_event() -> Option<HttpConnectionEvent> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| Ok(state.registry.poll_http_connection_event()))
        .ok()
        .flatten()
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

#[cfg(feature = "ffi-test")]
pub fn push_http_connection_event(event: HttpConnectionEvent) {
    let manager = RuntimeManager::global();
    let _ = manager.with_state(|state| {
        state.registry.push_connection_event(event);
        Ok(())
    });
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

#[cfg(test)]
mod stats_tests {
    use super::*;

    #[test]
    fn http_connection_stats_capture_idle_timeout() {
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http2);
        stats.record_request();
        stats.record_idle_timeout(Some("idle timeout".into()));
        let event = stats.finalize(ConnectionId(42), HttpConnectionCloseReason::Graceful, None);
        assert_eq!(event.connection_id, ConnectionId(42));
        assert_eq!(event.protocol, ConnectionProtocol::Http2);
        assert_eq!(event.request_count, 1);
        assert_eq!(event.idle_timeouts, 1);
        assert_eq!(event.reason, HttpConnectionCloseReason::IdleTimeout);
        assert_eq!(event.backpressure_events, 0);
        assert_eq!(event.max_backpressure_depth, 0);
        assert_eq!(event.goaway_events, 0);
        assert_eq!(event.detail.as_deref(), Some("idle timeout"));
    }

    #[test]
    fn http_connection_stats_capture_backpressure_and_goaway() {
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http2);
        stats.record_request();
        stats.record_backpressure(3);
        stats.record_backpressure(7);
        stats.record_goaway(Some("remote goaway".into()));
        let event = stats.finalize(ConnectionId(7), HttpConnectionCloseReason::Graceful, None);
        assert_eq!(event.connection_id, ConnectionId(7));
        assert_eq!(event.protocol, ConnectionProtocol::Http2);
        assert_eq!(event.request_count, 1);
        assert_eq!(event.backpressure_events, 2);
        assert_eq!(event.max_backpressure_depth, 7);
        assert_eq!(event.goaway_events, 1);
        assert_eq!(event.reason, HttpConnectionCloseReason::GoAway);
        assert_eq!(event.detail.as_deref(), Some("remote goaway"));
    }
}

async fn serve_http_connection(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    handshake: protocol::HttpHandshake,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) {
    let (stream, request, body_phase) = handshake.into_parts();
    let _ = stream.set_nodelay(true);
    let (read_half, mut write_half) = stream.into_split();
    let mut reader = Some(BufReader::new(read_half));
    let mut pending = Some((request, body_phase));
    let mut pending_reclaim: Option<Http1BodyReclaim> = None;
    let read_timeout = endpoint_config
        .idle_timeout
        .unwrap_or(endpoint_config.handshake_timeout);

    loop {
        let (request, body_phase) = match pending.take() {
            Some(value) => value,
            None => {
                if reader.is_none() {
                    if let Some(reclaim) = pending_reclaim.take() {
                        match reclaim.wait().await {
                            Ok(read_half) => {
                                reader = Some(BufReader::new(read_half));
                            }
                            Err(_) => break,
                        }
                    } else {
                        break;
                    }
                }
                match protocol::read_http_request(reader.as_mut().unwrap(), &endpoint_config).await
                {
                    Ok(Some(value)) => value,
                    Ok(None) => break,
                    Err(err) => {
                        eprintln!(
                            "http/1 connection read error for listener {:?}: {:?}",
                            listener_id, err
                        );
                        break;
                    }
                }
            }
        };

        let (body_handle, new_reclaim) = match body_phase {
            HttpBodyPhase::Buffered(bytes) => (HttpBodyHandle::from_bytes(bytes.to_vec()), None),
            HttpBodyPhase::Finished => (HttpBodyHandle::empty(), None),
            HttpBodyPhase::NeedsStreaming {
                prefix,
                remaining_len,
            } => {
                let reader_half = match reader.take() {
                    Some(buf) => buf.into_inner(),
                    None => {
                        eprintln!(
                            "http/1 streaming requested without active reader for listener {:?}",
                            listener_id
                        );
                        break;
                    }
                };
                let (state, reclaim) =
                    spawn_http1_streaming_body(prefix, reader_half, remaining_len, read_timeout);
                (HttpBodyHandle::streaming(state), Some(reclaim))
            }
        };
        if let Some(reclaim) = new_reclaim {
            pending_reclaim = Some(reclaim);
        }

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
                            send_http_dispatch(&mut write_half, version, keep_alive, &mut dispatch)
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
                            &mut write_half,
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
                    &mut write_half,
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
                    &mut write_half,
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

        if reader.is_none() {
            if let Some(reclaim) = pending_reclaim.take() {
                match reclaim.wait().await {
                    Ok(read_half) => {
                        reader = Some(BufReader::new(read_half));
                    }
                    Err(_) => break,
                }
            } else {
                break;
            }
        }

        if !keep_alive {
            break;
        }
    }
}

async fn send_http_dispatch(
    writer: &mut OwnedWriteHalf,
    version: u8,
    keep_alive: bool,
    dispatch: &mut HttpResponseDispatch,
) -> Result<(), String> {
    ensure_connection_header(&mut dispatch.headers, keep_alive, version);
    match &mut dispatch.body {
        HttpResponseBody::Buffered(body) => protocol::write_http_response_shared(
            writer,
            version,
            dispatch.status,
            &dispatch.headers,
            body,
        )
        .await
        .map_err(|err| err.to_string()),
        HttpResponseBody::Streaming(reader) => {
            strip_content_length(&mut dispatch.headers);
            ensure_chunked_transfer_encoding(&mut dispatch.headers);
            write_http1_chunked_response(
                writer,
                version,
                dispatch.status,
                &dispatch.headers,
                reader,
            )
            .await
        }
    }
}

async fn send_http_simple_response(
    writer: &mut OwnedWriteHalf,
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
    protocol::write_http_response_shared(writer, version, status.as_u16() as i32, &headers, body)
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

fn ensure_chunked_transfer_encoding(headers: &mut Vec<(String, String)>) {
    headers.retain(|(name, _)| !name.eq_ignore_ascii_case("transfer-encoding"));
    headers.push(("Transfer-Encoding".into(), "chunked".into()));
}

fn strip_content_length(headers: &mut Vec<(String, String)>) {
    headers.retain(|(name, _)| !name.eq_ignore_ascii_case("content-length"));
}

async fn write_http1_chunked_response(
    writer: &mut OwnedWriteHalf,
    version: u8,
    status: i32,
    headers: &[(String, String)],
    reader: &mut ResponseStreamReader,
) -> Result<(), String> {
    let clamped = status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let reason = status_code.canonical_reason().unwrap_or("");
    let mut response = Vec::with_capacity(128 + headers.len() * 32);
    write!(
        &mut response,
        "HTTP/1.{} {} {}\r\n",
        version,
        status_code.as_u16(),
        reason
    )
    .map_err(|err| err.to_string())?;
    for (name, value) in headers {
        write!(&mut response, "{}: {}\r\n", name, value).map_err(|err| err.to_string())?;
    }
    response.extend_from_slice(b"\r\n");
    if let Err(err) = writer.write_all(&response).await {
        reader.close();
        return Err(err.to_string());
    }

    loop {
        match reader.next().await {
            Ok(ResponseStreamFrame::Chunk(bytes)) => {
                if bytes.is_empty() {
                    continue;
                }
                let header = format!("{:X}\r\n", bytes.len());
                if let Err(err) = writer.write_all(header.as_bytes()).await {
                    reader.close();
                    return Err(err.to_string());
                }
                if let Err(err) = writer.write_all(&bytes).await {
                    reader.close();
                    return Err(err.to_string());
                }
                if let Err(err) = writer.write_all(b"\r\n").await {
                    reader.close();
                    return Err(err.to_string());
                }
            }
            Ok(ResponseStreamFrame::Finished) => {
                if let Err(err) = writer.write_all(b"0\r\n\r\n").await {
                    reader.close();
                    return Err(err.to_string());
                }
                return Ok(());
            }
            Err(err) => {
                reader.close();
                return Err(format!("http/1.x streaming response failed: {}", err));
            }
        }
    }
}

fn websocket_accept_value(key: &str) -> String {
    let mut sha1 = Sha1::new();
    sha1.update(key.as_bytes());
    sha1.update(WEBSOCKET_GUID.as_bytes());
    Base64Engine.encode(sha1.finalize())
}

fn write_websocket_handshake_response(
    stream: &mut std::net::TcpStream,
    accept_value: &str,
    protocol: Option<&str>,
) -> io::Result<()> {
    let mut response = format!(
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {}\r\n",
        accept_value
    );
    if let Some(protocol) = protocol {
        response.push_str(&format!("Sec-WebSocket-Protocol: {}\r\n", protocol));
    }
    response.push_str("\r\n");
    stream.write_all(response.as_bytes())?;
    stream.flush()?;
    Ok(())
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
            registry.finish_http_connection(
                connection_id,
                HttpConnectionCloseReason::ProtocolError,
                Some(err.to_string()),
            );
            return;
        }
    };

    let connection_stats = registry
        .connection_stats(connection_id)
        .ok()
        .and_then(|stats| stats);
    let mut closed = false;

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
                let h3_no_error = err.is_h3_no_error();
                let err_description = err.to_string();
                let mut graceful_close = h3_no_error;
                if !graceful_close {
                    if let Some(code_segment) = err_description.rsplit(':').next() {
                        if code_segment.trim().eq_ignore_ascii_case("0x0") {
                            graceful_close = true;
                        }
                    }
                }
                let error_message = if graceful_close {
                    None
                } else {
                    Some(err_description)
                };
                if !graceful_close {
                    if let Some(message) = error_message.as_ref() {
                        eprintln!(
                            "http3 accept loop stopped for listener {:?}: {}",
                            listener_id, message
                        );
                    }
                }
                let reason = if graceful_close {
                    HttpConnectionCloseReason::Graceful
                } else {
                    HttpConnectionCloseReason::ProtocolError
                };
                if let Some(stats) = connection_stats.as_ref() {
                    stats.set_close_reason(reason, error_message.clone());
                }
                registry.finish_http_connection(connection_id, reason, error_message);
                closed = true;
                break;
            }
        }
    }

    drop(streams);
    if !closed {
        registry.finish_http_connection(connection_id, HttpConnectionCloseReason::Graceful, None);
    }
}

async fn serve_http2_connection(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    stream: TokioTcpStream,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) {
    let mut connection = match h2_server::handshake(stream).await {
        Ok(connection) => connection,
        Err(err) => {
            eprintln!(
                "http/2 handshake failed for listener {:?}: {}",
                listener_id, err
            );
            registry.finish_http_connection(
                connection_id,
                HttpConnectionCloseReason::ProtocolError,
                Some(err.to_string()),
            );
            return;
        }
    };

    let connection_stats = registry
        .connection_stats(connection_id)
        .ok()
        .and_then(|stats| stats);
    let mut closed = false;

    while let Some(result) = connection.accept().await {
        match result {
            Ok((request, respond)) => {
                if let Err(err) = handle_http2_request(
                    connection_id,
                    request,
                    respond,
                    Arc::clone(&endpoint_config),
                    Arc::clone(&registry),
                )
                .await
                {
                    eprintln!(
                        "http/2 request error for listener {:?}: {}",
                        listener_id, err
                    );
                }
            }
            Err(err) => {
                eprintln!(
                    "http/2 accept error for listener {:?}: {}",
                    listener_id, err
                );
                if let Some(stats) = connection_stats.as_ref() {
                    if err.is_go_away() {
                        stats.record_goaway(Some(err.to_string()));
                    } else {
                        stats.set_close_reason(
                            HttpConnectionCloseReason::ProtocolError,
                            Some(err.to_string()),
                        );
                    }
                }
                registry.finish_http_connection(
                    connection_id,
                    if err.is_go_away() {
                        HttpConnectionCloseReason::GoAway
                    } else {
                        HttpConnectionCloseReason::ProtocolError
                    },
                    Some(err.to_string()),
                );
                closed = true;
                break;
            }
        }
    }

    if !closed {
        registry.finish_http_connection(connection_id, HttpConnectionCloseReason::Graceful, None);
    }
}

async fn handle_http2_request(
    connection_id: ConnectionId,
    request: Http2Request<H2RecvStream>,
    respond: H2SendResponse<Bytes>,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) -> Result<(), String> {
    let (parts, body_stream) = request.into_parts();
    let method = parts.method.as_str().to_string();
    let normalized_method = method.to_uppercase();
    let target = parts
        .uri
        .path_and_query()
        .map(|pq| pq.as_str().to_string())
        .unwrap_or_else(|| parts.uri.path().to_string());
    let (path, query) = split_target_components(&target);
    let headers = flatten_http2_headers(&parts.headers);
    let content_length = parse_content_length(&headers);
    let max_body = endpoint_config
        .max_http_content_length
        .unwrap_or(HTTP3_DEFAULT_BODY_LIMIT);

    let stats = registry
        .connection_stats(connection_id)
        .map_err(|err| err.to_string())?;
    if let Some(ref stats_arc) = stats {
        stats_arc.record_request();
    }
    let state = StreamingBodyState::new(content_length.map(|len| len as usize).unwrap_or(0));
    let (idle_timeout, total_timeout) = http_stream_timeouts(&endpoint_config);
    spawn_http2_stream_reader(
        stats.clone(),
        Arc::clone(&state),
        body_stream,
        max_body,
        content_length,
        idle_timeout,
        total_timeout,
    );
    let body_handle = HttpBodyHandle::streaming(state);
    let query_owned = query.clone();

    match endpoint_config.match_http_route(&path, query.as_deref(), &normalized_method, "http2") {
        HttpRouteMatch::Resolved(resolution) => {
            let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
            let summary = HttpRequestSummary::new(
                normalized_method,
                target,
                path,
                query_owned,
                "http/2".to_string(),
                2,
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
                match rx.await {
                    Ok(dispatch) => {
                        if let Err(err) = send_http2_response_from_dispatch(respond, dispatch).await
                        {
                            eprintln!(
                                "failed to send http/2 response for connection {:?}: {}",
                                connection_id, err
                            );
                        }
                    }
                    Err(_) => {
                        let _ = send_http2_plain_response(
                            respond,
                            StatusCode::INTERNAL_SERVER_ERROR,
                            b"http/2 request cancelled",
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
            send_http2_plain_response(
                respond,
                StatusCode::METHOD_NOT_ALLOWED,
                b"method not allowed",
                &[("allow", allow_value.as_str())],
            )
            .await
        }
        HttpRouteMatch::NotFound => {
            send_http2_plain_response(respond, StatusCode::NOT_FOUND, b"route not found", &[]).await
        }
    }
}

fn spawn_http2_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    stream: H2RecvStream,
    max_body: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) {
    tokio::spawn(async move {
        if let Err(err) = run_http2_stream_reader(
            stats,
            state,
            stream,
            max_body,
            content_length,
            idle_timeout,
            total_timeout,
        )
        .await
        {
            eprintln!("http/2 body reader error: {}", err);
        }
    });
}

async fn run_http2_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    mut stream: H2RecvStream,
    max_body: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) -> Result<(), String> {
    let mut bytes_read: u64 = 0;
    let total_deadline = Instant::now() + total_timeout;
    loop {
        if state.finish_requested() {
            state.mark_finished();
            return Ok(());
        }

        if Instant::now() >= total_deadline {
            if let Some(stats_ref) = stats.as_ref() {
                stats_ref.record_body_timeout(Some("http/2 body total timeout".into()));
            }
            state.mark_error("http/2 body total timeout exceeded".into());
            return Err("http/2 body total timeout".into());
        }

        let data_future = stream.data();
        let chunk = match time::timeout(idle_timeout, data_future).await {
            Ok(value) => value,
            Err(_) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.record_idle_timeout(Some("http/2 body idle timeout".into()));
                }
                state.mark_error("http/2 body idle timeout".into());
                return Err("http/2 body idle timeout".into());
            }
        };

        match chunk {
            Some(Ok(bytes)) => {
                bytes_read += bytes.len() as u64;
                if bytes_read > max_body
                    || content_length
                        .map(|limit| bytes_read > limit)
                        .unwrap_or(false)
                {
                    state.mark_error("http/2 body exceeded configured limit".into());
                    return Ok(());
                }
                if content_length.is_none() {
                    state.extend_total_len(bytes.len());
                }
                if !state.finish_requested() {
                    state.enqueue_vec(bytes.to_vec());
                }
                if let Err(err) = stream.flow_control().release_capacity(bytes.len()) {
                    state.mark_error(format!("http/2 flow control error: {}", err));
                    return Err(err.to_string());
                }
            }
            Some(Err(err)) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.set_close_reason(
                        HttpConnectionCloseReason::ProtocolError,
                        Some(format!("http/2 body read failed: {}", err)),
                    );
                }
                state.mark_error(format!("http/2 body read failed: {}", err));
                return Err(err.to_string());
            }
            None => {
                if let Some(expected) = content_length {
                    if bytes_read != expected {
                        state.mark_error("http/2 body ended before declared Content-Length".into());
                        return Ok(());
                    }
                }
                state.mark_finished();
                return Ok(());
            }
        }
    }
}

async fn send_http2_plain_response(
    mut respond: H2SendResponse<Bytes>,
    status: StatusCode,
    body: &[u8],
    extra_headers: &[(&str, &str)],
) -> Result<(), String> {
    let http2_status = Http2StatusCode::from_u16(status.as_u16())
        .unwrap_or(Http2StatusCode::INTERNAL_SERVER_ERROR);
    let mut builder = Http2Response::builder().status(http2_status);
    {
        let header_map = builder.headers_mut().expect("headers available");
        if let Ok(value) = Http2HeaderValue::from_str(&body.len().to_string()) {
            header_map.insert(Http2HeaderName::from_static("content-length"), value);
        }
        for (name, value) in extra_headers {
            if let (Ok(name), Ok(val)) = (
                Http2HeaderName::from_bytes(name.as_bytes()),
                Http2HeaderValue::from_str(value),
            ) {
                header_map.insert(name, val);
            }
        }
    }
    let response = builder.body(()).map_err(|err| err.to_string())?;
    let end_of_stream = body.is_empty();
    let mut send_stream = respond
        .send_response(response, end_of_stream)
        .map_err(|err| err.to_string())?;
    if !body.is_empty() {
        send_stream
            .send_data(Bytes::copy_from_slice(body), true)
            .map_err(|err| err.to_string())?;
    }
    Ok(())
}

async fn send_http2_response_from_dispatch(
    mut respond: H2SendResponse<Bytes>,
    dispatch: HttpResponseDispatch,
) -> Result<(), String> {
    let HttpResponseDispatch {
        status,
        mut headers,
        body,
    } = dispatch;
    let clamped = status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let http2_status = Http2StatusCode::from_u16(status_code.as_u16())
        .unwrap_or(Http2StatusCode::INTERNAL_SERVER_ERROR);
    let mut builder = Http2Response::builder().status(http2_status);
    match body {
        HttpResponseBody::Buffered(body_bytes) => {
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        Http2HeaderName::from_bytes(name.as_bytes()),
                        Http2HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
                if let Ok(len_value) = Http2HeaderValue::from_str(&body_bytes.len().to_string()) {
                    header_map.insert(Http2HeaderName::from_static("content-length"), len_value);
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            let end_of_stream = body_bytes.is_empty();
            let mut send_stream = respond
                .send_response(response, end_of_stream)
                .map_err(|err| err.to_string())?;
            if !body_bytes.is_empty() {
                send_stream
                    .send_data(Bytes::from(body_bytes), true)
                    .map_err(|err| err.to_string())?;
            }
            Ok(())
        }
        HttpResponseBody::Streaming(mut reader) => {
            strip_content_length(&mut headers);
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        Http2HeaderName::from_bytes(name.as_bytes()),
                        Http2HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            let mut send_stream = respond
                .send_response(response, false)
                .map_err(|err| err.to_string())?;
            loop {
                match reader.next().await {
                    Ok(ResponseStreamFrame::Chunk(bytes)) => {
                        if let Err(err) = send_stream.send_data(bytes, false) {
                            reader.close();
                            return Err(err.to_string());
                        }
                    }
                    Ok(ResponseStreamFrame::Finished) => {
                        if let Err(err) = send_stream.send_data(Bytes::new(), true) {
                            return Err(err.to_string());
                        }
                        return Ok(());
                    }
                    Err(err) => {
                        reader.close();
                        return Err(format!("http/2 streaming response failed: {}", err));
                    }
                }
            }
        }
    }
}

async fn process_http3_request(
    connection_id: ConnectionId,
    request: HttpRequest<()>,
    stream: H3ServerBidiStream,
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
    let content_length = parse_content_length(&headers);
    let stats = registry
        .connection_stats(connection_id)
        .map_err(|err| err.to_string())?;
    if let Some(ref stats_arc) = stats {
        stats_arc.record_request();
    }
    let (mut send_stream, recv_stream) = stream.split();
    let body_state = StreamingBodyState::new(content_length.map(|len| len as usize).unwrap_or(0));
    let (idle_timeout, total_timeout) = http_stream_timeouts(&endpoint_config);
    spawn_http3_stream_reader(
        stats.clone(),
        Arc::clone(&body_state),
        recv_stream,
        max_body,
        0,
        content_length,
        idle_timeout,
        total_timeout,
    );
    let body_handle = HttpBodyHandle::streaming(body_state);

    match endpoint_config.match_http_route(&path, query.as_deref(), &normalized_method, "http3") {
        HttpRouteMatch::Resolved(resolution) => {
            let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
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
                match rx.await {
                    Ok(dispatch) => {
                        if let Err(err) =
                            send_http3_response_from_dispatch(&mut send_stream, dispatch).await
                        {
                            eprintln!(
                                "failed to send http3 response for connection {:?}: {}",
                                connection_id, err
                            );
                        }
                    }
                    Err(_) => {
                        let _ = send_http3_plain_response(
                            &mut send_stream,
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
            send_http3_plain_response(
                &mut send_stream,
                StatusCode::METHOD_NOT_ALLOWED,
                b"method not allowed",
                &[("allow", allow_value.as_str())],
            )
            .await
        }
        HttpRouteMatch::NotFound => {
            send_http3_plain_response(
                &mut send_stream,
                StatusCode::NOT_FOUND,
                b"route not found",
                &[],
            )
            .await
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

fn flatten_http2_headers(headers: &http02::HeaderMap) -> Vec<(String, String)> {
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

fn parse_content_length(headers: &[(String, String)]) -> Option<u64> {
    headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case(CONTENT_LENGTH.as_str()))
        .and_then(|(_, value)| value.trim().parse::<u64>().ok())
}

fn spawn_http3_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    stream: H3ServerRecvStream,
    max_body: u64,
    bytes_read: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) {
    tokio::spawn(async move {
        if let Err(err) = run_http3_stream_reader(
            stats,
            state,
            stream,
            max_body,
            bytes_read,
            content_length,
            idle_timeout,
            total_timeout,
        )
        .await
        {
            eprintln!("http/3 body reader failed: {}", err);
        }
    });
}

async fn run_http3_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    mut stream: H3ServerRecvStream,
    max_body: u64,
    mut bytes_read: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) -> Result<(), String> {
    let mut total_deadline = Instant::now() + total_timeout;
    loop {
        if state.finish_requested() {
            stream.stop_sending(H3ErrorCode::H3_NO_ERROR);
            state.mark_finished();
            return Ok(());
        }
        if Instant::now() >= total_deadline {
            if let Some(stats_ref) = stats.as_ref() {
                stats_ref.record_body_timeout(Some("http/3 body total timeout".into()));
            }
            state.mark_error("http/3 body total timeout exceeded".into());
            stream.stop_sending(H3ErrorCode::H3_REQUEST_CANCELLED);
            return Err("http/3 body total timeout".into());
        }
        let recv_future = stream.recv_data();
        let chunk = match time::timeout(idle_timeout, recv_future).await {
            Ok(value) => value,
            Err(_) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.record_idle_timeout(Some("http/3 body idle timeout".into()));
                }
                state.mark_error("http/3 body idle timeout".into());
                stream.stop_sending(H3ErrorCode::H3_REQUEST_CANCELLED);
                return Err("http/3 body idle timeout".into());
            }
        };
        match chunk {
            Ok(Some(mut chunk)) => {
                while chunk.has_remaining() {
                    let len = chunk.remaining();
                    let bytes = chunk.copy_to_bytes(len);
                    bytes_read += len as u64;
                    if bytes_read > max_body
                        || content_length
                            .map(|limit| bytes_read > limit)
                            .unwrap_or(false)
                    {
                        state.mark_error("http/3 body exceeded configured limit".into());
                        stream.stop_sending(H3ErrorCode::H3_REQUEST_CANCELLED);
                        return Ok(());
                    }
                    if content_length.is_none() {
                        state.extend_total_len(len);
                    }
                    if !state.finish_requested() {
                        state.enqueue_vec(bytes.to_vec());
                    }
                }
                total_deadline = Instant::now() + total_timeout;
            }
            Ok(None) => {
                if let Some(expected) = content_length {
                    if bytes_read != expected {
                        state.mark_error("http/3 body ended before declared Content-Length".into());
                        return Ok(());
                    }
                }
                state.mark_finished();
                stream.stop_sending(H3ErrorCode::H3_NO_ERROR);
                return Ok(());
            }
            Err(err) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.set_close_reason(
                        HttpConnectionCloseReason::ProtocolError,
                        Some(format!("http/3 body read failed: {}", err)),
                    );
                }
                state.mark_error(format!("http/3 body read failed: {}", err));
                stream.stop_sending(H3ErrorCode::H3_REQUEST_CANCELLED);
                return Err(err.to_string());
            }
        }
    }
}
#[allow(dead_code)]
fn http_summary_from_handshake(
    handshake: &protocol::HttpHandshake,
    route: &config::HttpRouteResolution,
) -> HttpRequestSummary {
    let (path, query) = protocol::split_http_target(&handshake.request.target);
    let normalized_path = if path.is_empty() { "/" } else { path };
    let body_handle = match &handshake.body {
        HttpBodyPhase::Buffered(bytes) => HttpBodyHandle::from_bytes(bytes.to_vec()),
        HttpBodyPhase::Finished => HttpBodyHandle::empty(),
        HttpBodyPhase::NeedsStreaming { .. } => HttpBodyHandle::empty(),
    };
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

async fn send_http3_plain_response(
    stream: &mut H3ServerSendStream,
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
    stream: &mut H3ServerSendStream,
    dispatch: HttpResponseDispatch,
) -> Result<(), String> {
    let HttpResponseDispatch {
        status,
        mut headers,
        body,
    } = dispatch;
    let clamped = status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    match body {
        HttpResponseBody::Buffered(body_bytes) => {
            let mut builder = HttpResponse::builder().status(status_code);
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        HeaderName::from_bytes(name.as_bytes()),
                        HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
                if let Ok(len_value) = HeaderValue::from_str(&body_bytes.len().to_string()) {
                    header_map.insert(CONTENT_LENGTH, len_value);
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            stream
                .send_response(response)
                .await
                .map_err(|err| err.to_string())?;
            if !body_bytes.is_empty() {
                stream
                    .send_data(Bytes::from(body_bytes))
                    .await
                    .map_err(|err| err.to_string())?;
            }
            stream.finish().await.map_err(|err| err.to_string())
        }
        HttpResponseBody::Streaming(mut reader) => {
            strip_content_length(&mut headers);
            let mut builder = HttpResponse::builder().status(status_code);
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        HeaderName::from_bytes(name.as_bytes()),
                        HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            stream
                .send_response(response)
                .await
                .map_err(|err| err.to_string())?;
            loop {
                match reader.next().await {
                    Ok(ResponseStreamFrame::Chunk(bytes)) => {
                        stream
                            .send_data(bytes)
                            .await
                            .map_err(|err| err.to_string())?;
                    }
                    Ok(ResponseStreamFrame::Finished) => {
                        reader.close();
                        return stream.finish().await.map_err(|err| err.to_string());
                    }
                    Err(err) => {
                        reader.close();
                        return Err(format!("http/3 streaming response failed: {}", err));
                    }
                }
            }
        }
    }
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
