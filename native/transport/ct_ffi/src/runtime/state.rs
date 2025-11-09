use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc, Mutex, OnceLock,
};

use bytes::Bytes;
use ct_core::{
    ConnectionId, Http2Handshake, Http3BidiStream, Http3Handshake, HttpBodyHandle, HttpHandshake,
    HttpRequestSummary, HttpResponseHandle, HttpRouteResolution, ListenerId, RawSocketSerializer,
    WampMessage, WebSocketHandshake,
};
use dashmap::DashMap;
use quinn::Connection as QuinnConnection;
use tokio::sync::mpsc::Receiver;

struct ReceiverEntry {
    receiver: Mutex<Receiver<ConnectionId>>,
}

static CHANNELS: OnceLock<DashMap<ListenerId, ReceiverEntry>> = OnceLock::new();

fn map() -> &'static DashMap<ListenerId, ReceiverEntry> {
    CHANNELS.get_or_init(DashMap::new)
}

pub fn store_channel(listener_id: ListenerId, receiver: Receiver<ConnectionId>) {
    map().insert(
        listener_id,
        ReceiverEntry {
            receiver: Mutex::new(receiver),
        },
    );
}

pub fn with_channel<F, T>(listener_id: ListenerId, f: F) -> Option<T>
where
    F: FnOnce(&mut Receiver<ConnectionId>) -> T,
{
    map().get(&listener_id).map(|entry| {
        let mut guard = entry.receiver.lock().unwrap();
        f(&mut guard)
    })
}

pub fn clear_channels() {
    map().clear();
    clear_messages();
    clear_http_handshakes();
    clear_websocket_handshakes();
    clear_http2_handshakes();
    clear_http3_handshakes();
    clear_http3_connections();
    clear_http3_streams();
}

#[derive(Clone)]
pub struct HttpMetadata {
    pub method: Arc<[u8]>,
    pub target: Arc<[u8]>,
    pub path: Arc<[u8]>,
    pub query: Option<Arc<[u8]>>,
    pub protocol: Arc<[u8]>,
    pub version: u8,
    pub headers: Vec<(Arc<[u8]>, Arc<[u8]>)>,
    pub body: HttpBodyHandle,
    pub realm: Option<Arc<[u8]>>,
    pub procedure: Option<Arc<[u8]>>,
}

#[derive(Clone)]
pub struct Http2Metadata {
    pub protocol: Arc<[u8]>,
    pub alpn: Option<Arc<[u8]>>,
    pub listener_protocols: Vec<Arc<[u8]>>,
}

impl Default for Http2Metadata {
    fn default() -> Self {
        Self {
            protocol: Arc::<[u8]>::from(b"http/2".to_vec()),
            alpn: None,
            listener_protocols: Vec::new(),
        }
    }
}

impl Http2Metadata {
    pub fn listener_protocol(&self, index: usize) -> Option<&[u8]> {
        self.listener_protocols
            .get(index)
            .map(|value| value.as_ref())
    }
}

#[derive(Clone)]
pub struct Http3Metadata {
    pub protocol: Arc<[u8]>,
    pub alpn: Option<Arc<[u8]>>,
    pub listener_protocols: Vec<Arc<[u8]>>,
}

impl Default for Http3Metadata {
    fn default() -> Self {
        Self {
            protocol: Arc::<[u8]>::from(b"http/3".to_vec()),
            alpn: None,
            listener_protocols: Vec::new(),
        }
    }
}

impl Http3Metadata {
    pub fn listener_protocol(&self, index: usize) -> Option<&[u8]> {
        self.listener_protocols
            .get(index)
            .map(|value| value.as_ref())
    }
}

