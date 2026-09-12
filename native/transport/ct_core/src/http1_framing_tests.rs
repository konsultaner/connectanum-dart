use super::*;
use crate::{
    config::{HttpRouteMatchKind, HttpRouteRuntime, HttpRouteTarget},
    serve_http_connection, ConnectionId, HttpResponseBody, HttpResponseDispatch, ListenerId,
    ListenerRegistry,
};
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::{TlsAcceptor, TlsConnector};

const INNER_REQUEST: &[u8] = b"GET /inside-body HTTP/1.1\r\nHost: localhost\r\n\r\n";
// gzip level 0, mtime 0: one stored DEFLATE block, CRC32 and original size.
// Independently round-tripped with Python's gzip.decompress in the audit probe.
const GZIP_BODY: &[u8] = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x04\xff\x01\x2e\x00\xd1\xffGET /inside-body HTTP/1.1\r\nHost: localhost\r\n\r\n\xc7\xd2\x68\x6f\x2e\x00\x00\x00";

macro_rules! rejects_framing {
    ($name:ident, $version:literal, $headers:expr, $status:literal) => {
        #[tokio::test]
        async fn $name() {
            let config = super::tests::runtime_config(Some(Duration::from_secs(1)), 16);
            let bytes = format!(
                "POST / HTTP/1.{}\r\nHost: localhost\r\n{}\r\nabcdefgh",
                $version, $headers
            );
            let mut reader = BufReader::new(bytes.as_bytes());
            let err = read_http_request(&mut reader, &config).await.unwrap_err();
            let NegotiationError::Protocol(detail) = err else {
                panic!("framing must be rejected before waiting for a body: {err:?}");
            };
            assert_eq!(
                classify_http_error_status(&detail),
                Some($status),
                "{detail}"
            );
        }
    };
}

rejects_framing!(
    transfer_list,
    1,
    "Transfer-Encoding: gzip, chunked\r\n",
    501
);
rejects_framing!(
    transfer_split_fields,
    1,
    "Transfer-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n",
    501
);
rejects_framing!(
    transfer_chunked_control,
    1,
    "Transfer-Encoding: ChUnKeD\r\n",
    501
);
rejects_framing!(transfer_empty, 1, "Transfer-Encoding:\r\n", 400);
rejects_framing!(
    transfer_list_empty_members,
    1,
    "Transfer-Encoding: , gzip, , chunked,\r\n",
    501
);
rejects_framing!(
    transfer_split_trailing_empty_member,
    1,
    "Transfer-Encoding: chunked\r\nTransfer-Encoding: ,\r\n",
    501
);
rejects_framing!(
    transfer_not_final_chunked,
    1,
    "Transfer-Encoding: chunked, gzip\r\n",
    400
);
rejects_framing!(transfer_unknown, 1, "Transfer-Encoding: identity\r\n", 400);
rejects_framing!(
    transfer_repeated_chunked,
    1,
    "Transfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n",
    400
);
rejects_framing!(
    transfer_chunked_parameter,
    1,
    "Transfer-Encoding: chunked; q=1\r\n",
    400
);
rejects_framing!(transfer_http10, 0, "Transfer-Encoding: chunked\r\n", 400);
rejects_framing!(
    transfer_and_length,
    1,
    "Transfer-Encoding: gzip, chunked\r\nContent-Length: 0\r\n",
    400
);
rejects_framing!(
    length_and_transfer,
    1,
    "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n",
    400
);
rejects_framing!(length_plus_sign, 1, "Content-Length: +4\r\n", 400);
rejects_framing!(
    length_form_feed_whitespace,
    1,
    "Content-Length: \u{000c}4\u{000c}\r\n",
    400
);
rejects_framing!(
    length_unicode_space,
    1,
    "Content-Length: \u{a0}4\u{a0}\r\n",
    400
);
rejects_framing!(
    length_overflow_control,
    1,
    "Content-Length: 18446744073709551616\r\n",
    400
);
rejects_framing!(
    length_conflict_control,
    1,
    "Content-Length: 0\r\nContent-Length: 4\r\n",
    400
);
rejects_framing!(length_negative_control, 1, "Content-Length: -4\r\n", 400);
rejects_framing!(
    length_comma_joined_duplicate,
    1,
    "Content-Length: 4, 4\r\n",
    400
);

