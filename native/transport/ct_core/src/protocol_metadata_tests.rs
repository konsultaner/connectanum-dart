use super::*;
use tokio::net::{TcpListener, TcpStream};

#[test]
fn request_target_preserves_query_boundaries_without_decoding() {
    for (target, path, query) in [
        ("", "", None),
        ("/api", "/api", None),
        ("?", "", None),
        ("/api?", "/api", None),
        ("/api?x", "/api", Some("x")),
        ("?x", "", Some("x")),
        ("/a?b?c", "/a", Some("b?c")),
        ("/a%3Fb?q=%3F", "/a%3Fb", Some("q=%3F")),
    ] {
        assert_eq!(split_http_target(target), (path, query), "{target:?}");
    }
}

#[tokio::test]
async fn owned_responses_emit_exact_status_headers_and_close_the_socket() {
    for (status, reason) in [
        (100, "Continue"),
        (101, "Switching Protocols"),
        (200, "OK"),
        (201, "Created"),
        (202, "Accepted"),
        (204, "No Content"),
        (301, "Moved Permanently"),
        (302, "Found"),
        (304, "Not Modified"),
        (400, "Bad Request"),
        (401, "Unauthorized"),
        (403, "Forbidden"),
        (404, "Not Found"),
        (405, "Method Not Allowed"),
        (409, "Conflict"),
        (413, "Payload Too Large"),
        (415, "Unsupported Media Type"),
        (422, "Unprocessable Entity"),
        (426, "Upgrade Required"),
        (429, "Too Many Requests"),
        (500, "Internal Server Error"),
        (501, "Not Implemented"),
        (502, "Bad Gateway"),
        (503, "Service Unavailable"),
        (504, "Gateway Timeout"),
        (599, "OK"),
    ] {
        for (version, connection) in [(0, "close"), (1, "keep-alive")] {
            let (stream, mut peer) = socket_pair().await;
            let mut received = Vec::new();
            let exchange = time::timeout(Duration::from_secs(2), async {
                tokio::join!(
                    write_http_response(stream, version, status, vec![], vec![]),
                    peer.read_to_end(&mut received)
                )
            })
            .await;
            assert!(exchange.is_ok(), "status {status}, version {version}");
            let (written, read) = exchange.unwrap();
            assert!(written.is_ok(), "{written:?}");
            assert!(read.is_ok(), "{read:?}");
            let expected = format!(
                "HTTP/1.{version} {status} {reason}\r\nContent-Length: 0\r\nConnection: {connection}\r\n\r\n"
            );
            assert_eq!(received, expected.as_bytes(), "status {status}");
        }
    }
}

async fn socket_pair() -> (IoStream, TcpStream) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await;
    assert!(listener.is_ok());
    let listener = listener.unwrap();
    let address = listener.local_addr();
    assert!(address.is_ok());
    let pair = time::timeout(Duration::from_secs(2), async {
        tokio::join!(TcpStream::connect(address.unwrap()), listener.accept())
    })
    .await;
    assert!(pair.is_ok());
    let (client, server) = pair.unwrap();
    assert!(client.is_ok());
    assert!(server.is_ok());
    (IoStream::plain(server.unwrap().0), client.unwrap())
}

#[tokio::test]
async fn http2_negotiation_selects_exact_alpn_and_preserves_preface() {
    for (tokens, expected) in [
        (vec![], None),
        (vec!["http/1.1"], None),
        (vec!["H2", "h2c"], None),
        (vec!["h2"], Some("h2")),
        (vec!["http/1.1", "h2", "h3"], Some("h2")),
        (vec!["h2", "http/1.1"], Some("h2")),
    ] {
        let mut endpoint = tests::runtime_config(Some(Duration::from_secs(2)), 16);
        endpoint.protocols.push(TransportProtocol::Http2);
        endpoint.http.as_mut().unwrap().alpn = tokens.iter().map(|s| s.to_string()).collect();
        let (stream, mut peer) = socket_pair().await;
        assert!(peer.write_all(HTTP2_PREFACE).await.is_ok());
        let negotiated = negotiate_connection(stream, &endpoint).await;
        assert!(matches!(&negotiated, Ok(NegotiatedConnection::Http2(_))));
        if let Ok(NegotiatedConnection::Http2(handshake)) = negotiated {
            let (mut stream, metadata) = handshake.split();
            assert_eq!(metadata.protocol(), "http/2");
            assert_eq!(metadata.alpn(), expected, "tokens: {tokens:?}");
            assert_eq!(
                metadata.listener_protocols(),
                ["rawsocket", "http", "websocket", "http2"]
            );
            let mut bytes = [0; 24];
            let read = time::timeout(Duration::from_secs(2), stream.read_exact(&mut bytes)).await;
            assert!(matches!(read, Ok(Ok(_))));
            assert_eq!(&bytes, HTTP2_PREFACE);
        }
    }
}

#[tokio::test]
async fn incomplete_protocol_prefix_is_a_protocol_error_not_an_io_error() {
    for prefix_len in 0..4 {
        let endpoint = tests::runtime_config(Some(Duration::from_secs(2)), 16);
        let (stream, mut peer) = socket_pair().await;
        assert!(peer.write_all(&HTTP2_PREFACE[..prefix_len]).await.is_ok());
        assert!(peer.shutdown().await.is_ok());
        let result = negotiate_connection(stream, &endpoint).await;
        assert_eq!(
            matches!(
                &result,
                Err(NegotiationError::Protocol(message))
                    if message == "connection closed before protocol negotiation"
            ),
            true,
            "prefix length {prefix_len}: {result:?}"
        );
    }
}

