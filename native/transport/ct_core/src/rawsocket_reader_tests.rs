use super::*;

struct ReaderFixture {
    peer: tokio::net::TcpStream,
    messages: mpsc::Receiver<wamp::ParsedMessage>,
    controls: mpsc::Receiver<OutboundFrame>,
    pongs: tokio::sync::mpsc::UnboundedReceiver<Bytes>,
    closed: tokio::sync::mpsc::UnboundedReceiver<ConnectionTaskSignal>,
    task: AbortHandle,
}

impl Drop for ReaderFixture {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl ReaderFixture {
    async fn new(exponent: u32, idle: Option<Duration>, observe_pongs: bool) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await;
        assert!(listener.is_ok());
        let listener = listener.unwrap();
        let address = listener.local_addr();
        assert!(address.is_ok());
        let pair = time::timeout(Duration::from_secs(2), async {
            tokio::join!(
                tokio::net::TcpStream::connect(address.unwrap()),
                listener.accept()
            )
        })
        .await;
        assert!(pair.is_ok());
        let (peer, server) = pair.unwrap();
        assert!(peer.is_ok());
        assert!(server.is_ok());
        let (reader, _writer) = tokio::io::split(IoStream::plain(server.unwrap().0));
        let endpoint = serde_json::from_value::<config::EndpointConfig>(serde_json::json!({
            "host": "127.0.0.1", "port": 0, "tls_mode": "disabled"
        }));
        assert!(endpoint.is_ok());
        let endpoint = config::EndpointRuntimeConfig::try_from_endpoint(&endpoint.unwrap());
        assert!(endpoint.is_ok());
        let mut endpoint = endpoint.unwrap();
        endpoint.idle_timeout = idle;
        let (frames, messages) = mpsc::channel(4);
        let (outbound, controls) = mpsc::channel(4);
        let (pong, pongs) = mpsc::unbounded_channel();
        let (close, closed) = mpsc::unbounded_channel();
        let task = spawn_connection_reader(
            tokio::runtime::Handle::current(),
            ConnectionId(71),
            Arc::new(endpoint),
            reader,
            rawsocket::Serializer::Json,
            exponent,
            frames,
            outbound,
            observe_pongs.then_some(pong),
            close,
        );
        Self {
            peer: peer.unwrap(),
            messages,
            controls,
            pongs,
            closed,
            task,
        }
    }

    async fn write(&mut self, bytes: &[u8]) {
        let result = time::timeout(Duration::from_secs(2), self.peer.write_all(bytes)).await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_ok());
    }

    async fn frame(&mut self, kind: u8, payload: &[u8], upgraded: bool) {
        // Construct wire bytes independently of the production header encoder.
        let length = (payload.len() as u32).to_be_bytes();
        let mut wire = vec![kind];
        wire.extend_from_slice(if upgraded { &length } else { &length[1..] });
        wire.extend_from_slice(payload);
        self.write(&wire).await;
    }

    async fn assert_closed(&mut self) {
        let signal = time::timeout(Duration::from_secs(2), self.closed.recv()).await;
        assert!(signal.is_ok());
        assert_eq!(signal.unwrap(), Some(ConnectionTaskSignal::ReaderClosed));
        let next = time::timeout(Duration::from_secs(2), self.closed.recv()).await;
        assert!(next.is_ok());
        assert_eq!(next.unwrap(), None);
    }
}

async fn receive<T>(receiver: &mut mpsc::Receiver<T>) -> T {
    let result = time::timeout(Duration::from_secs(2), receiver.recv()).await;
    assert!(result.is_ok());
    let result = result.unwrap();
    assert!(result.is_some());
    result.unwrap()
}

