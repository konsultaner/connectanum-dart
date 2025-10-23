use std::io;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::time;

use crate::config::EndpointRuntimeConfig;

const RAWSOCKET_MAGIC: u8 = 0x7F;
const RAWSOCKET_UPGRADE_MAGIC: u8 = 0x3F;

const SERIALIZER_JSON: u8 = 0x01;
const SERIALIZER_MSGPACK: u8 = 0x02;
const SERIALIZER_CBOR: u8 = 0x03;
const SERIALIZER_UBJSON: u8 = 0x04;
const SERIALIZER_FLATBUFFERS: u8 = 0x05;

const ERROR_SERIALIZER_UNSUPPORTED: u8 = 1;
const ERROR_MESSAGE_LENGTH_EXCEEDED: u8 = 2;
const ERROR_RESERVED_BITS: u8 = 3;

const HTTP_PROBE_RESPONSE: &[u8] =
    b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";

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
    pub reader: OwnedReadHalf,
    pub writer: OwnedWriteHalf,
    pub serializer: Serializer,
    pub max_message_size_exponent: u32,
    #[allow(dead_code)]
    pub upgraded: bool,
}

#[derive(Debug)]
pub enum HandshakeError {
    HttpProbe,
    Protocol(&'static str),
    Io(io::Error),
}

impl From<io::Error> for HandshakeError {
    fn from(err: io::Error) -> Self {
        HandshakeError::Io(err)
    }
}

pub async fn negotiate(
    mut stream: TcpStream,
    endpoint: &EndpointRuntimeConfig,
) -> Result<NegotiatedSession, HandshakeError> {
    let mut buf = [0u8; 4];
    read_with_timeout(&mut stream, &mut buf, endpoint.handshake_timeout).await?;

    if looks_like_http(&buf) {
        respond_http_probe(&mut stream).await?;
        return Err(HandshakeError::HttpProbe);
    }

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
        match time::timeout(endpoint.handshake_timeout, async {
            let mut buf = [0u8; 2];
            match stream.read_exact(&mut buf).await {
                Ok(_) => Ok(buf),
                Err(err) => Err(err),
            }
        })
        .await
        {
            Ok(Ok(buf)) if buf[0] == RAWSOCKET_UPGRADE_MAGIC => {
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
            Ok(Ok(_buf)) => {
                send_error(&mut stream, ERROR_RESERVED_BITS).await?;
                return Err(HandshakeError::Protocol("unexpected data during upgrade"));
            }
            Ok(Err(err)) => return Err(HandshakeError::Io(err)),
            Err(_) => {
                // No upgrade request within the timeout; continue with base exponent.
            }
        }
    }

    let (reader, writer) = stream.into_split();

    Ok(NegotiatedSession {
        reader,
        writer,
        serializer,
        max_message_size_exponent: final_exponent,
        upgraded,
    })
}

async fn read_with_timeout(
    stream: &mut TcpStream,
    buf: &mut [u8],
    timeout: Duration,
) -> Result<(), HandshakeError> {
    time::timeout(timeout, stream.read_exact(buf))
        .await
        .map_err(|_| HandshakeError::Protocol("rawsocket handshake timed out"))??;
    Ok(())
}

async fn respond_http_probe(stream: &mut TcpStream) -> io::Result<()> {
    stream.write_all(HTTP_PROBE_RESPONSE).await?;
    let _ = stream.shutdown().await;
    Ok(())
}

async fn send_error(stream: &mut TcpStream, code: u8) -> io::Result<()> {
    let frame = [RAWSOCKET_MAGIC, code << 4, 0, 0];
    stream.write_all(&frame).await?;
    let _ = stream.shutdown().await;
    Ok(())
}

fn looks_like_http(buf: &[u8; 4]) -> bool {
    matches!(
        buf,
        b"GET " | b"POST" | b"HEAD" | b"PUT " | b"DELE" | b"OPTI" | b"PATC" | b"HTTP" | b"PRI "
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{EndpointConfig, EndpointRuntimeConfig, TlsMode};
    use tokio::{net::TcpListener, sync::oneshot};

    fn runtime_config(
        handshake_timeout: Option<Duration>,
        rawsocket_exponent: u32,
    ) -> EndpointRuntimeConfig {
        let endpoint = EndpointConfig {
            host: "127.0.0.1".into(),
            port: 0,
            tls_mode: TlsMode::Native,
            idle_timeout: None,
            handshake_timeout,
            max_http_content_length: None,
            max_rawsocket_size_exponent: Some(rawsocket_exponent),
            websocket_path: None,
            sni_certificates: Vec::new(),
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

    #[tokio::test]
    async fn negotiate_success_returns_session() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(500)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(stream, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        send_handshake(&mut client, 16).await;
        let mut response = [0u8; 4];
        client.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], RAWSOCKET_MAGIC);

        let session = rx.await.unwrap().expect("handshake succeeds");
        assert_eq!(session.max_message_size_exponent, 16);
        assert_eq!(session.serializer, Serializer::Json);
        assert!(!session.upgraded);
    }

    #[tokio::test]
    async fn negotiate_clamps_to_endpoint_exponent() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 12);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(stream, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        send_handshake(&mut client, 24).await;
        let mut response = [0u8; 4];
        client.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], RAWSOCKET_MAGIC);

