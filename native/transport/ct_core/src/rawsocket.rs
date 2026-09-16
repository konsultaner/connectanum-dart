use std::fs::File;
use std::io;
use std::sync::Arc;
use std::time::Duration;

#[cfg(any(target_os = "linux", target_os = "macos"))]
use std::os::fd::{AsRawFd, OwnedFd};

#[cfg(any(target_os = "linux", target_os = "macos"))]
use tokio::io::unix::AsyncFd;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time;

use crate::config::EndpointRuntimeConfig;
use crate::io_stream::{IoReadHalf, IoStream, IoWriteHalf};

pub(crate) const RAWSOCKET_MAGIC: u8 = 0x7F;
const RAWSOCKET_UPGRADE_MAGIC: u8 = 0x3F;

const SERIALIZER_JSON: u8 = 0x01;
const SERIALIZER_MSGPACK: u8 = 0x02;
const SERIALIZER_CBOR: u8 = 0x03;
const SERIALIZER_UBJSON: u8 = 0x04;
const SERIALIZER_FLATBUFFERS: u8 = 0x05;

const ERROR_SERIALIZER_UNSUPPORTED: u8 = 1;
const ERROR_MESSAGE_LENGTH_EXCEEDED: u8 = 2;
const ERROR_RESERVED_BITS: u8 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Serializer {
    Json,
    MessagePack,
    Cbor,
    Ubjson,
    Flatbuffers,
}

#[derive(Debug)]
pub struct NegotiatedSession {
    pub reader: IoReadHalf,
    pub writer: IoWriteHalf,
    pub file_sender: Option<RawSocketFileSender>,
    pub serializer: Serializer,
    pub max_message_size_exponent: u32,
    #[allow(dead_code)]
    pub upgraded: bool,
}

pub struct RawSocketFileSender {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    socket: AsyncFd<OwnedFd>,
}

impl std::fmt::Debug for RawSocketFileSender {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RawSocketFileSender")
            .finish_non_exhaustive()
    }
}

impl RawSocketFileSender {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    fn from_stream(stream: &IoStream) -> io::Result<Option<Self>> {
        stream
            .try_clone_plain_fd()?
            .map(AsyncFd::new)
            .transpose()
            .map(|socket| socket.map(|socket| Self { socket }))
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    fn from_stream(_stream: &IoStream) -> io::Result<Option<Self>> {
        Ok(None)
    }

    #[cfg(target_os = "linux")]
    pub async fn send_file_segment(
        &self,
        file: &Arc<File>,
        mut offset: u64,
        mut remaining: usize,
    ) -> io::Result<()> {
        const MAX_SENDFILE_COUNT: usize = 0x7ffff000;

        while remaining > 0 {
            let mut readiness = self.socket.writable().await?;
            let count = remaining.min(MAX_SENDFILE_COUNT);
            let result = readiness.try_io(|socket| {
                let mut file_offset = libc::off_t::try_from(offset).map_err(|_| {
                    io::Error::new(io::ErrorKind::InvalidInput, "file offset exceeds off_t")
                })?;
                let sent = unsafe {
                    libc::sendfile(
                        socket.get_ref().as_raw_fd(),
                        file.as_raw_fd(),
                        &mut file_offset,
                        count,
                    )
                };
                if sent < 0 {
                    Err(io::Error::last_os_error())
                } else {
                    Ok(sent as usize)
                }
            });

            match result {
                Ok(Ok(0)) => {
                    return Err(io::Error::new(
                        io::ErrorKind::UnexpectedEof,
                        "file ended before the queued RawSocket segment",
                    ));
                }
                Ok(Ok(sent)) => {
                    crate::record_rawsocket_zero_copy_file_write(sent);
                    offset += sent as u64;
                    remaining -= sent;
                }
                Ok(Err(err)) if err.kind() == io::ErrorKind::Interrupted => continue,
                Ok(Err(err)) => return Err(err),
                Err(_would_block) => continue,
            }
        }
        Ok(())
    }

    #[cfg(target_os = "macos")]
    pub async fn send_file_segment(
        &self,
        file: &Arc<File>,
        mut offset: u64,
        mut remaining: usize,
    ) -> io::Result<()> {
        const MAX_SENDFILE_COUNT: usize = 0x7ffff000;

        while remaining > 0 {
            let mut readiness = self.socket.writable().await?;
            let count = remaining.min(MAX_SENDFILE_COUNT);
            let result = readiness.try_io(|socket| {
                let file_offset = libc::off_t::try_from(offset).map_err(|_| {
                    io::Error::new(io::ErrorKind::InvalidInput, "file offset exceeds off_t")
                })?;
                let mut sent = libc::off_t::try_from(count).map_err(|_| {
                    io::Error::new(io::ErrorKind::InvalidInput, "file length exceeds off_t")
                })?;
                let status = unsafe {
                    libc::sendfile(
                        file.as_raw_fd(),
                        socket.get_ref().as_raw_fd(),
                        file_offset,
                        &mut sent,
                        std::ptr::null_mut(),
                        0,
                    )
                };
                let sent = usize::try_from(sent).map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::InvalidData,
                        "sendfile returned negative length",
                    )
                })?;
                if status == 0 || sent > 0 {
                    Ok(sent)
                } else {
                    Err(io::Error::last_os_error())
                }
            });