impl HttpMetadata {
    fn from_handshake(
        handshake: &HttpHandshake,
        path: &str,
        query: Option<&str>,
        protocol: &str,
        route: Option<&HttpRouteResolution>,
    ) -> Self {
        let method = Arc::<[u8]>::from(handshake.request.method.as_bytes().to_vec());
        let target = Arc::<[u8]>::from(handshake.request.target.as_bytes().to_vec());
        let path_arc = Arc::<[u8]>::from(path.as_bytes().to_vec());
        let query_arc = query.map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        let protocol_arc = Arc::<[u8]>::from(protocol.as_bytes().to_vec());
        let realm_arc =
            route.map(|resolution| Arc::<[u8]>::from(resolution.realm.as_bytes().to_vec()));
        let procedure_arc =
            route.map(|resolution| Arc::<[u8]>::from(resolution.procedure.as_bytes().to_vec()));
        let headers = handshake
            .request
            .headers
            .iter()
            .map(|(name, value)| {
                (
                    Arc::<[u8]>::from(name.as_bytes().to_vec()),
                    Arc::<[u8]>::from(value.as_bytes().to_vec()),
                )
            })
            .collect();
        let body = HttpBodyHandle::from_bytes(handshake.body.clone());
        Self {
            method,
            target,
            path: path_arc,
            query: query_arc,
            protocol: protocol_arc,
            version: handshake.request.version,
            headers,
            body,
            realm: realm_arc,
            procedure: procedure_arc,
        }
    }

    pub fn from_summary(summary: &HttpRequestSummary) -> Self {
        let method = Arc::<[u8]>::from(summary.method.as_bytes().to_vec());
        let target = Arc::<[u8]>::from(summary.target.as_bytes().to_vec());
        let path = Arc::<[u8]>::from(summary.path.as_bytes().to_vec());
        let query = summary
            .query
            .as_ref()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        let protocol = Arc::<[u8]>::from(summary.protocol.as_bytes().to_vec());
        let realm = summary
            .realm
            .as_ref()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        let procedure = summary
            .procedure
            .as_ref()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        let headers = summary
            .headers
            .iter()
            .map(|(name, value)| {
                (
                    Arc::<[u8]>::from(name.as_bytes().to_vec()),
                    Arc::<[u8]>::from(value.as_bytes().to_vec()),
                )
            })
            .collect();
        let body = summary.body.clone();
        Self {
            method,
            target,
            path,
            query,
            protocol,
            version: summary.version,
            headers,
            body,
            realm,
            procedure,
        }
    }
}

fn split_target(target: &str) -> (&str, Option<&str>) {
    match target.find('?') {
        Some(index) => {
            let (path, rest) = target.split_at(index);
            if rest.len() > 1 {
                (path, Some(&rest[1..]))
            } else {
                (path, None)
            }
        }
        None => (target, None),
    }
}

pub enum StoredHttpHandshakePayload {
    Response(HttpResponseHandle),
}

pub struct StoredHttpHandshake {
    pub metadata: HttpMetadata,
    payload: Mutex<Option<StoredHttpHandshakePayload>>,
}

impl StoredHttpHandshake {
    pub fn from_metadata(metadata: HttpMetadata, response: HttpResponseHandle) -> Self {
        Self {
            metadata,
            payload: Mutex::new(Some(StoredHttpHandshakePayload::Response(response))),
        }
    }

    pub fn take_payload(&self) -> Option<StoredHttpHandshakePayload> {
        self.payload.lock().unwrap().take()
    }
}

pub struct StoredWebSocketHandshake {
    pub metadata: HttpMetadata,
    pub key: Arc<[u8]>,
    pub protocols: Vec<Arc<[u8]>>,
    pub extensions: Vec<Arc<[u8]>>,
    pub version: Option<Arc<[u8]>>,
    #[allow(dead_code)]
    handshake: Mutex<Option<WebSocketHandshake>>,
}

pub struct StoredHttp2Handshake {
    pub metadata: Http2Metadata,
    #[allow(dead_code)]
    handshake: Mutex<Option<Http2Handshake>>,
}

impl StoredHttp2Handshake {
    pub fn new(handshake: Http2Handshake) -> Self {
        let mut metadata = Http2Metadata::default();
        metadata.protocol = Arc::<[u8]>::from(handshake.protocol().as_bytes().to_vec());
        metadata.alpn = handshake
            .alpn()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        metadata.listener_protocols = handshake
            .listener_protocols()
            .iter()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()))
            .collect();
        Self {
            metadata,
            handshake: Mutex::new(Some(handshake)),
        }
    }

    #[allow(dead_code)]
    pub fn take(&self) -> Option<Http2Handshake> {
        self.handshake.lock().unwrap().take()
    }
}

pub struct StoredHttp3Handshake {
    pub metadata: Http3Metadata,
    handshake: Mutex<Option<Http3Handshake>>,
}