#[tokio::test]
async fn transfer_rejected_before_waiting_for_a_declared_body() {
    time::timeout(Duration::from_millis(250), async {
        let config = super::tests::runtime_config(Some(Duration::from_secs(2)), 16);
        let (mut client, server) = tokio::io::duplex(256);
        client.write_all(b"POST / HTTP/1.1\r\nTransfer-Encoding: gzip, chunked\r\nContent-Length: 1000\r\n\r\n").await.unwrap();
        let mut reader = BufReader::new(server);
        let err = read_http_request(&mut reader, &config).await.unwrap_err();
        assert!(matches!(err, NegotiationError::Protocol(_)));
        drop(client);
    })
    .await
    .expect("header rejection must not wait for an attacker-controlled body");
}

#[tokio::test]
async fn valid_lengths_preserve_body_and_next_request() {
    for headers in [
        "Content-Length: 4\r\n",
        "Content-Length: \t004 \t\r\n",
        "Content-Length: 4\r\nContent-Length: 04\r\n",
    ] {
        let config = super::tests::runtime_config(Some(Duration::from_secs(1)), 16);
        let bytes = format!("POST /outer HTTP/1.1\r\n{headers}\r\nbodyGET /next HTTP/1.1\r\n\r\n");
        let mut reader = BufReader::new(bytes.as_bytes());
        let (request, body) = read_http_request(&mut reader, &config)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(request.target, "/outer");
        assert!(matches!(body, HttpBodyPhase::Buffered(b) if b.as_ref() == b"body"));
        let (request, body) = read_http_request(&mut reader, &config)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(request.target, "/next");
        assert!(matches!(body, HttpBodyPhase::Buffered(b) if b.is_empty()));
    }
}

#[tokio::test]
async fn content_encoding_preserves_opaque_body_and_next_request() {
    let config = super::tests::runtime_config(Some(Duration::from_secs(1)), 16);
    let mut bytes = format!(
        "POST /compressed HTTP/1.1\r\nContent-Encoding: gzip\r\nContent-Length: {}\r\n\r\n",
        GZIP_BODY.len()
    )
    .into_bytes();
    bytes.extend_from_slice(GZIP_BODY);
    bytes.extend_from_slice(b"GET /next HTTP/1.1\r\n\r\n");

    let mut reader = BufReader::new(bytes.as_slice());
    let (request, body) = read_http_request(&mut reader, &config)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(request.target, "/compressed");
    assert!(matches!(body, HttpBodyPhase::Buffered(b) if b.as_ref() == GZIP_BODY));

    let (request, body) = read_http_request(&mut reader, &config)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(request.target, "/next");
    assert!(matches!(body, HttpBodyPhase::Buffered(b) if b.is_empty()));
}

fn smuggling_request() -> Vec<u8> {
    assert_eq!(GZIP_BODY.len(), 69);
    assert_eq!(&GZIP_BODY[15..61], INNER_REQUEST);
    let chunk_header = format!("{:x}\r\n", GZIP_BODY.len());
    // A TE-aware recipient sees one gzip body; a CL-first recipient stops at
    // the first stored-block byte and sees the embedded request as a new one.
    let false_length = chunk_header.len() + 15;
    let mut bytes = format!("POST /outer HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: gzip, chunked\r\nContent-Length: {false_length}\r\n\r\n{chunk_header}").into_bytes();
    bytes.extend_from_slice(GZIP_BODY);
    bytes.extend_from_slice(b"\r\n0\r\n\r\n");
    bytes
}