#[tokio::test]
async fn rawsocket_reader_preserves_messages_ping_and_pong_in_both_framings() {
    for (exponent, upgraded) in [(16, false), (24, false), (25, true)] {
        let mut fixture = ReaderFixture::new(exponent, None, true).await;
        for payload in [b"".as_slice(), &[0, 127, 128, 255]] {
            fixture.frame(1, payload, upgraded).await;
            let response = receive(&mut fixture.controls).await;
            assert_eq!(response.frame_type, 2);
            assert_eq!(response.payload_len, payload.len());
            assert_eq!(response.segments, vec![Bytes::copy_from_slice(payload)]);
            fixture.frame(2, payload, upgraded).await;
            let pong = time::timeout(Duration::from_secs(2), fixture.pongs.recv()).await;
            assert!(pong.is_ok());
            assert_eq!(pong.unwrap(), Some(Bytes::copy_from_slice(payload)));
        }
        let payload = br#"[1,"realm.test",{}]"#;
        fixture.frame(0, payload, upgraded).await;
        let message = receive(&mut fixture.messages).await;
        assert_eq!(message.serializer, rawsocket::Serializer::Json);
        assert_eq!(message.raw.into_bytes(), Bytes::from_static(payload));
        assert_eq!(
            message.message,
            wamp::WampMessage::Hello {
                realm: "realm.test".into(),
                details: Default::default()
            }
        );
        assert!(fixture.peer.shutdown().await.is_ok());
        fixture.assert_closed().await;
        assert!(fixture.messages.recv().await.is_none());
    }
}

#[tokio::test]
async fn rawsocket_reader_continues_without_a_live_pong_observer() {
    for observe in [false, true] {
        let mut fixture = ReaderFixture::new(16, None, observe).await;
        fixture.pongs.close();
        fixture.frame(2, b"discarded pong", false).await;
        fixture.frame(1, b"still alive", false).await;
        let response = receive(&mut fixture.controls).await;
        assert_eq!(response.frame_type, 2);
        assert_eq!(response.segments, vec![Bytes::from_static(b"still alive")]);
        assert!(fixture.peer.shutdown().await.is_ok());
        fixture.assert_closed().await;
        assert!(fixture.messages.recv().await.is_none());
    }
}

#[tokio::test]
async fn rawsocket_reader_rejects_bad_frames_without_delivering_messages() {
    for wire in [
        vec![0x10, 0, 0, 0],          // Reserved bits.
        vec![3, 0, 0, 0],             // Unknown control frame.
        vec![0, 1, 0, 1],             // Payload exceeds the negotiated 64 KiB limit.
        vec![0, 0, 0, 1, b'!'],       // Invalid JSON.
        vec![0, 0, 0, 2, b'[', b']'], // Valid JSON, invalid WAMP message.
    ] {
        let mut fixture = ReaderFixture::new(16, None, true).await;
        fixture.write(&wire).await;
        // Keep the peer open: invalid input itself must terminate the reader.
        fixture.assert_closed().await;
        assert!(fixture.messages.recv().await.is_none());
        assert!(fixture.controls.recv().await.is_none());
        assert!(fixture.pongs.recv().await.is_none());
    }
}

#[tokio::test]
async fn rawsocket_reader_stops_when_delivery_channels_are_closed() {
    for message in [false, true] {
        let mut fixture = ReaderFixture::new(16, None, true).await;
        if message {
            fixture.messages.close();
            fixture.frame(0, br#"[1,"realm.test",{}]"#, false).await;
        } else {
            fixture.controls.close();
            fixture.frame(1, b"no receiver", false).await;
        }
        fixture.assert_closed().await;
        assert!(fixture.messages.recv().await.is_none());
        assert!(fixture.controls.recv().await.is_none());
    }
}

#[tokio::test]
async fn rawsocket_reader_closes_on_idle_and_truncated_input() {
    let mut idle = ReaderFixture::new(16, Some(Duration::from_millis(20)), true).await;
    idle.assert_closed().await;
    assert!(idle.messages.recv().await.is_none());
    for wire in [vec![], vec![0, 0], vec![0, 0, 0, 3, b'[']] {
        let mut fixture = ReaderFixture::new(16, None, true).await;
        fixture.write(&wire).await;
        assert!(fixture.peer.shutdown().await.is_ok());
        fixture.assert_closed().await;
        assert!(fixture.messages.recv().await.is_none());
    }
}