impl StoredHttp3Handshake {
    pub fn new(handshake: Http3Handshake) -> Self {
        let mut metadata = Http3Metadata::default();
        metadata.protocol = Arc::<[u8]>::from(handshake.protocol().as_bytes().to_vec());
        metadata.alpn = handshake
            .alpn()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        metadata.listener_protocols = handshake
            .listener_protocols()
            .iter()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()))
            .collect();
        Self {
            metadata,
            handshake: Mutex::new(Some(handshake)),
        }
    }

    pub fn take(&self) -> Option<Http3Handshake> {
        self.handshake.lock().unwrap().take()
    }
}

impl StoredWebSocketHandshake {
    pub fn new(handshake: WebSocketHandshake) -> Self {
        let protocol = format!("http/1.{}", handshake.http.request.version);
        let (raw_path, query) = split_target(&handshake.http.request.target);
        let path = if raw_path.is_empty() { "/" } else { raw_path };
        let metadata = HttpMetadata::from_handshake(&handshake.http, path, query, &protocol, None);
        let key = Arc::<[u8]>::from(handshake.sec_websocket_key.as_bytes().to_vec());
        let protocols = handshake
            .sec_websocket_protocols
            .iter()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()))
            .collect();
        let extensions = handshake
            .sec_websocket_extensions
            .iter()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()))
            .collect();
        let version = handshake
            .sec_websocket_version
            .as_ref()
            .map(|value| Arc::<[u8]>::from(value.as_bytes().to_vec()));
        Self {
            metadata,
            key,
            protocols,
            extensions,
            version,
            handshake: Mutex::new(Some(handshake)),
        }
    }

    #[allow(dead_code)]
    pub fn take(&self) -> Option<WebSocketHandshake> {
        self.handshake.lock().unwrap().take()
    }
}

struct HttpHandshakeStore {
    next_id: AtomicU32,
    handshakes: DashMap<u32, Arc<StoredHttpHandshake>>,
}

impl Default for HttpHandshakeStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            handshakes: DashMap::new(),
        }
    }
}

static HTTP_HANDSHAKES: OnceLock<HttpHandshakeStore> = OnceLock::new();

fn http_store() -> &'static HttpHandshakeStore {
    HTTP_HANDSHAKES.get_or_init(HttpHandshakeStore::default)
}

pub fn store_http_request_metadata(metadata: HttpMetadata, response: HttpResponseHandle) -> u32 {
    let store = http_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.handshakes.insert(
        id,
        Arc::new(StoredHttpHandshake::from_metadata(metadata, response)),
    );
    id
}

pub fn with_http_handshake<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredHttpHandshake) -> T,
{
    http_store().handshakes.get(&id).map(|entry| {
        let handshake = Arc::clone(entry.value());
        f(handshake.as_ref())
    })
}

pub fn remove_http_handshake(id: u32) -> Option<Arc<StoredHttpHandshake>> {
    http_store()
        .handshakes
        .remove(&id)
        .map(|(_, handshake)| handshake)
}

struct HttpBodyStore {
    next_id: AtomicU32,
    bodies: DashMap<u32, HttpBodyHandle>,
}

impl Default for HttpBodyStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            bodies: DashMap::new(),
        }
    }
}

static HTTP_BODIES: OnceLock<HttpBodyStore> = OnceLock::new();

fn http_body_store() -> &'static HttpBodyStore {
    HTTP_BODIES.get_or_init(HttpBodyStore::default)
}

pub fn store_http_body(handle: HttpBodyHandle) -> u32 {
    let store = http_body_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.bodies.insert(id, handle);
    id
}

pub fn with_http_body<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&HttpBodyHandle) -> T,
{
    http_body_store()
        .bodies
        .get(&id)
        .map(|entry| f(entry.value()))
}

pub fn remove_http_body(id: u32) {
    http_body_store().bodies.remove(&id);
}

struct Http2HandshakeStore {
    next_id: AtomicU32,
    handshakes: DashMap<u32, Arc<StoredHttp2Handshake>>,
}

impl Default for Http2HandshakeStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            handshakes: DashMap::new(),
        }
    }
}