            match result {
                Ok(Ok(0)) => {
                    return Err(io::Error::new(
                        io::ErrorKind::UnexpectedEof,
                        "file ended before the queued RawSocket segment",
                    ));
                }
                Ok(Ok(sent)) => {
                    crate::record_rawsocket_zero_copy_file_write(sent);
                    offset += sent as u64;
                    remaining -= sent;
                }
                Ok(Err(err)) if err.kind() == io::ErrorKind::Interrupted => continue,
                Ok(Err(err)) => return Err(err),
                Err(_would_block) => continue,
            }
        }
        Ok(())
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    pub async fn send_file_segment(
        &self,
        _file: &Arc<File>,
        _offset: u64,
        _remaining: usize,
    ) -> io::Result<()> {
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "zero-copy RawSocket file segments require Linux or macOS",
        ))
    }
}

#[derive(Debug)]
pub enum HandshakeError {
    Protocol(&'static str),
    Io(io::Error),
}

impl From<io::Error> for HandshakeError {
    fn from(err: io::Error) -> Self {
        HandshakeError::Io(err)
    }
}

pub async fn negotiate(
    mut stream: IoStream,
    endpoint: &EndpointRuntimeConfig,
) -> Result<NegotiatedSession, HandshakeError> {
    let mut buf = [0u8; 4];
    read_with_timeout(&mut stream, &mut buf, endpoint.handshake_timeout).await?;

    if buf[0] != RAWSOCKET_MAGIC {
        send_error(&mut stream, ERROR_RESERVED_BITS).await?;
        return Err(HandshakeError::Protocol("invalid rawsocket magic"));
    }

    if buf[2] != 0 || buf[3] != 0 {
        send_error(&mut stream, ERROR_RESERVED_BITS).await?;
        return Err(HandshakeError::Protocol("reserved bits must be zero"));
    }

    let serializer = match buf[1] & 0x0F {
        SERIALIZER_JSON => Serializer::Json,
        SERIALIZER_MSGPACK => Serializer::MessagePack,
        SERIALIZER_CBOR => Serializer::Cbor,
        SERIALIZER_UBJSON => Serializer::Ubjson,
        SERIALIZER_FLATBUFFERS => Serializer::Flatbuffers,
        _value => {
            send_error(&mut stream, ERROR_SERIALIZER_UNSUPPORTED).await?;
            return Err(HandshakeError::Protocol("unsupported serializer"));
        }
    };

    let client_exponent = ((buf[1] & 0xF0) >> 4) as u32 + 9;
    let desired_exponent = endpoint
        .max_rawsocket_size_exponent
        .min(crate::config::CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT);
    let response_exponent = client_exponent.min(desired_exponent.min(24));

    if response_exponent < 9 {
        send_error(&mut stream, ERROR_MESSAGE_LENGTH_EXCEEDED).await?;
        return Err(HandshakeError::Protocol(
            "negotiated exponent below minimum",
        ));
    }

    let response_byte = (((response_exponent - 9).min(15)) as u8) << 4 | (buf[1] & 0x0F);
    stream
        .write_all(&[RAWSOCKET_MAGIC, response_byte, 0, 0])
        .await?;

    let _ = stream.set_nodelay(true);

    let mut final_exponent = response_exponent;
    let mut upgraded = false;

    if desired_exponent > response_exponent && client_exponent >= 24 {
        // Retain partial lookahead across cancellation: read_exact can consume
        // a standard frame's first byte before the optional probe times out.
        let mut buf = [0u8; 2];
        let mut filled = 0;
        match time::timeout(endpoint.handshake_timeout, async {
            while filled < buf.len() {
                let read = stream.read(&mut buf[filled..]).await?;
                if read == 0 {
                    return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "early eof"));
                }
                filled += read;
            }
            Ok(())
        })
        .await
        {
            Ok(Ok(())) if buf[0] == RAWSOCKET_UPGRADE_MAGIC => {
                let client_upgrade = ((buf[1] & 0x0F) as u32) + 25;
                let negotiated_upgrade = desired_exponent
                    .min(client_upgrade)
                    .min(crate::config::CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT);
                if negotiated_upgrade <= 24 {
                    send_error(&mut stream, ERROR_MESSAGE_LENGTH_EXCEEDED).await?;
                    return Err(HandshakeError::Protocol(
                        "invalid upgrade exponent requested",
                    ));
                }
                let upgrade_byte = ((negotiated_upgrade - 25).min(15) as u8) & 0x0F;
                stream
                    .write_all(&[RAWSOCKET_UPGRADE_MAGIC, upgrade_byte])
                    .await?;
                final_exponent = negotiated_upgrade;
                upgraded = true;
            }
            Ok(Ok(())) => {
                // Exponent-24 peers can start WAMP immediately; preserve the
                // speculative bytes when they did not request the extension.
                stream.buffer_front(&buf);
            }
            Ok(Err(err)) => return Err(HandshakeError::Io(err)),
            Err(_) => {
                // Continue with the base exponent without discarding peer bytes.
                stream.buffer_front(&buf[..filled]);
            }
        }
    }

    let file_sender = if matches!(serializer, Serializer::MessagePack | Serializer::Cbor) {
        RawSocketFileSender::from_stream(&stream)?
    } else {
        None
    };
    let (reader, writer) = tokio::io::split(stream);

    Ok(NegotiatedSession {
        reader,
        writer,
        file_sender,
        serializer,
        max_message_size_exponent: final_exponent,
        upgraded,
    })
}

