use std::io::{self, Write};

use bytes::{Bytes, BytesMut};
use tokio::{
    io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader},
    time::{self, Duration},
};

use crate::{
    config::{EndpointRuntimeConfig, HttpRouteMatch, TransportProtocol},
    http1_stream::{self, HttpBodyPhase},
    io_stream::IoStream,
    rawsocket::{self, NegotiatedSession, RAWSOCKET_MAGIC},
    HTTP1_INLINE_BODY_LIMIT,
};

const MAX_HTTP_HEADER_BYTES: usize = 64 * 1024;
const DEFAULT_HTTP_BODY_LIMIT: u64 = 4 * 1024 * 1024;
#[allow(dead_code)]
const HTTP_NOT_IMPLEMENTED_RESPONSE: &[u8] =
    b"HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
const HTTP_NOT_FOUND_RESPONSE: &[u8] =
    b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
const HTTP2_PREFACE: &[u8; 24] = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

/// Outcome of protocol negotiation for an incoming connection.
#[derive(Debug)]
pub enum NegotiatedConnection {
    RawSocket(NegotiatedSession),
    WebSocket(WebSocketHandshake),
    Http(HttpHandshake),
    Http2(Http2Handshake),
    Http3(Http3Handshake),
}

/// Error raised while negotiating the protocol for an incoming connection.
#[derive(Debug)]
pub enum NegotiationError {
    Timeout,
    Protocol(String),
    Io(io::Error),
}

#[derive(Debug)]
enum HttpHandshakeError {
    Negotiation(NegotiationError),
    Reject(HttpRejectResponse),
}

#[derive(Debug)]
struct HttpRejectResponse {
    stream: IoStream,
    version: u8,
    status: i32,
    headers: Vec<(String, String)>,
    detail: String,
}

impl HttpRejectResponse {
    fn status_only(stream: IoStream, version: u8, status: i32, detail: impl Into<String>) -> Self {
        Self {
            stream,
            version,
            status,
            headers: vec![("Connection".into(), "close".into())],
            detail: detail.into(),
        }
    }
}

impl From<io::Error> for NegotiationError {
    fn from(error: io::Error) -> Self {
        NegotiationError::Io(error)
    }
}

/// Parsed HTTP handshake data returned for plain HTTP requests.
#[derive(Debug)]
pub struct HttpHandshake {
    stream: IoStream,
    pub request: HttpRequest,
    pub body: HttpBodyPhase,
}

impl HttpHandshake {
    /// Converts the handshake into the underlying TCP stream.
    pub(crate) fn into_stream(self) -> IoStream {
        self.stream
    }

    pub(crate) fn into_parts(self) -> (IoStream, HttpRequest, HttpBodyPhase) {
        (self.stream, self.request, self.body)
    }

    /// Returns the HTTP version captured during negotiation.
    pub fn version(&self) -> u8 {
        self.request.version
    }

    pub fn body_len(&self) -> usize {
        match &self.body {
            HttpBodyPhase::Buffered(bytes) => bytes.len(),
            HttpBodyPhase::Finished => 0,
            HttpBodyPhase::NeedsStreaming {
                prefix,
                remaining_len,
            } => prefix.len() + remaining_len,
        }
    }

    fn try_into_websocket(self) -> Result<WebSocketHandshake, HttpHandshake> {
        if !self.request.method.eq_ignore_ascii_case("GET") {
            return Err(self);
        }
        if !header_equals(&self.request, "Upgrade", "websocket") {
            return Err(self);
        }
        if !header_contains_token(&self.request, "Connection", "upgrade") {
            return Err(self);
        }
        let Some(key) = self
            .request
            .header("Sec-WebSocket-Key")
            .map(|value| value.trim().to_string())
        else {
            return Err(self);
        };
        if self.body_len() > 0 {
            return Err(self);
        }

        let protocols = self
            .request
            .header("Sec-WebSocket-Protocol")
            .map(parse_comma_separated)
            .unwrap_or_default();
        let extensions = self
            .request
            .header("Sec-WebSocket-Extensions")
            .map(parse_comma_separated)
            .unwrap_or_default();
        let version = self
            .request
            .header("Sec-WebSocket-Version")
            .map(|value| value.trim().to_string());

        Ok(WebSocketHandshake {
            http: self,
            sec_websocket_key: key,
            sec_websocket_protocols: protocols,
            sec_websocket_version: version,
            sec_websocket_extensions: extensions,
        })
    }
}