#[tokio::test]
async fn body_lengths_and_upgrade_decisions_preserve_all_body_phases() {
    for (body, expected_len) in [
        (HttpBodyPhase::Finished, 0),
        (HttpBodyPhase::Buffered(Bytes::new()), 0),
        (HttpBodyPhase::Buffered(Bytes::from_static(b"abc")), 3),
        (
            HttpBodyPhase::NeedsStreaming {
                prefix: Bytes::from_static(b"ab"),
                remaining_len: 5,
            },
            7,
        ),
        (
            HttpBodyPhase::NeedsStreaming {
                prefix: Bytes::new(),
                remaining_len: 9,
            },
            9,
        ),
    ] {
        let (stream, _peer) = socket_pair().await;
        let handshake = HttpHandshake {
            stream,
            request: HttpRequest {
                method: "GET".into(),
                target: "/socket?x=1".into(),
                version: 1,
                headers: vec![
                    ("Upgrade".into(), "websocket".into()),
                    ("Connection".into(), "keep-alive, Upgrade".into()),
                    ("Sec-WebSocket-Key".into(), " test-key ".into()),
                    (
                        "Sec-WebSocket-Protocol".into(),
                        "wamp.2.json, wamp.2.cbor".into(),
                    ),
                    ("Sec-WebSocket-Version".into(), " 13 ".into()),
                    (
                        "Sec-WebSocket-Extensions".into(),
                        "extension-a, extension-b".into(),
                    ),
                ],
            },
            body,
            prefetched: Bytes::from_static(b"next-frame"),
        };
        assert_eq!(handshake.version(), 1);
        assert_eq!(handshake.body_len(), expected_len);
        let upgrade = handshake.try_into_websocket();
        assert_eq!(upgrade.is_ok(), expected_len == 0);
        let mut retained = match upgrade {
            Ok(websocket) => {
                assert_eq!(websocket.sec_websocket_key, "test-key");
                assert_eq!(
                    websocket.sec_websocket_protocols,
                    ["wamp.2.json", "wamp.2.cbor"]
                );
                assert_eq!(websocket.sec_websocket_version.as_deref(), Some("13"));
                assert_eq!(
                    websocket.sec_websocket_extensions,
                    ["extension-a", "extension-b"]
                );
                websocket.http
            }
            Err(http) => http,
        };
        assert_eq!(retained.body_len(), expected_len);
        assert_eq!(retained.request.target, "/socket?x=1");
        assert_eq!(retained.prefetched.as_ref(), b"next-frame");
        retained.request.version = 0;
        assert_eq!(retained.version(), 0);
    }
}

#[tokio::test]
async fn http2_split_preserves_metadata_and_transfers_live_socket() {
    for alpn in [None, Some("h2"), Some("custom-h2")] {
        let (stream, mut peer) = socket_pair().await;
        let handshake = Http2Handshake {
            stream: Some(stream),
            protocol: "http/2".into(),
            alpn: alpn.map(str::to_owned),
            listener_protocols: vec!["http".into(), "websocket".into()],
        };
        let (mut stream, metadata) = handshake.split();
        assert_eq!(metadata.protocol(), "http/2");
        assert_eq!(metadata.alpn(), alpn);
        assert_eq!(metadata.listener_protocols(), ["http", "websocket"]);
        assert!(metadata.into_stream().is_none());
        let exchange = time::timeout(Duration::from_secs(2), async {
            let sent = peer.write_all(b"h2-frame").await;
            assert!(sent.is_ok());
            let mut bytes = [0; 8];
            let received = stream.read_exact(&mut bytes).await;
            assert!(received.is_ok());
            assert_eq!(&bytes, b"h2-frame");
        })
        .await;
        assert!(exchange.is_ok());
    }
}

#[test]
fn http3_metadata_selects_first_supported_alpn_and_retains_protocols() {
    for (tokens, expected) in [
        (vec![], None),
        (vec!["h2", "http/1.1"], None),
        (vec!["h2", "h3", "h3-29"], Some("h3")),
        (vec!["h3-29", "h3"], Some("h3-29")),
        (vec!["H3"], Some("H3")),
        (vec!["h30", "H3-29"], None),
    ] {
        let mut endpoint = tests::runtime_config(None, 16);
        endpoint.http.as_mut().unwrap().alpn = tokens.iter().map(|s| s.to_string()).collect();
        let metadata = Http3Handshake::from_endpoint(&endpoint);
        assert_eq!(metadata.protocol(), "http/3");
        assert_eq!(metadata.alpn(), expected);
        assert_eq!(
            metadata.listener_protocols(),
            ["rawsocket", "http", "websocket"]
        );
        endpoint.http = None;
        endpoint.protocols.clear();
        let metadata = Http3Handshake::from_endpoint(&endpoint);
        assert_eq!(metadata.protocol(), "http/3");
        assert_eq!(metadata.alpn(), None);
        assert!(metadata.listener_protocols().is_empty());
    }
}