pub async fn connect(
    mut stream: IoStream,
    serializer: Serializer,
    desired_exponent: u32,
    handshake_timeout: Duration,
) -> Result<NegotiatedSession, HandshakeError> {
    let requested_exponent =
        desired_exponent.min(crate::config::CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT);
    let serializer_id = serializer_to_wire_id(serializer)
        .ok_or(HandshakeError::Protocol("unsupported serializer"))?;
    let base_exponent = requested_exponent.min(24);
    let header = [
        RAWSOCKET_MAGIC,
        (((base_exponent.saturating_sub(9)).min(15) as u8) << 4) | serializer_id,
        0,
        0,
    ];
    time::timeout(handshake_timeout, stream.write_all(&header))
        .await
        .map_err(|_| HandshakeError::Protocol("rawsocket handshake timed out"))??;

    let mut response = [0u8; 4];
    read_with_timeout(&mut stream, &mut response, handshake_timeout).await?;
    if response[0] != RAWSOCKET_MAGIC {
        return Err(HandshakeError::Protocol("invalid rawsocket response magic"));
    }
    if response[2] != 0 || response[3] != 0 {
        return Err(HandshakeError::Protocol(
            "rawsocket reserved bits must be zero",
        ));
    }
    let serializer_id = response[1] & 0x0F;
    if serializer_id == 0 {
        let response_code = response[1] >> 4;
        return Err(HandshakeError::Protocol(match response_code {
            ERROR_SERIALIZER_UNSUPPORTED => "rawsocket serializer unsupported",
            ERROR_MESSAGE_LENGTH_EXCEEDED => "rawsocket message length exceeded",
            ERROR_RESERVED_BITS => "rawsocket reserved bits error",
            _ => "rawsocket handshake failed",
        }));
    }
    let negotiated_serializer = serializer_from_wire_id(serializer_id).ok_or(
        HandshakeError::Protocol("rawsocket serializer response invalid"),
    )?;
    if negotiated_serializer != serializer {
        return Err(HandshakeError::Protocol("rawsocket serializer mismatch"));
    }

    let mut final_exponent = ((response[1] & 0xF0) >> 4) as u32 + 9;
    let mut upgraded = false;
    if requested_exponent > 24 && final_exponent >= 24 {
        let upgrade = [
            RAWSOCKET_UPGRADE_MAGIC,
            ((requested_exponent - 25).min(15) as u8) & 0x0F,
        ];
        time::timeout(handshake_timeout, stream.write_all(&upgrade))
            .await
            .map_err(|_| HandshakeError::Protocol("rawsocket upgrade timed out"))??;
        let mut upgrade_response = [0u8; 2];
        read_with_timeout(&mut stream, &mut upgrade_response, handshake_timeout).await?;
        if upgrade_response[0] != RAWSOCKET_UPGRADE_MAGIC {
            return Err(HandshakeError::Protocol(
                "invalid rawsocket upgrade response",
            ));
        }
        final_exponent = ((upgrade_response[1] & 0x0F) as u32) + 25;
        upgraded = true;
    }

    let _ = stream.set_nodelay(true);
    let file_sender = if matches!(serializer, Serializer::MessagePack | Serializer::Cbor) {
        RawSocketFileSender::from_stream(&stream)?
    } else {
        None
    };
    let (reader, writer) = tokio::io::split(stream);
    Ok(NegotiatedSession {
        reader,
        writer,
        file_sender,
        serializer,
        max_message_size_exponent: final_exponent,
        upgraded,
    })
}

fn serializer_to_wire_id(serializer: Serializer) -> Option<u8> {
    match serializer {
        Serializer::Json => Some(SERIALIZER_JSON),
        Serializer::MessagePack => Some(SERIALIZER_MSGPACK),
        Serializer::Cbor => Some(SERIALIZER_CBOR),
        Serializer::Ubjson => Some(SERIALIZER_UBJSON),
        Serializer::Flatbuffers => Some(SERIALIZER_FLATBUFFERS),
    }
}

fn serializer_from_wire_id(value: u8) -> Option<Serializer> {
    match value {
        SERIALIZER_JSON => Some(Serializer::Json),
        SERIALIZER_MSGPACK => Some(Serializer::MessagePack),
        SERIALIZER_CBOR => Some(Serializer::Cbor),
        SERIALIZER_UBJSON => Some(Serializer::Ubjson),
        SERIALIZER_FLATBUFFERS => Some(Serializer::Flatbuffers),
        _ => None,
    }
}

async fn read_with_timeout(
    stream: &mut IoStream,
    buf: &mut [u8],
    timeout: Duration,
) -> Result<(), HandshakeError> {
    time::timeout(timeout, stream.read_exact(buf))
        .await
        .map_err(|_| HandshakeError::Protocol("rawsocket handshake timed out"))??;
    Ok(())
}