static HTTP2_HANDSHAKES: OnceLock<Http2HandshakeStore> = OnceLock::new();

fn http2_store() -> &'static Http2HandshakeStore {
    HTTP2_HANDSHAKES.get_or_init(Http2HandshakeStore::default)
}

pub fn store_http2_handshake(handshake: Http2Handshake) -> u32 {
    let store = http2_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store
        .handshakes
        .insert(id, Arc::new(StoredHttp2Handshake::new(handshake)));
    id
}

pub fn with_http2_handshake<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredHttp2Handshake) -> T,
{
    http2_store().handshakes.get(&id).map(|entry| {
        let handshake = Arc::clone(entry.value());
        f(handshake.as_ref())
    })
}

pub fn remove_http2_handshake(id: u32) -> Option<Arc<StoredHttp2Handshake>> {
    http2_store()
        .handshakes
        .remove(&id)
        .map(|(_, handshake)| handshake)
}

pub fn clear_http2_handshakes() {
    if let Some(store) = HTTP2_HANDSHAKES.get() {
        store.handshakes.clear();
    }
}

struct Http3ConnectionStore {
    next_id: AtomicU32,
    connections: DashMap<u32, Arc<QuinnConnection>>,
}

impl Default for Http3ConnectionStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            connections: DashMap::new(),
        }
    }
}

static HTTP3_CONNECTIONS: OnceLock<Http3ConnectionStore> = OnceLock::new();

fn http3_connection_store() -> &'static Http3ConnectionStore {
    HTTP3_CONNECTIONS.get_or_init(Http3ConnectionStore::default)
}

pub fn store_http3_connection(connection: Arc<QuinnConnection>) -> u32 {
    let store = http3_connection_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.connections.insert(id, connection);
    id
}

pub fn remove_http3_connection(id: u32) -> Option<Arc<QuinnConnection>> {
    http3_connection_store()
        .connections
        .remove(&id)
        .map(|(_, connection)| connection)
}

pub fn with_http3_connection<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&Arc<QuinnConnection>) -> T,
{
    http3_connection_store()
        .connections
        .get(&id)
        .map(|entry| f(entry.value()))
}

pub fn clear_http3_connections() {
    if let Some(store) = HTTP3_CONNECTIONS.get() {
        store.connections.clear();
    }
}

struct Http3HandshakeStore {
    next_id: AtomicU32,
    handshakes: DashMap<u32, Arc<StoredHttp3Handshake>>,
}

impl Default for Http3HandshakeStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            handshakes: DashMap::new(),
        }
    }
}

static HTTP3_HANDSHAKES: OnceLock<Http3HandshakeStore> = OnceLock::new();

fn http3_store() -> &'static Http3HandshakeStore {
    HTTP3_HANDSHAKES.get_or_init(Http3HandshakeStore::default)
}

pub fn store_http3_handshake(handshake: Http3Handshake) -> u32 {
    let store = http3_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store
        .handshakes
        .insert(id, Arc::new(StoredHttp3Handshake::new(handshake)));
    id
}

pub fn with_http3_handshake<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredHttp3Handshake) -> T,
{
    http3_store().handshakes.get(&id).map(|entry| {
        let handshake = Arc::clone(entry.value());
        f(handshake.as_ref())
    })
}

pub fn remove_http3_handshake(id: u32) -> Option<Arc<StoredHttp3Handshake>> {
    http3_store()
        .handshakes
        .remove(&id)
        .map(|(_, handshake)| handshake)
}

pub fn clear_http3_handshakes() {
    if let Some(store) = HTTP3_HANDSHAKES.get() {
        store.handshakes.clear();
    }
}

struct Http3StreamStore {
    next_id: AtomicU32,
    streams: DashMap<u32, Arc<StoredHttp3Stream>>,
}

impl Default for Http3StreamStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            streams: DashMap::new(),
        }
    }
}

static HTTP3_STREAMS: OnceLock<Http3StreamStore> = OnceLock::new();

fn http3_stream_store() -> &'static Http3StreamStore {
    HTTP3_STREAMS.get_or_init(Http3StreamStore::default)
}

pub struct StoredHttp3Stream {
    pub stream_id: u64,
    stream: Mutex<Option<Http3BidiStream>>,
}