/// Metadata extracted from a WebSocket handshake.
#[allow(dead_code)]
#[derive(Debug)]
pub struct WebSocketHandshake {
    pub http: HttpHandshake,
    pub sec_websocket_key: String,
    pub sec_websocket_protocols: Vec<String>,
    pub sec_websocket_version: Option<String>,
    pub sec_websocket_extensions: Vec<String>,
}

impl WebSocketHandshake {
    /// Converts the handshake into the underlying TCP stream.
    pub(crate) fn into_stream(self) -> IoStream {
        self.http.into_stream()
    }
}

/// Simple representation of an HTTP request parsed during negotiation.
#[allow(dead_code)]
#[derive(Debug)]
pub struct HttpRequest {
    pub method: String,
    pub target: String,
    pub version: u8,
    pub headers: Vec<(String, String)>,
}

#[allow(dead_code)]
#[derive(Debug)]
pub struct Http2Handshake {
    stream: Option<IoStream>,
    protocol: String,
    alpn: Option<String>,
    listener_protocols: Vec<String>,
}

impl Http2Handshake {
    pub(crate) fn into_stream(mut self) -> Option<IoStream> {
        self.stream.take()
    }

    pub(crate) fn split(self) -> (IoStream, Http2Handshake) {
        let Http2Handshake {
            stream,
            protocol,
            alpn,
            listener_protocols,
        } = self;
        let metadata = Http2Handshake {
            stream: None,
            protocol,
            alpn,
            listener_protocols,
        };
        (stream.expect("http2 stream already taken"), metadata)
    }

    pub fn protocol(&self) -> &str {
        self.protocol.as_str()
    }

    pub fn alpn(&self) -> Option<&str> {
        self.alpn.as_deref()
    }

