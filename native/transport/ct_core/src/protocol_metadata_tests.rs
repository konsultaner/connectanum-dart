use super::*;
use tokio::net::{TcpListener, TcpStream};

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