        let session = rx.await.unwrap().expect("handshake succeeds");
        assert_eq!(session.max_message_size_exponent, 12);
        assert!(!session.upgraded);
    }

    #[tokio::test]
    async fn negotiate_performs_upgrade() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 30);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(stream, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        send_handshake(&mut client, 24).await;
        let mut response = [0u8; 4];
        client.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], RAWSOCKET_MAGIC);

        send_upgrade(&mut client, 30).await;
        let mut upgrade_resp = [0u8; 2];
        client.read_exact(&mut upgrade_resp).await.unwrap();
        assert_eq!(upgrade_resp[0], RAWSOCKET_UPGRADE_MAGIC);

        let session = rx.await.unwrap().expect("upgrade succeeds");
        assert_eq!(session.max_message_size_exponent, 30);
        assert!(session.upgraded);
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
            let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
            let addr = listener.local_addr().unwrap();
            let config = runtime_config(Some(Duration::from_millis(200)), 16);
            let (tx, rx) = oneshot::channel();

            tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                let result = negotiate(stream, &config).await;
                tx.send(result).ok();
            });

            let mut client = TcpStream::connect(addr).await.unwrap();
            send_handshake_with_serializer(&mut client, 16, serializer_byte).await;
            let mut response = [0u8; 4];
            client
                .read_exact(&mut response)
                .await
                .expect("handshake response");
            assert_eq!(response[0], RAWSOCKET_MAGIC);

            let session = rx.await.unwrap().expect("handshake succeeds");
            assert_eq!(session.serializer, expected_variant);
        }
    }

    #[tokio::test]
    async fn negotiate_rejects_unsupported_serializer() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(200)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(stream, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        send_handshake_with_serializer(&mut client, 16, 0x06).await;
        let mut response = [0u8; 4];
        client.read_exact(&mut response).await.expect("error frame");
        assert_eq!(response[0], RAWSOCKET_MAGIC);
        assert_eq!(response[1] >> 4, ERROR_SERIALIZER_UNSUPPORTED);

        let err = rx.await.unwrap().expect_err("serializer unsupported");
        assert!(matches!(err, HandshakeError::Protocol(_)));
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
            let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
            let addr = listener.local_addr().unwrap();
            let config = runtime_config(Some(Duration::from_millis(200)), case.endpoint_exponent);
            let (tx, rx) = oneshot::channel();

            tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                let result = negotiate(stream, &config).await;
                tx.send(result).ok();
            });

            let mut client = TcpStream::connect(addr).await.unwrap();
            send_handshake(&mut client, case.handshake_exponent).await;

            let mut handshake_resp = [0u8; 4];
            let handshake_ok = client.read_exact(&mut handshake_resp).await.is_ok();

            let mut upgrade_resp = [0u8; 2];
            let mut upgrade_ok = false;
            if let Some(req) = case.upgrade_request {
                send_upgrade(&mut client, req).await;
                upgrade_ok = client.read_exact(&mut upgrade_resp).await.is_ok();
            }

            match rx.await.unwrap() {
                Ok(session) => {
                    assert!(case.expect_ok, "case should have failed");
                    assert!(handshake_ok);
                    assert_eq!(handshake_resp[0], RAWSOCKET_MAGIC);
                    assert_eq!(
                        session.max_message_size_exponent,
                        case.expect_exponent.unwrap()
                    );
                    assert_eq!(session.upgraded, case.expect_upgrade);
                    if case.expect_upgrade {
                        assert!(upgrade_ok);
                        assert_eq!(upgrade_resp[0], RAWSOCKET_UPGRADE_MAGIC);
                    }
                }
                Err(_) => {
                    assert!(!case.expect_ok, "case should have succeeded");
                }
            }
        }
    }

    #[tokio::test]
    async fn negotiate_detects_http_probe() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_secs(1)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(stream, &config).await;
            tx.send(result).ok();
        });

        let mut client = TcpStream::connect(addr).await.unwrap();
        client.write_all(b"GET / HTTP/1.1").await.unwrap();
        let mut buf = Vec::new();
        client.read_to_end(&mut buf).await.unwrap();
        assert!(std::str::from_utf8(&buf)
            .unwrap()
            .starts_with("HTTP/1.1 400"));

        let err = rx.await.unwrap().expect_err("http probe");
        assert!(matches!(err, HandshakeError::HttpProbe));
    }

    #[tokio::test]
    async fn negotiate_times_out_when_client_silent() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(50)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(stream, &config).await;
            tx.send(result).ok();
        });

        let _client = TcpStream::connect(addr).await.unwrap();
        let err = rx.await.unwrap().expect_err("handshake timeout");
        assert!(matches!(err, HandshakeError::Protocol(_)));
    }
}