    pub fn listener_protocols(&self) -> &[String] {
        &self.listener_protocols
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Http3Handshake {
    pub protocol: String,
    pub alpn: Option<String>,
    pub listener_protocols: Vec<String>,
}

impl Http3Handshake {
    pub(crate) fn from_endpoint(endpoint: &EndpointRuntimeConfig) -> Self {
        let protocol = "http/3".to_string();
        let alpn = endpoint.http_settings().and_then(|settings| {
            settings
                .alpn
                .iter()
                .find(|token| token.eq_ignore_ascii_case("h3") || token.starts_with("h3-"))
                .cloned()
        });
        let listener_protocols = endpoint
            .protocols
            .iter()
            .map(|protocol| protocol.identifier().to_string())
            .collect();
        Self {
            protocol,
            alpn,
            listener_protocols,
        }
    }

    pub fn protocol(&self) -> &str {
        self.protocol.as_str()
    }

    pub fn alpn(&self) -> Option<&str> {
        self.alpn.as_deref()
    }

    pub fn listener_protocols(&self) -> &[String] {
        &self.listener_protocols
    }
}

impl HttpRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

/// Performs protocol detection and handshake for an accepted TCP connection.
pub async fn negotiate_connection(
    mut stream: IoStream,
    endpoint: &EndpointRuntimeConfig,
) -> Result<NegotiatedConnection, NegotiationError> {
    let prefix = peek_handshake(&mut stream, endpoint.handshake_timeout).await?;
    if looks_like_http(&prefix) {
        if prefix == HTTP2_PREFACE[..4] {
            if !endpoint.supports_protocol(TransportProtocol::Http2) {
                return Err(NegotiationError::Protocol(
                    "http2 protocol disabled for listener".into(),
                ));
            }
            let protocol = "http/2".to_string();
            let alpn = stream.negotiated_alpn().or_else(|| {
                endpoint
                    .http_settings()
                    .and_then(|settings| settings.alpn.iter().find(|token| *token == "h2").cloned())
            });
            let listener_protocols = endpoint
                .protocols
                .iter()
                .map(|protocol| protocol.identifier().to_string())
                .collect();
            return Ok(NegotiatedConnection::Http2(Http2Handshake {
                stream: Some(stream),
                protocol,
                alpn,
                listener_protocols,
            }));
        }
        if !endpoint.supports_protocol(TransportProtocol::Http)
            && !endpoint.supports_protocol(TransportProtocol::Websocket)
        {
            return Err(NegotiationError::Protocol(
                "http/websocket protocols disabled for listener".into(),
            ));
        }
        let handshake = match parse_http_handshake(stream, endpoint).await {
            Ok(handshake) => handshake,
            Err(HttpHandshakeError::Negotiation(err)) => return Err(err),
            Err(HttpHandshakeError::Reject(reject)) => {
                let detail = reject.detail.clone();
                send_http_status_only_response(
                    reject.stream,
                    reject.version,
                    reject.status,
                    &reject.headers,
                )
                .await
                .map_err(NegotiationError::Io)?;
                return Err(NegotiationError::Protocol(detail));
            }
        };
        if endpoint.supports_protocol(TransportProtocol::Websocket) {
            match handshake.try_into_websocket() {
                Ok(websocket) => return Ok(NegotiatedConnection::WebSocket(websocket)),
                Err(handshake) => {
                    if endpoint.supports_protocol(TransportProtocol::Http) {
                        return Ok(NegotiatedConnection::Http(handshake));
                    }
                    return Err(NegotiationError::Protocol(
                        "websocket handshake rejected and HTTP disabled".into(),
                    ));
                }
            }
        }
        if endpoint.supports_protocol(TransportProtocol::Http) {
            return Ok(NegotiatedConnection::Http(handshake));
        }
        Err(NegotiationError::Protocol(
            "HTTP protocol disabled for listener".into(),
        ))
    } else if prefix[0] == RAWSOCKET_MAGIC {
        if !endpoint.supports_protocol(TransportProtocol::Rawsocket) {
            return Err(NegotiationError::Protocol(
                "rawsocket protocol disabled for listener".into(),
            ));
        }
        rawsocket::negotiate(stream, endpoint)
            .await
            .map(NegotiatedConnection::RawSocket)
            .map_err(|err| match err {
                rawsocket::HandshakeError::Protocol(msg) => {
                    NegotiationError::Protocol(msg.to_string())
                }
                rawsocket::HandshakeError::Io(io_err) => NegotiationError::Io(io_err),
            })
    } else {
        Err(NegotiationError::Protocol(
            "unsupported listener handshake preamble".into(),
        ))
    }
}

/// Sends a generic 501 response for HTTP requests that cannot be serviced yet.
#[allow(dead_code)]
pub async fn respond_http_not_implemented(handshake: HttpHandshake) -> io::Result<()> {
    send_http_response(handshake.into_stream(), HTTP_NOT_IMPLEMENTED_RESPONSE).await
}

/// Sends a generic 501 response for unsupported WebSocket negotiations.
#[allow(dead_code)]
pub async fn respond_websocket_not_implemented(handshake: WebSocketHandshake) -> io::Result<()> {
    send_http_response(handshake.into_stream(), HTTP_NOT_IMPLEMENTED_RESPONSE).await
}

#[allow(dead_code)]
async fn send_http_response(mut stream: IoStream, payload: &[u8]) -> io::Result<()> {
    stream.write_all(payload).await?;
    let _ = stream.shutdown().await;
    Ok(())
}

async fn send_http_status_only_response(
    mut stream: IoStream,
    version: u8,
    status: i32,
    headers: &[(String, String)],
) -> io::Result<()> {
    write_http_response_inner(&mut stream, version, status, headers, &[]).await?;
    let _ = stream.shutdown().await;
    Ok(())
}

async fn peek_handshake(
    stream: &mut IoStream,
    timeout: Duration,
) -> Result<[u8; 4], NegotiationError> {
    let mut buf = [0u8; 4];
    time::timeout(timeout, stream.read_exact(&mut buf))
        .await
        .map_err(|_| NegotiationError::Timeout)?
        .map_err(|err| {
            if err.kind() == io::ErrorKind::UnexpectedEof {
                NegotiationError::Protocol("connection closed before protocol negotiation".into())
            } else {
                NegotiationError::Io(err)
            }
        })?;
    stream.buffer_front(&buf);
    Ok(buf)
}

fn looks_like_http(buf: &[u8; 4]) -> bool {
    matches!(
        buf,
        b"GET " | b"POST" | b"HEAD" | b"PUT " | b"DELE" | b"OPTI" | b"PATC" | b"HTTP" | b"PRI "
    )
}

#[allow(dead_code)]
pub fn resolve_http_route(
    handshake: &HttpHandshake,
    endpoint: &EndpointRuntimeConfig,
) -> HttpRouteMatch {
    let method = handshake.request.method.as_str();
    let (path, query) = split_http_target(&handshake.request.target);
    let normalised_path = if path.is_empty() { "/" } else { path };
    let protocol = format!("http/1.{}", handshake.request.version);
    endpoint.match_http_route(normalised_path, query, method, &protocol)
}

pub(crate) fn split_http_target(target: &str) -> (&str, Option<&str>) {
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

#[allow(dead_code)]
pub async fn respond_http_not_found(handshake: HttpHandshake) -> io::Result<()> {
    send_http_response(handshake.into_stream(), HTTP_NOT_FOUND_RESPONSE).await
}

pub async fn write_http_response(
    mut stream: IoStream,
    version: u8,
    status: i32,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
) -> io::Result<()> {
    write_http_response_inner(&mut stream, version, status, &headers, &body).await?;
    let _ = stream.shutdown().await;
    Ok(())
}

pub async fn write_http_response_shared<W>(
    stream: &mut W,
    version: u8,
    status: i32,
    headers: &[(String, String)],
    body: &[u8],
) -> io::Result<()>
where
    W: AsyncWrite + Unpin,
{
    write_http_response_inner(stream, version, status, headers, body).await
}

async fn write_http_response_inner<W>(
    writer: &mut W,
    version: u8,
    status: i32,
    headers: &[(String, String)],
    body: &[u8],
) -> io::Result<()>
where
    W: AsyncWrite + Unpin,
{
    let reason = http_reason_phrase(status);
    let mut response = Vec::with_capacity(128 + headers.len() * 32);
    write!(
        &mut response,
        "HTTP/1.{} {} {}\r\n",
        version, status, reason
    )?;

    let mut has_content_length = false;
    let mut has_connection = false;
    for (name, value) in headers {
        if name.eq_ignore_ascii_case("content-length") {
            has_content_length = true;
        } else if name.eq_ignore_ascii_case("connection") {
            has_connection = true;
        }
        write!(&mut response, "{}: {}\r\n", name, value)?;
    }
    if !has_content_length {
        write!(&mut response, "Content-Length: {}\r\n", body.len())?;
    }
    if !has_connection {
        if version >= 1 {
            response.extend_from_slice(b"Connection: keep-alive\r\n");
        } else {
            response.extend_from_slice(b"Connection: close\r\n");
        }
    }
    response.extend_from_slice(b"\r\n");

    writer.write_all(&response).await?;
    if !body.is_empty() {
        writer.write_all(body).await?;
    }
    Ok(())
}

fn http_reason_phrase(status: i32) -> &'static str {
    match status {
        100 => "Continue",
        101 => "Switching Protocols",
        200 => "OK",
        201 => "Created",
        202 => "Accepted",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Payload Too Large",
        415 => "Unsupported Media Type",
        422 => "Unprocessable Entity",
        426 => "Upgrade Required",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        _ => "OK",
    }
}

#[allow(dead_code)]
pub async fn respond_http_method_not_allowed(
    handshake: HttpHandshake,
    allowed_methods: &[String],
) -> io::Result<()> {
    let allow_header = if allowed_methods.is_empty() {
        "".to_string()
    } else {
        allowed_methods.join(", ")
    };
    let response = format!(
        "HTTP/1.1 405 Method Not Allowed\r\nAllow: {}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        allow_header
    );
    let bytes = response.into_bytes();
    send_http_response(handshake.into_stream(), &bytes).await
}

async fn parse_http_handshake(
    stream: IoStream,
    endpoint: &EndpointRuntimeConfig,
) -> Result<HttpHandshake, HttpHandshakeError> {
    let timeout = endpoint.handshake_timeout;
    let max_body = endpoint
        .max_http_content_length
        .unwrap_or(DEFAULT_HTTP_BODY_LIMIT);

    time::timeout(timeout, async move {
        let mut reader = BufReader::with_capacity(1024, stream);
        let (request, body_phase) = match read_http_request_with_options(
            &mut reader,
            endpoint,
            false,
            HTTP1_INLINE_BODY_LIMIT,
        )
        .await
        {
            Ok(Some(parts)) => parts,
            Err(err) => {
                let stream = reader.into_inner();
                return Err(classify_http_handshake_error(stream, None, err));
            }
            Ok(None) => {
                return Err(HttpHandshakeError::Negotiation(NegotiationError::Protocol(
                    "connection closed before HTTP headers completed".into(),
                )))
            }
        };
        if let HttpBodyPhase::Buffered(bytes) = &body_phase {
            if bytes.len() as u64 > max_body {
                let stream = reader.into_inner();
                return Err(HttpHandshakeError::Reject(HttpRejectResponse::status_only(
                    stream,
                    request.version,
                    413,
                    format!(
                        "http body length {} exceeds configured limit {}",
                        bytes.len(),
                        max_body
                    ),
                )));
            }
        }
        if header_equals(&request, "Transfer-Encoding", "chunked") {
            let stream = reader.into_inner();
            return Err(HttpHandshakeError::Reject(HttpRejectResponse::status_only(
                stream,
                request.version,
                501,
                "chunked transfer encoding is not supported",
            )));
        }
        let buffered = Bytes::copy_from_slice(reader.buffer());
        reader.consume(buffered.len());
        let mut stream = reader.into_inner();
        if !buffered.is_empty() {
            stream.buffer_front(buffered.as_ref());
        }
        Ok(HttpHandshake {
            stream,
            request,
            body: body_phase,
        })
    })
    .await
    .map_err(|_| HttpHandshakeError::Negotiation(NegotiationError::Timeout))?
}

fn classify_http_handshake_error(
    stream: IoStream,
    version: Option<u8>,
    err: NegotiationError,
) -> HttpHandshakeError {
    let version = version.unwrap_or(1);
    match err {
        NegotiationError::Protocol(detail) => {
            let status = classify_http_error_status(&detail);
            if let Some(status) = status {
                HttpHandshakeError::Reject(HttpRejectResponse::status_only(
                    stream, version, status, detail,
                ))
            } else {
                HttpHandshakeError::Negotiation(NegotiationError::Protocol(detail))
            }
        }
        other => HttpHandshakeError::Negotiation(other),
    }
}

fn classify_http_error_status(detail: &str) -> Option<i32> {
    if detail.contains("exceeds configured limit") {
        Some(413)
    } else if detail == "chunked transfer encoding is not supported" {
        Some(501)
    } else if detail == "invalid Content-Length value"
        || detail == "conflicting Content-Length headers"
        || detail == "missing HTTP method"
        || detail == "missing request target"
        || detail == "incomplete HTTP headers"
        || detail == "HTTP headers exceed supported limit"
    {
        Some(400)
    } else {
        None
    }
}

pub async fn read_http_request<R>(
    reader: &mut BufReader<R>,
    endpoint: &EndpointRuntimeConfig,
) -> Result<Option<(HttpRequest, HttpBodyPhase)>, NegotiationError>
where
    R: AsyncRead + Unpin,
{
    read_http_request_with_options(reader, endpoint, true, HTTP1_INLINE_BODY_LIMIT).await
}

async fn read_http_request_with_options<R>(
    reader: &mut BufReader<R>,
    endpoint: &EndpointRuntimeConfig,
    allow_eof: bool,
    inline_limit: usize,
) -> Result<Option<(HttpRequest, HttpBodyPhase)>, NegotiationError>
where
    R: AsyncRead + Unpin,
{
    let mut buffer = BytesMut::with_capacity(1024);
    let read_timeout = endpoint.idle_timeout.unwrap_or(endpoint.handshake_timeout);
    let header_len =
        match read_until_header_terminator(reader, &mut buffer, read_timeout, allow_eof).await? {
            Some(len) => len,
            None => return Ok(None),
        };

    let (request, content_length_u64) = parse_http_request(&buffer[..header_len])?;

    let max_body = endpoint
        .max_http_content_length
        .unwrap_or(DEFAULT_HTTP_BODY_LIMIT);
    if let Some(len) = content_length_u64 {
        if len > max_body {
            return Err(NegotiationError::Protocol(format!(
                "http body length {} exceeds configured limit {}",
                len, max_body
            )));
        }
    }

    let content_length = match content_length_u64 {
        Some(len) => Some(usize::try_from(len).map_err(|_| {
            NegotiationError::Protocol("http body length exceeds platform addressable range".into())
        })?),
        None => None,
    };

    if header_equals(&request, "Transfer-Encoding", "chunked") {
        return Err(NegotiationError::Protocol(
            "chunked transfer encoding is not supported".into(),
        ));
    }

    let mut body_bytes = buffer.split_off(header_len);
    if let Some(len) = content_length {
        if len < body_bytes.len() {
            body_bytes.truncate(len);
        }
    }

    if let Some(len) = content_length {
        if len <= inline_limit {
            let mut remaining = len.saturating_sub(body_bytes.len());
            let timeout = endpoint.idle_timeout.unwrap_or(endpoint.handshake_timeout);
            while remaining > 0 {
                let request = remaining.min(4096);
                let start = body_bytes.len();
                body_bytes.resize(start + request, 0);
                let read = read_with_timeout(reader, &mut body_bytes[start..], timeout).await?;
                if read == 0 {
                    return Err(NegotiationError::Protocol(
                        "connection closed before receiving declared HTTP body".into(),
                    ));
                }
                body_bytes.truncate(start + read);
                remaining -= read;
            }
            return Ok(Some((
                request,
                HttpBodyPhase::Buffered(body_bytes.freeze()),
            )));
        } else {
            let prefix = body_bytes.freeze();
            let phase = http1_stream::classify_http_body(prefix, Some(len));
            return Ok(Some((request, phase)));
        }
    }

    Ok(Some((
        request,
        HttpBodyPhase::Buffered(body_bytes.freeze()),
    )))
}

async fn read_until_header_terminator<R>(
    reader: &mut BufReader<R>,
    buffer: &mut BytesMut,
    timeout: Duration,
    allow_eof: bool,
) -> Result<Option<usize>, NegotiationError>
where
    R: AsyncRead + Unpin,
{
    loop {
        if let Some(index) = find_header_terminator(buffer) {
            return Ok(Some(index + 4));
        }
        let start = buffer.len();
        buffer.resize(start + 1024, 0);
        let read = read_with_timeout(reader, &mut buffer[start..], timeout).await?;
        if read == 0 {
            buffer.truncate(start);
            if allow_eof && buffer.is_empty() {
                return Ok(None);
            } else {
                return Err(NegotiationError::Protocol(
                    "connection closed before HTTP headers completed".into(),
                ));
            }
        }
        buffer.truncate(start + read);
        if buffer.len() > MAX_HTTP_HEADER_BYTES {
            return Err(NegotiationError::Protocol(
                "HTTP headers exceed supported limit".into(),
            ));
        }
    }
}

fn find_header_terminator(buffer: &[u8]) -> Option<usize> {
    buffer
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|index| index)
}

async fn read_with_timeout<R>(
    reader: &mut BufReader<R>,
    buf: &mut [u8],
    timeout: Duration,
) -> Result<usize, NegotiationError>
where
    R: AsyncRead + Unpin,
{
    match time::timeout(timeout, reader.read(buf)).await {
        Ok(result) => result.map_err(NegotiationError::Io),
        Err(_) => Err(NegotiationError::Timeout),
    }
}

fn parse_http_request(bytes: &[u8]) -> Result<(HttpRequest, Option<u64>), NegotiationError> {
    let mut headers = [httparse::EMPTY_HEADER; 64];
    let mut request = httparse::Request::new(&mut headers);
    let status = request
        .parse(bytes)
        .map_err(|err| NegotiationError::Protocol(err.to_string()))?;
    match status {
        httparse::Status::Complete(_) => {}
        httparse::Status::Partial => {
            return Err(NegotiationError::Protocol("incomplete HTTP headers".into()))
        }
    }

    let method = request
        .method
        .ok_or_else(|| NegotiationError::Protocol("missing HTTP method".into()))?
        .to_string();
    let target = request
        .path
        .ok_or_else(|| NegotiationError::Protocol("missing request target".into()))?
        .to_string();
    let version = request.version.unwrap_or(1);

    let mut header_list = Vec::with_capacity(request.headers.len());
    let mut content_length: Option<u64> = None;

    for header in request.headers.iter() {
        let name = header.name.to_string();
        let value = String::from_utf8_lossy(header.value).trim().to_string();
        if name.eq_ignore_ascii_case("Content-Length") {
            let parsed = value
                .parse::<u64>()
                .map_err(|_| NegotiationError::Protocol("invalid Content-Length value".into()))?;
            if let Some(existing) = content_length {
                if existing != parsed {
                    return Err(NegotiationError::Protocol(
                        "conflicting Content-Length headers".into(),
                    ));
                }
            }
            content_length = Some(parsed);
        }
        header_list.push((name, value));
    }

    Ok((
        HttpRequest {
            method,
            target,
            version,
            headers: header_list,
        },
        content_length,
    ))
}

fn parse_comma_separated(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(|part| part.trim())
        .filter(|part| !part.is_empty())
        .map(|part| part.to_string())
        .collect()
}

fn header_equals(request: &HttpRequest, name: &str, expected: &str) -> bool {
    request
        .header(name)
        .map(|value| value.eq_ignore_ascii_case(expected))
        .unwrap_or(false)
}

fn header_contains_token(request: &HttpRequest, name: &str, token: &str) -> bool {
    request
        .header(name)
        .map(|value| {
            value
                .split(',')
                .any(|segment| segment.trim().eq_ignore_ascii_case(token))
        })
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{
        EndpointConfig, EndpointRuntimeConfig, HttpEndpointConfig, TlsMode, TransportProtocol,
    };
    use serde_json::Value as JsonValue;
    use std::collections::HashMap;
    use tokio::{net::TcpListener, net::TcpStream, sync::oneshot};

    fn runtime_config(
        handshake_timeout: Option<Duration>,
        rawsocket_exponent: u32,
    ) -> EndpointRuntimeConfig {
        let endpoint = EndpointConfig {
            host: "127.0.0.1".into(),
            port: 0,
            tls_mode: TlsMode::Disabled,
            idle_timeout: None,
            heartbeat_interval: None,
            heartbeat_timeout: None,
            handshake_timeout,
            max_http_content_length: None,
            max_rawsocket_size_exponent: Some(rawsocket_exponent),
            outbound_send_queue_capacity: None,
            websocket_path: None,
            sni_certificates: Vec::new(),
            client_auth: None,
            http_routes: Vec::new(),
            protocols: vec![
                TransportProtocol::Rawsocket,
                TransportProtocol::Http,
                TransportProtocol::Websocket,
            ],
            http: Some(HttpEndpointConfig {
                alpn: vec![],
                http3: None,
                options: HashMap::<String, JsonValue>::new(),
            }),
        };
        EndpointRuntimeConfig::try_from_endpoint(&endpoint).expect("config valid")
    }

    async fn send_rawsocket_handshake(stream: &mut TcpStream, exponent: u32) {
        let nibble = (exponent.saturating_sub(9)).min(15) as u8;
        let frame = [RAWSOCKET_MAGIC, (nibble << 4) | 0x01, 0, 0];
        stream.write_all(&frame).await.expect("handshake write");
    }

    async fn send_http2_preface(stream: &mut TcpStream) {
        stream
            .write_all(HTTP2_PREFACE)
            .await
            .expect("preface write");
    }

    #[tokio::test]
    async fn read_http_request_times_out_when_headers_stall() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(10)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut reader = BufReader::new(stream);
            let result = read_http_request(&mut reader, &config).await;
            tx.send(result).ok();
        });

        let _client = TcpStream::connect(addr).await.unwrap();
        match rx.await.unwrap() {
            Err(NegotiationError::Timeout) => {}
            other => panic!("expected timeout, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn read_http_request_times_out_when_body_stalls() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let mut config = runtime_config(Some(Duration::from_secs(1)), 16);
        config.idle_timeout = Some(Duration::from_millis(10));
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut reader = BufReader::new(stream);
            let result = read_http_request(&mut reader, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        client
            .write_all(
                b"POST /ingest HTTP/1.1\r\nHost: localhost\r\nContent-Length: 16\r\n\r\nbody",
            )
            .await
            .unwrap();

        match rx.await.unwrap() {
            Err(NegotiationError::Timeout) => {}
            other => panic!("expected timeout, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn read_http_request_returns_streaming_phase_for_large_incomplete_body() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut reader = BufReader::new(stream);
            let result = read_http_request(&mut reader, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        client
            .write_all(
                b"POST /ingest HTTP/1.1\r\nHost: localhost\r\nContent-Length: 70000\r\n\r\nbody",
            )
            .await
            .unwrap();

        match rx.await.unwrap().expect("request parsed") {
            Some((
                request,
                HttpBodyPhase::NeedsStreaming {
                    prefix,
                    remaining_len,
                },
            )) => {
                assert_eq!(request.method, "POST");
                assert_eq!(prefix, bytes::Bytes::from_static(b"body"));
                assert_eq!(remaining_len, 70000 - 4);
            }
            other => panic!("expected streaming phase, got {:?}", other),
        }
    }

    #[test]
    fn classify_http_error_status_maps_native_rejections() {
        assert_eq!(
            classify_http_error_status("http body length 123 exceeds configured limit 64"),
            Some(413)
        );
        assert_eq!(
            classify_http_error_status("chunked transfer encoding is not supported"),
            Some(501)
        );
        assert_eq!(
            classify_http_error_status("invalid Content-Length value"),
            Some(400)
        );
        assert_eq!(
            classify_http_error_status("some unrelated protocol error"),
            None
        );
    }

    #[tokio::test]
    async fn negotiate_detects_rawsocket() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate_connection(IoStream::plain(stream), &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        send_rawsocket_handshake(&mut client, 16).await;
        let mut response = [0u8; 4];
        client.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], RAWSOCKET_MAGIC);

        match rx.await.unwrap().expect("negotiation succeeds") {
            NegotiatedConnection::RawSocket(session) => {
                assert_eq!(session.max_message_size_exponent, 16);
            }
            other => panic!("unexpected negotiation outcome: {:?}", other),
        }
    }

    #[tokio::test]
    async fn negotiate_detects_http() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate_connection(IoStream::plain(stream), &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        client
            .write_all(b"GET /healthz HTTP/1.1\r\nHost: localhost\r\n\r\n")
            .await
            .unwrap();

        match rx.await.unwrap().expect("negotiation succeeds") {
            NegotiatedConnection::Http(handshake) => {
                assert_eq!(handshake.request.method, "GET");
                assert_eq!(handshake.request.target, "/healthz");
                assert_eq!(handshake.request.version, 1);
                respond_http_not_implemented(handshake).await.unwrap();
            }
            other => panic!("unexpected negotiation outcome: {:?}", other),
        }

        let mut buf = Vec::new();
        client.read_to_end(&mut buf).await.unwrap();
        let response = std::str::from_utf8(&buf).unwrap();
        assert!(response.starts_with("HTTP/1.1 501"));
    }

    #[tokio::test]
    async fn negotiate_detects_websocket() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate_connection(IoStream::plain(stream), &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        let request = b"GET /ws HTTP/1.1\r\n\
Host: localhost\r\n\
Upgrade: websocket\r\n\
Connection: Upgrade\r\n\
Sec-WebSocket-Key: SGVsbG9OZWdvdGlhdGlvbg==\r\n\
Sec-WebSocket-Version: 13\r\n\
Sec-WebSocket-Protocol: wamp.2.json, wamp.2.cbor\r\n\r\n";
        client.write_all(request).await.unwrap();

        match rx.await.unwrap().expect("negotiation succeeds") {
            NegotiatedConnection::WebSocket(handshake) => {
                assert_eq!(handshake.sec_websocket_key, "SGVsbG9OZWdvdGlhdGlvbg==");
                assert_eq!(handshake.sec_websocket_protocols.len(), 2);
                respond_websocket_not_implemented(handshake).await.unwrap();
            }
            other => panic!("unexpected negotiation outcome: {:?}", other),
        }

        let mut buf = Vec::new();
        client.read_to_end(&mut buf).await.unwrap();
        let response = std::str::from_utf8(&buf).unwrap();
        assert!(response.starts_with("HTTP/1.1 501"));
    }

    #[tokio::test]
    async fn negotiate_detects_http2() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let endpoint = EndpointConfig {
            host: "127.0.0.1".into(),
            port: 0,
            tls_mode: TlsMode::Disabled,
            idle_timeout: None,
            heartbeat_interval: None,
            heartbeat_timeout: None,
            handshake_timeout: Some(Duration::from_secs(1)),
            max_http_content_length: None,
            max_rawsocket_size_exponent: Some(16),
            outbound_send_queue_capacity: None,
            websocket_path: None,
            sni_certificates: Vec::new(),
            client_auth: None,
            http_routes: Vec::new(),
            protocols: vec![TransportProtocol::Rawsocket, TransportProtocol::Http],
            http: Some(HttpEndpointConfig {
                alpn: vec!["h2".into(), "http/1.1".into()],
                http3: None,
                options: HashMap::new(),
            }),
        };
        let config = EndpointRuntimeConfig::try_from_endpoint(&endpoint).unwrap();
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate_connection(IoStream::plain(stream), &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        send_http2_preface(&mut client).await;

        match rx.await.unwrap().expect("negotiation succeeds") {
            NegotiatedConnection::Http2(handshake) => {
                if let Some(mut stream) = handshake.into_stream() {
                    let _ = stream.shutdown().await;
                }
            }
            other => panic!("unexpected negotiation outcome: {:?}", other),
        }
    }

    #[tokio::test]
    async fn negotiate_times_out_without_data() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(50)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate_connection(IoStream::plain(stream), &config).await;
            tx.send(result).ok();
        });

        let _client = TcpStream::connect(addr).await.unwrap();
        let err = rx.await.unwrap().expect_err("negotiation fails");
        match err {
            NegotiationError::Timeout => {}
            other => panic!("unexpected error: {:?}", other),
        }
    }
}