async fn send_error(stream: &mut IoStream, code: u8) -> io::Result<()> {
    let frame = [RAWSOCKET_MAGIC, code << 4, 0, 0];
    stream.write_all(&frame).await?;
    let _ = stream.shutdown().await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{
        EndpointConfig, EndpointRuntimeConfig, HttpEndpointConfig, TlsMode, TransportProtocol,
    };
    use crate::io_stream::IoStream;
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

    async fn send_handshake_with_serializer(stream: &mut TcpStream, exponent: u32, serializer: u8) {
        let nibble = (exponent.saturating_sub(9)).min(15) as u8;
        let frame = [RAWSOCKET_MAGIC, (nibble << 4) | serializer, 0, 0];
        stream.write_all(&frame).await.expect("handshake write");
    }

    async fn send_handshake(stream: &mut TcpStream, exponent: u32) {
        send_handshake_with_serializer(stream, exponent, SERIALIZER_JSON).await;
    }

    async fn send_upgrade(stream: &mut TcpStream, exponent: u32) {
        let nibble = (exponent.saturating_sub(25)).min(15) as u8;
        stream
            .write_all(&[RAWSOCKET_UPGRADE_MAGIC, nibble])
            .await
            .expect("upgrade write");
    }

    fn successful_handshake(
        result: Result<NegotiatedSession, HandshakeError>,
    ) -> NegotiatedSession {
        assert!(result.is_ok());
        result.unwrap()
    }

    async fn assert_complete_wire(reader: impl tokio::io::AsyncRead + Unpin, expected: &[u8]) {
        let mut received = Vec::new();
        time::timeout(
            Duration::from_secs(2),
            reader
                .take(expected.len() as u64 + 1)
                .read_to_end(&mut received),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(received, expected);
    }

    #[tokio::test]
    async fn negotiate_success_returns_session() {
        let (socket, mut client) = socket_pair().await;
        let config = runtime_config(Some(Duration::from_millis(500)), 16);
        send_handshake(&mut client, 16).await;
        let session = successful_handshake(negotiate(IoStream::plain(socket), &config).await);
        assert_eq!(session.max_message_size_exponent, 16);
        assert_eq!(session.serializer, Serializer::Json);
        assert!(!session.upgraded);
        assert!(session.file_sender.is_none());
        drop(session);
        assert_complete_wire(client, &[0x7f, 0x71, 0, 0]).await;
    }

    #[tokio::test]
    async fn negotiate_clamps_to_endpoint_exponent() {
        let (socket, mut client) = socket_pair().await;
        let config = runtime_config(Some(Duration::from_secs(1)), 12);
        send_handshake(&mut client, 24).await;
        let session = successful_handshake(negotiate(IoStream::plain(socket), &config).await);
        assert_eq!(session.max_message_size_exponent, 12);
        assert!(!session.upgraded);
        drop(session);
        assert_complete_wire(client, &[0x7f, 0x31, 0, 0]).await;
    }

    #[tokio::test]
    async fn negotiate_performs_upgrade() {
        let (socket, mut client) = socket_pair().await;
        let config = runtime_config(Some(Duration::from_secs(1)), 30);
        send_handshake(&mut client, 24).await;
        send_upgrade(&mut client, 30).await;
        let session = successful_handshake(negotiate(IoStream::plain(socket), &config).await);
        assert_eq!(session.max_message_size_exponent, 30);
        assert!(session.upgraded);
        drop(session);
        assert_complete_wire(client, &[0x7f, 0xf1, 0, 0, 0x3f, 5]).await;
    }

    #[tokio::test]
    async fn negotiate_preserves_standard_peer_bytes_when_upgrade_is_available() {
        let (socket, mut client) = socket_pair().await;
        let config = runtime_config(Some(Duration::from_millis(500)), 30);
        send_handshake(&mut client, 24).await;
        client.write_all(&[0x00, 0x05]).await.unwrap();
        client.shutdown().await.unwrap();
        let mut session = successful_handshake(negotiate(IoStream::plain(socket), &config).await);
        assert_eq!(session.max_message_size_exponent, 24);
        assert!(!session.upgraded);
        assert_complete_wire(&mut session.reader, &[0x00, 0x05]).await;
        drop(session);
        assert_complete_wire(client, &[0x7f, 0xf1, 0, 0]).await;
    }

    #[tokio::test]
    async fn server_upgrade_timeout_retains_partial_standard_frame() {
        let frame = [0x00, 0x00, 0x00, 0x03, b'[', b'1', b']'];
        for prefix_length in [0, 1] {
            let (socket, mut peer) = socket_pair().await;
            let mut stream = IoStream::plain(socket);
            // Model the protocol detector's buffered bytes. This guarantees
            // the partial probe is consumed before the virtual deadline.
            let mut buffered = vec![0x7f, 0xf1, 0, 0];
            buffered.extend_from_slice(&frame[..prefix_length]);
            stream.buffer_front(&buffered);
            let config = runtime_config(Some(Duration::from_secs(1)), 30);
            time::pause();
            let started = time::Instant::now();
            let mut session = successful_handshake(negotiate(stream, &config).await);
            assert!(started.elapsed() >= config.handshake_timeout);
            time::resume();

            assert_eq!(session.max_message_size_exponent, 24);
            assert!(!session.upgraded);
            peer.write_all(&frame[prefix_length..]).await.unwrap();
            peer.shutdown().await.unwrap();
            let mut received = Vec::new();
            time::timeout(
                Duration::from_secs(1),
                session.reader.read_to_end(&mut received),
            )
            .await
            .unwrap()
            .unwrap();
            assert_eq!(received, frame, "buffered prefix length {prefix_length}");
            drop(session);
            assert_complete_wire(peer, &[0x7f, 0xf1, 0, 0]).await;
        }
    }

    #[tokio::test]
    async fn server_upgrade_rejects_eof_with_empty_or_partial_probe() {
        for prefix in [vec![], vec![0x3f]] {
            let (socket, mut peer) = socket_pair().await;
            let mut stream = IoStream::plain(socket);
            let mut buffered = vec![0x7f, 0xf1, 0, 0];
            buffered.extend_from_slice(&prefix);
            stream.buffer_front(&buffered);
            peer.shutdown().await.unwrap();
            let config = runtime_config(Some(Duration::from_secs(1)), 30);
            let result = negotiate(stream, &config).await;
            assert!(matches!(result, Err(HandshakeError::Io(error))
                if error.kind() == io::ErrorKind::UnexpectedEof));
        }
    }

    #[tokio::test]
    async fn server_upgrade_joins_buffered_prefix_and_socket_suffix() {
        let (socket, mut peer) = socket_pair().await;
        let mut stream = IoStream::plain(socket);
        stream.buffer_front(&[0x7f, 0xf1, 0, 0, 0x3f]);
        peer.write_all(&[5, 0, 0, 0, 3, b'[', b'1', b']'])
            .await
            .unwrap();
        peer.shutdown().await.unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 30);
        let mut session = successful_handshake(negotiate(stream, &config).await);
        assert!(session.upgraded);
        assert_eq!(session.max_message_size_exponent, 30);
        assert_complete_wire(&mut session.reader, &[0, 0, 0, 3, b'[', b'1', b']']).await;
        drop(session);
        assert_complete_wire(peer, &[0x7f, 0xf1, 0, 0, 0x3f, 5]).await;
    }

    #[tokio::test]
    async fn native_cbor_peer_starts_wamp_without_optional_upgrade() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(500)), 30);

        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            negotiate(IoStream::plain(stream), &config).await
        });

        let stream = TcpStream::connect(addr).await.unwrap();
        let mut client = successful_handshake(
            connect(
                IoStream::plain(stream),
                Serializer::Cbor,
                24,
                Duration::from_millis(500),
            )
            .await,
        );
        client.writer.write_all(&[0x00, 0x05]).await.unwrap();
        client.writer.shutdown().await.unwrap();

        let mut server = successful_handshake(server.await.unwrap());
        assert_eq!(client.max_message_size_exponent, 24);
        assert_eq!(server.max_message_size_exponent, 24);
        assert!(!client.upgraded);
        assert!(!server.upgraded);
        assert_complete_wire(&mut server.reader, &[0x00, 0x05]).await;
    }

    #[tokio::test]
    async fn negotiate_supports_all_serializers() {
        let serializers = [
            (SERIALIZER_JSON, Serializer::Json),
            (SERIALIZER_MSGPACK, Serializer::MessagePack),
            (SERIALIZER_CBOR, Serializer::Cbor),
            (SERIALIZER_UBJSON, Serializer::Ubjson),
            (SERIALIZER_FLATBUFFERS, Serializer::Flatbuffers),
        ];

        for (serializer_byte, expected_variant) in serializers {
            let (socket, mut client) = socket_pair().await;
            let config = runtime_config(Some(Duration::from_millis(200)), 16);
            send_handshake_with_serializer(&mut client, 16, serializer_byte).await;
            let session = successful_handshake(negotiate(IoStream::plain(socket), &config).await);
            assert_eq!(session.serializer, expected_variant);
            assert_eq!(session.max_message_size_exponent, 16);
            assert!(!session.upgraded);
            assert_eq!(
                session.file_sender.is_some(),
                cfg!(any(target_os = "linux", target_os = "macos"))
                    && (serializer_byte == 2 || serializer_byte == 3)
            );
            drop(session);
            assert_complete_wire(client, &[0x7f, 0x70 | serializer_byte, 0, 0]).await;
        }
    }

    #[tokio::test]
    async fn negotiate_rejects_unsupported_serializer() {
        let (socket, mut client) = socket_pair().await;
        let config = runtime_config(Some(Duration::from_millis(200)), 16);
        send_handshake_with_serializer(&mut client, 16, 0x06).await;
        let result = negotiate(IoStream::plain(socket), &config).await;
        assert!(matches!(
            result,
            Err(HandshakeError::Protocol("unsupported serializer"))
        ));
        assert_complete_wire(client, &[0x7f, 0x10, 0, 0]).await;
    }

    #[tokio::test]
    async fn negotiate_exponent_matrix() {
        struct Case {
            handshake_exponent: u32,
            upgrade_request: Option<u32>,
            endpoint_exponent: u32,
            expect_ok: bool,
            expect_exponent: Option<u32>,
            expect_upgrade: bool,
        }

        let cases = [
            Case {
                handshake_exponent: 9,
                upgrade_request: None,
                endpoint_exponent: 16,
                expect_ok: true,
                expect_exponent: Some(9),
                expect_upgrade: false,
            },
            Case {
                handshake_exponent: 10,
                upgrade_request: None,
                endpoint_exponent: 10,
                expect_ok: true,
                expect_exponent: Some(10),
                expect_upgrade: false,
            },
            Case {
                handshake_exponent: 17,
                upgrade_request: None,
                endpoint_exponent: 30,
                expect_ok: true,
                expect_exponent: Some(17),
                expect_upgrade: false,
            },
            Case {
                handshake_exponent: 18,
                upgrade_request: None,
                endpoint_exponent: 24,
                expect_ok: true,
                expect_exponent: Some(18),
                expect_upgrade: false,
            },
            Case {
                handshake_exponent: 24,
                upgrade_request: None,
                endpoint_exponent: 30,
                expect_ok: true,
                expect_exponent: Some(24),
                expect_upgrade: false,
            },
            Case {
                handshake_exponent: 24,
                upgrade_request: Some(25),
                endpoint_exponent: 30,
                expect_ok: true,
                expect_exponent: Some(25),
                expect_upgrade: true,
            },
            Case {
                handshake_exponent: 24,
                upgrade_request: Some(30),
                endpoint_exponent: 30,
                expect_ok: true,
                expect_exponent: Some(30),
                expect_upgrade: true,
            },
            Case {
                handshake_exponent: 24,
                upgrade_request: Some(31),
                endpoint_exponent: 30,
                expect_ok: true,
                expect_exponent: Some(30),
                expect_upgrade: true,
            },
            Case {
                handshake_exponent: 24,
                upgrade_request: Some(40),
                endpoint_exponent: 28,
                expect_ok: true,
                expect_exponent: Some(28),
                expect_upgrade: true,
            },
        ];

        for case in cases {
            let (socket, mut peer) = socket_pair().await;
            let config = runtime_config(Some(Duration::from_millis(200)), case.endpoint_exponent);
            send_handshake(&mut peer, case.handshake_exponent).await;
            if let Some(req) = case.upgrade_request {
                send_upgrade(&mut peer, req).await;
            }
            // Only an eligible peer omitting the optional upgrade needs to
            // leave its write half open until the server's probe expires.
            if case.upgrade_request.is_some()
                || case.handshake_exponent < 24
                || case.endpoint_exponent <= 24
            {
                peer.shutdown().await.unwrap();
            }

            match negotiate(IoStream::plain(socket), &config).await {
                Ok(session) => {
                    assert!(case.expect_ok);
                    assert_eq!(
                        session.max_message_size_exponent,
                        case.expect_exponent.unwrap()
                    );
                    assert_eq!(session.upgraded, case.expect_upgrade);
                    drop(session);
                    let mut response = Vec::new();
                    time::timeout(Duration::from_secs(1), peer.read_to_end(&mut response))
                        .await
                        .unwrap()
                        .unwrap();
                    let base = case.handshake_exponent.min(case.endpoint_exponent).min(24);
                    let mut expected = vec![0x7f, ((base - 9) as u8) << 4 | 1, 0, 0];
                    if case.expect_upgrade {
                        expected.extend([0x3f, (case.expect_exponent.unwrap() - 25) as u8]);
                    }
                    assert_eq!(response, expected, "complete handshake response");
                }
                Err(_) => {
                    assert!(!case.expect_ok);
                }
            }
        }
    }

    #[tokio::test]
    async fn server_does_not_probe_when_upgrade_is_ineligible() {
        for endpoint in [9, 16, 24, 30] {
            for requested in [9, 16, 24] {
                if endpoint > 24 && requested == 24 {
                    continue;
                }
                let (socket, mut peer) = socket_pair().await;
                let request = [0x7f, ((requested - 9) as u8) << 4 | 1, 0, 0];
                peer.write_all(&request).await.unwrap();
                peer.shutdown().await.unwrap();
                let config = runtime_config(Some(Duration::from_millis(100)), endpoint);
                let result = negotiate(IoStream::plain(socket), &config).await;
                assert!(result.is_ok());
                let session = result.unwrap();
                assert!(!session.upgraded);
                assert_eq!(session.max_message_size_exponent, requested.min(endpoint));
                drop(session);
                let mut response = Vec::new();
                time::timeout(Duration::from_secs(1), peer.read_to_end(&mut response))
                    .await
                    .unwrap()
                    .unwrap();
                assert_eq!(
                    response,
                    [0x7f, ((requested.min(endpoint) - 9) as u8) << 4 | 1, 0, 0]
                );
            }
        }
    }

    #[tokio::test]
    async fn negotiate_times_out_when_client_silent() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(50)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(IoStream::plain(stream), &config).await;
            tx.send(result).ok();
        });

        let _client = TcpStream::connect(addr).await.unwrap();
        let result = rx.await.unwrap();
        assert!(matches!(
            result,
            Err(HandshakeError::Protocol("rawsocket handshake timed out"))
        ));
    }

    async fn socket_pair() -> (TcpStream, TcpStream) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap())
            .await
            .unwrap();
        let (peer, _) = listener.accept().await.unwrap();
        (client, peer)
    }

    #[tokio::test]
    async fn client_handshake_serializer_and_exponent_wire_matrix() {
        for (serializer, wire_id) in [
            (Serializer::Json, 1),
            (Serializer::MessagePack, 2),
            (Serializer::Cbor, 3),
            (Serializer::Ubjson, 4),
            (Serializer::Flatbuffers, 5),
        ] {
            for exponent in 9..=24 {
                let (client, mut peer) = socket_pair().await;
                let expected = [0x7f, ((exponent - 9) as u8) << 4 | wire_id, 0, 0];
                peer.write_all(&expected).await.unwrap();
                peer.write_all(b"next-frame").await.unwrap();
                peer.shutdown().await.unwrap();
                time::timeout(Duration::from_secs(3), async {
                    let mut session = successful_handshake(
                        connect(
                            IoStream::plain(client),
                            serializer,
                            exponent,
                            Duration::from_secs(1),
                        )
                        .await,
                    );
                    assert_eq!(session.serializer, serializer);
                    assert_eq!(session.max_message_size_exponent, exponent);
                    assert!(!session.upgraded);
                    assert_eq!(
                        session.file_sender.is_some(),
                        cfg!(any(target_os = "linux", target_os = "macos"))
                            && (wire_id == 2 || wire_id == 3)
                    );
                    assert_complete_wire(&mut session.reader, b"next-frame").await;
                    session.writer.write_all(b"reply").await.unwrap();
                    session.writer.shutdown().await.unwrap();
                    let mut request_and_reply = expected.to_vec();
                    request_and_reply.extend_from_slice(b"reply");
                    assert_complete_wire(peer, &request_and_reply).await;
                })
                .await
                .unwrap();
            }
        }
    }

    #[tokio::test]
    async fn client_rejects_invalid_response_fields_independently() {
        for (response, expected) in [
            ([0, 1, 0, 0], "invalid rawsocket response magic"),
            ([0x7f, 1, 1, 0], "rawsocket reserved bits must be zero"),
            ([0x7f, 1, 0, 1], "rawsocket reserved bits must be zero"),
            ([0x7f, 0x10, 0, 0], "rawsocket serializer unsupported"),
            ([0x7f, 0x20, 0, 0], "rawsocket message length exceeded"),
            ([0x7f, 0x30, 0, 0], "rawsocket reserved bits error"),
            ([0x7f, 0x40, 0, 0], "rawsocket handshake failed"),
            ([0x7f, 6, 0, 0], "rawsocket serializer response invalid"),
            ([0x7f, 2, 0, 0], "rawsocket serializer mismatch"),
        ] {
            let (client, mut peer) = socket_pair().await;
            peer.write_all(&response).await.unwrap();
            let result = time::timeout(
                Duration::from_secs(2),
                connect(
                    IoStream::plain(client),
                    Serializer::Json,
                    16,
                    Duration::from_millis(100),
                ),
            )
            .await
            .unwrap();
            assert!(
                matches!(result, Err(HandshakeError::Protocol(message)) if message == expected)
            );
        }
    }

    #[tokio::test]
    async fn server_rejects_invalid_magic_and_each_reserved_byte() {
        for (request, message) in [
            ([0, 1, 0, 0], "invalid rawsocket magic"),
            ([0x7f, 1, 1, 0], "reserved bits must be zero"),
            ([0x7f, 1, 0, 1], "reserved bits must be zero"),
        ] {
            let (client, mut peer) = socket_pair().await;
            peer.write_all(&request).await.unwrap();
            let config = runtime_config(Some(Duration::from_millis(100)), 16);
            let result = negotiate(IoStream::plain(client), &config).await;
            assert!(matches!(result, Err(HandshakeError::Protocol(actual)) if actual == message));
            let mut response = Vec::new();
            time::timeout(Duration::from_secs(1), peer.read_to_end(&mut response))
                .await
                .unwrap()
                .unwrap();
            assert_eq!(response, [0x7f, 0x30, 0, 0]);
        }
    }

    #[tokio::test]
    async fn client_upgrade_and_server_clamping_are_negotiated_independently() {
        for (requested, returned, upgrade) in [(40, 30, true), (26, 25, true), (30, 16, false)] {
            let (client, mut peer) = socket_pair().await;
            let server = async {
                assert_complete_wire((&mut peer).take(4), &[0x7f, 0xf2, 0, 0]).await;
                peer.write_all(&[0x7f, if upgrade { 0xf2 } else { 0x72 }, 0, 0])
                    .await
                    .unwrap();
                if upgrade {
                    assert_complete_wire(
                        (&mut peer).take(2),
                        &[
                            0x3f,
                            (requested.min(crate::config::CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT)
                                - 25) as u8,
                        ],
                    )
                    .await;
                    peer.write_all(&[0x3f, (returned - 25) as u8])
                        .await
                        .unwrap();
                }
            };
            let client = async {
                let session = successful_handshake(
                    connect(
                        IoStream::plain(client),
                        Serializer::MessagePack,
                        requested,
                        Duration::from_secs(1),
                    )
                    .await,
                );
                assert_eq!(session.max_message_size_exponent, returned);
                assert_eq!(session.upgraded, upgrade);
            };
            time::timeout(Duration::from_secs(3), async {
                tokio::join!(server, client);
            })
            .await
            .unwrap();
            assert_complete_wire(peer, &[]).await;
        }
    }

    #[tokio::test]
    async fn client_handshake_timeout_and_truncation_fail_closed() {
        let (client, _silent) = socket_pair().await;
        let result = connect(
            IoStream::plain(client),
            Serializer::Json,
            16,
            Duration::from_millis(10),
        )
        .await;
        assert!(matches!(
            result,
            Err(HandshakeError::Protocol("rawsocket handshake timed out"))
        ));
        let (client, mut peer) = socket_pair().await;
        peer.write_all(&[0x7f, 1]).await.unwrap();
        peer.shutdown().await.unwrap();
        let result = connect(
            IoStream::plain(client),
            Serializer::Json,
            16,
            Duration::from_secs(1),
        )
        .await;
        assert!(
            matches!(result, Err(HandshakeError::Io(ref io)) if io.kind() == io::ErrorKind::UnexpectedEof)
        );
    }

    #[tokio::test]
    async fn client_upgrade_rejects_invalid_magic_and_truncated_response() {
        for response in [vec![0, 0], vec![0x3f]] {
            let (client, mut peer) = socket_pair().await;
            let server = async {
                assert_complete_wire((&mut peer).take(4), &[0x7f, 0xf1, 0, 0]).await;
                peer.write_all(&[0x7f, 0xf1, 0, 0]).await.unwrap();
                assert_complete_wire((&mut peer).take(2), &[0x3f, 1]).await;
                peer.write_all(&response).await.unwrap();
                peer.shutdown().await.unwrap();
            };
            let client = async {
                let result = connect(
                    IoStream::plain(client),
                    Serializer::Json,
                    26,
                    Duration::from_secs(1),
                )
                .await;
                if response.len() == 2 {
                    assert!(matches!(
                        result,
                        Err(HandshakeError::Protocol(
                            "invalid rawsocket upgrade response"
                        ))
                    ));
                } else {
                    assert!(
                        matches!(result, Err(HandshakeError::Io(ref io)) if io.kind() == io::ErrorKind::UnexpectedEof)
                    );
                }
            };
            time::timeout(Duration::from_secs(3), async {
                tokio::join!(server, client);
            })
            .await
            .unwrap();
            assert_complete_wire(peer, &[]).await;
        }
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[tokio::test]
    async fn file_sender_transfers_the_requested_file_range() {
        use std::io::{Seek, SeekFrom};
        use std::sync::Arc;
        use std::time::{SystemTime, UNIX_EPOCH};

        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "connectanum-sendfile-{}-{nonce}.bin",
            std::process::id()
        ));
        std::fs::write(&path, b"0123456789abcdef").unwrap();
        let file = Arc::new(File::open(&path).unwrap());
        std::fs::remove_file(path).unwrap();

        for (offset, length, expected, expected_error) in [
            (u64::MAX, 0, b"".as_slice(), None),
            (
                u64::MAX,
                1,
                b"".as_slice(),
                Some(io::ErrorKind::InvalidInput),
            ),
            (3, 8, b"3456789a".as_slice(), None),
            (14, 8, b"ef".as_slice(), Some(io::ErrorKind::UnexpectedEof)),
            (16, 1, b"".as_slice(), Some(io::ErrorKind::UnexpectedEof)),
            (16, 0, b"".as_slice(), None),
            (0, 16, b"0123456789abcdef".as_slice(), None),
        ] {
            let (client, peer) = socket_pair().await;
            let mut stream = IoStream::plain(client);
            let sender = RawSocketFileSender::from_stream(&stream);
            assert!(matches!(sender, Ok(Some(_))));
            let sender = sender.unwrap().unwrap();
            assert_eq!(format!("{sender:?}"), "RawSocketFileSender { .. }");
            let before = crate::file_segment_metrics_snapshot();
            let result = time::timeout(
                Duration::from_secs(2),
                sender.send_file_segment(&file, offset, length),
            )
            .await
            .unwrap();
            // shutdown applies to the socket, including the sender's duplicated
            // descriptor. EOF makes a missing payload observable without a hang.
            stream.shutdown().await.unwrap();
            let mut received = Vec::new();
            time::timeout(
                Duration::from_secs(2),
                peer.take(expected.len() as u64 + 1)
                    .read_to_end(&mut received),
            )
            .await
            .unwrap()
            .unwrap();
            assert_eq!(
                result.as_ref().err().map(io::Error::kind),
                expected_error,
                "offset {offset}, length {length}: {result:?}"
            );
            assert_eq!(received, expected, "offset {offset}, length {length}");
            if !expected.is_empty() {
                let after = crate::file_segment_metrics_snapshot();
                assert!(
                    after.rawsocket_zero_copy_calls_total
                        >= before.rawsocket_zero_copy_calls_total + 1
                );
                assert!(
                    after.rawsocket_zero_copy_bytes_total
                        >= before.rawsocket_zero_copy_bytes_total + expected.len() as u64
                );
            }
        }

        // Explicit offsets must neither move the shared file cursor nor require
        // switching away from the session's ordinary socket writer.
        let mut cursor = file.as_ref();
        cursor.seek(SeekFrom::Start(7)).unwrap();
        let (client, peer) = socket_pair().await;
        let mut stream = IoStream::plain(client);
        let sender = RawSocketFileSender::from_stream(&stream);
        assert!(matches!(sender, Ok(Some(_))));
        let sender = sender.unwrap().unwrap();
        time::timeout(Duration::from_secs(2), async {
            stream.write_all(b"prefix:").await.unwrap();
            let first = sender.send_file_segment(&file, 3, 4).await;
            assert!(first.is_ok());
            stream.write_all(b":").await.unwrap();
            let second = sender.send_file_segment(&file, 10, 3).await;
            assert!(second.is_ok());
            stream.write_all(b":suffix").await.unwrap();
            stream.shutdown().await.unwrap();
        })
        .await
        .unwrap();
        assert_complete_wire(peer, b"prefix:3456:abc:suffix").await;
        assert_eq!(cursor.stream_position().unwrap(), 7);
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[tokio::test]
    async fn file_sender_preserves_offsets_under_backpressure() {
        let (client, peer) = socket_pair().await;
        let mut stream = IoStream::plain(client);
        let sender = RawSocketFileSender::from_stream(&stream);
        assert!(matches!(sender, Ok(Some(_))));
        let sender = sender.unwrap().unwrap();
        let small_buffer: libc::c_int = 4096;
        let status = unsafe {
            libc::setsockopt(
                sender.socket.get_ref().as_raw_fd(),
                libc::SOL_SOCKET,
                libc::SO_SNDBUF,
                (&small_buffer as *const libc::c_int).cast(),
                std::mem::size_of_val(&small_buffer) as libc::socklen_t,
            )
        };
        assert_eq!(status, 0);
        let bytes: Vec<u8> = (0..1024 * 1024 + 73)
            .map(|i| ((i * 17 + i / 251) % 256) as u8)
            .collect();
        let path = std::env::temp_dir().join(format!(
            "connectanum-backpressure-{}-{}.bin",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&path, &bytes).unwrap();
        let file = Arc::new(File::open(&path).unwrap());
        std::fs::remove_file(path).unwrap();
        let expected = &bytes[31..bytes.len() - 19];
        let send = async {
            let result = sender.send_file_segment(&file, 31, expected.len()).await;
            stream.shutdown().await.unwrap();
            result
        };
        let receive = async move {
            time::sleep(Duration::from_millis(20)).await;
            let mut received = Vec::new();
            peer.take(expected.len() as u64 + 1)
                .read_to_end(&mut received)
                .await
                .unwrap();
            received
        };
        let (sent, received) = time::timeout(Duration::from_secs(5), async {
            tokio::join!(send, receive)
        })
        .await
        .expect("file segment must complete with a slow reader");
        assert!(sent.is_ok());
        assert_eq!(received, expected);
    }
}
