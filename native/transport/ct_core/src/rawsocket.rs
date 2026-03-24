use std::io;
use std::time::Duration;

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
    pub serializer: Serializer,
    pub max_message_size_exponent: u32,
    #[allow(dead_code)]
    pub upgraded: bool,
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

    let (reader, writer) = tokio::io::split(stream);

    Ok(NegotiatedSession {
        reader,
        writer,
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
    let (reader, writer) = tokio::io::split(stream);
    Ok(NegotiatedSession {
        reader,
        writer,
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

    #[tokio::test]
    async fn negotiate_success_returns_session() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let config = runtime_config(Some(Duration::from_millis(500)), 16);
        let (tx, rx) = oneshot::channel();

        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let result = negotiate(IoStream::plain(stream), &config).await;
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
            let result = negotiate(IoStream::plain(stream), &config).await;
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
            let result = negotiate(IoStream::plain(stream), &config).await;
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
                let result = negotiate(IoStream::plain(stream), &config).await;
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
            let result = negotiate(IoStream::plain(stream), &config).await;
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
                let result = negotiate(IoStream::plain(stream), &config).await;
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
        let err = rx.await.unwrap().expect_err("handshake timeout");
        assert!(matches!(err, HandshakeError::Protocol(_)));
    }
}