impl StoredHttp3Stream {
    pub fn new(stream: Http3BidiStream) -> Self {
        let stream_id = stream.id();
        Self {
            stream_id,
            stream: Mutex::new(Some(stream)),
        }
    }

    pub fn take(&self) -> Option<Http3BidiStream> {
        self.stream.lock().unwrap().take()
    }
}

pub fn store_http3_stream(stream: Http3BidiStream) -> u32 {
    let store = http3_stream_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store
        .streams
        .insert(id, Arc::new(StoredHttp3Stream::new(stream)));
    id
}

pub fn with_http3_stream<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredHttp3Stream) -> T,
{
    http3_stream_store().streams.get(&id).map(|entry| {
        let stream = Arc::clone(entry.value());
        f(stream.as_ref())
    })
}

pub fn remove_http3_stream(id: u32) -> Option<Http3BidiStream> {
    http3_stream_store()
        .streams
        .remove(&id)
        .and_then(|(_, stored)| stored.take())
}

pub fn clear_http3_streams() {
    if let Some(store) = HTTP3_STREAMS.get() {
        store.streams.clear();
    }
}

struct WebSocketHandshakeStore {
    next_id: AtomicU32,
    handshakes: DashMap<u32, Arc<StoredWebSocketHandshake>>,
}

impl Default for WebSocketHandshakeStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            handshakes: DashMap::new(),
        }
    }
}

static WEBSOCKET_HANDSHAKES: OnceLock<WebSocketHandshakeStore> = OnceLock::new();

fn websocket_store() -> &'static WebSocketHandshakeStore {
    WEBSOCKET_HANDSHAKES.get_or_init(WebSocketHandshakeStore::default)
}

pub fn store_websocket_handshake(handshake: WebSocketHandshake) -> u32 {
    let store = websocket_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store
        .handshakes
        .insert(id, Arc::new(StoredWebSocketHandshake::new(handshake)));
    id
}

pub fn with_websocket_handshake<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredWebSocketHandshake) -> T,
{
    websocket_store().handshakes.get(&id).map(|entry| {
        let handshake = Arc::clone(entry.value());
        f(handshake.as_ref())
    })
}

pub fn remove_websocket_handshake(id: u32) -> Option<Arc<StoredWebSocketHandshake>> {
    websocket_store()
        .handshakes
        .remove(&id)
        .map(|(_, handshake)| handshake)
}

pub fn clear_http_handshakes() {
    if let Some(store) = HTTP_HANDSHAKES.get() {
        store.handshakes.clear();
    }
}

pub fn clear_websocket_handshakes() {
    if let Some(store) = WEBSOCKET_HANDSHAKES.get() {
        store.handshakes.clear();
    }
}

#[derive(Clone)]
pub struct StoredMessage {
    pub serializer: RawSocketSerializer,
    pub code: u64,
    pub raw: Bytes,
    pub message: WampMessage,
    pub args: Option<Bytes>,
    pub kwargs: Option<Bytes>,
}

struct MessageStore {
    next_id: AtomicU32,
    messages: DashMap<u32, Arc<StoredMessage>>,
}

impl Default for MessageStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            messages: DashMap::new(),
        }
    }
}

static MESSAGE_STORE: OnceLock<MessageStore> = OnceLock::new();

fn message_store() -> &'static MessageStore {
    MESSAGE_STORE.get_or_init(MessageStore::default)
}

pub fn store_message(message: StoredMessage) -> u32 {
    let store = message_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.messages.insert(id, Arc::new(message));
    id
}

pub fn with_message<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredMessage) -> T,
{
    message_store().messages.get(&id).map(|entry| {
        let message = Arc::clone(entry.value());
        f(message.as_ref())
    })
}

pub fn remove_message(id: u32) -> Option<Arc<StoredMessage>> {
    message_store().messages.remove(&id).map(|(_, msg)| msg)
}

pub fn clear_messages() {
    if let Some(store) = MESSAGE_STORE.get() {
        store.messages.clear();
    }
}

pub fn clone_message(id: u32) -> Option<u32> {
    let store = message_store();
    let message = store.messages.get(&id)?;
    let cloned = Arc::clone(message.value());
    let new_id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.messages.insert(new_id, cloned);
    Some(new_id)
}