async fn exercise_live(bytes: Vec<u8>, tls: bool) -> (String, Vec<String>) {
    time::timeout(Duration::from_secs(5), async move {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let server_config = rustls::ServerConfig::builder_with_provider(provider.clone())
            .with_safe_default_protocol_versions().unwrap().with_no_client_auth()
            .with_single_cert(vec![identity.cert.der().clone()], rustls::pki_types::PrivatePkcs8KeyDer::from(identity.key_pair.serialize_der()).into()).unwrap();
        let mut roots = rustls::RootCertStore::empty();
        roots.add(identity.cert.der().clone()).unwrap();
        let client_config = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions().unwrap().with_root_certificates(roots).with_no_client_auth();
        let server = tokio::spawn(async move {
            let (stream, peer) = listener.accept().await.unwrap();
            let stream = if tls {
                IoStream::tls(TlsAcceptor::from(Arc::new(server_config)).accept(stream).await.unwrap())
            } else { IoStream::plain(stream) };
            let mut config = super::tests::runtime_config(Some(Duration::from_secs(1)), 16);
            config.http_routes.push(HttpRouteRuntime {
                path: "/".into(), match_kind: HttpRouteMatchKind::Prefix, protocols: vec![],
                transport_auth: Default::default(), methods: Default::default(),
                default: Some(HttpRouteTarget::Translation { realm: "test".into(), procedure: "test.echo".into() }),
            });
            let config = Arc::new(config);
            let registry = Arc::new(ListenerRegistry::default());
            registry.register_http_connection(ListenerId(1), ConnectionId(1), config.clone(), peer);
            let serving = async {
                match negotiate_connection(stream, &config).await {
                    Ok(NegotiatedConnection::Http(handshake)) => serve_http_connection(ListenerId(1), ConnectionId(1), handshake, config.clone(), registry.clone()).await,
                    Err(NegotiationError::Protocol(_)) => {},
                    other => panic!("unexpected negotiation: {other:?}"),
                }
            };
            tokio::pin!(serving);
            let mut dispatched = Vec::new();
            loop {
                tokio::select! {
                    _ = &mut serving => break,
                    _ = time::sleep(Duration::from_millis(1)) => {
                        while let Some((request, response)) = registry.poll_http_request(ConnectionId(1)).unwrap() {
                            dispatched.push(String::from_utf8(request.target.to_vec()).unwrap());
                            response.respond(HttpResponseDispatch { status: 200, headers: vec![], body: HttpResponseBody::Buffered(b"ok".to_vec()) }).unwrap();
                        }
                    }
                }
            }
            dispatched
        });
        let stream = TcpStream::connect(address).await.unwrap();
        let mut client = if tls {
            IoStream::tls_client(TlsConnector::from(Arc::new(client_config)).connect("localhost".try_into().unwrap(), stream).await.unwrap())
        } else { IoStream::plain(stream) };
        client.write_all(&bytes).await.unwrap();
        client.shutdown().await.unwrap();
        let mut wire = Vec::new();
        let closed = client.read_to_end(&mut wire).await;
        // The legacy connection loop can close TLS without close_notify.
        // Exact HTTP response/status and dispatch counts are checked separately.
        if let Err(err) = closed { assert_eq!(err.kind(), io::ErrorKind::UnexpectedEof); }
        (String::from_utf8(wire).unwrap(), server.await.unwrap())
    }).await.expect("bounded native HTTP/1 framing test")
}

async fn assert_hidden_request_rejected(tls: bool, keepalive: bool) {
    let mut bytes = Vec::new();
    if keepalive {
        bytes.extend_from_slice(b"GET /valid HTTP/1.1\r\nHost: localhost\r\n\r\n");
    }
    bytes.extend(smuggling_request());
    let (wire, dispatched) = exercise_live(bytes, tls).await;
    let expected = if keepalive { vec!["/valid"] } else { vec![] };
    assert_eq!(
        dispatched, expected,
        "request body must never become an application dispatch; wire={wire:?}"
    );
    assert_eq!(wire.matches("HTTP/1.1 400").count(), 1, "{wire}");
    assert_eq!(wire.matches("HTTP/1.1 200").count(), usize::from(keepalive));
    assert!(wire.contains("Connection: close"));
}

#[tokio::test]
async fn live_tcp_rejects_hidden_request_on_first_message() {
    assert_hidden_request_rejected(false, false).await;
}
#[tokio::test]
async fn live_tcp_rejects_hidden_request_after_keepalive() {
    assert_hidden_request_rejected(false, true).await;
}
#[tokio::test]
async fn live_tls_rejects_hidden_request_on_first_message() {
    assert_hidden_request_rejected(true, false).await;
}
#[tokio::test]
async fn live_tls_rejects_hidden_request_after_keepalive() {
    assert_hidden_request_rejected(true, true).await;
}

#[tokio::test]
async fn live_valid_pipelining_preserves_both_dispatches() {
    for tls in [false, true] {
        let (wire, dispatched) = exercise_live(b"POST /first HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nbodyGET /second HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".to_vec(), tls).await;
        assert_eq!(dispatched, ["/first", "/second"]);
        assert_eq!(wire.matches("HTTP/1.1 200").count(), 2);
    }
}

#[tokio::test]
async fn live_unconsumed_streaming_body_is_drained_before_next_request() {
    let mut body = vec![b'x'; HTTP1_INLINE_BODY_LIMIT + 1024];
    body[..INNER_REQUEST.len()].copy_from_slice(INNER_REQUEST);
    let mut bytes = format!(
        "POST /streamed HTTP/1.1\r\nHost: localhost\r\nContent-Length: {}\r\n\r\n",
        body.len()
    )
    .into_bytes();
    bytes.extend_from_slice(&body);
    bytes.extend_from_slice(b"GET /next HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");

    for tls in [false, true] {
        let (wire, dispatched) = exercise_live(bytes.clone(), tls).await;
        assert_eq!(dispatched, ["/streamed", "/next"], "wire={wire:?}");
        assert_eq!(wire.matches("HTTP/1.1 200").count(), 2, "{wire}");
    }
}
