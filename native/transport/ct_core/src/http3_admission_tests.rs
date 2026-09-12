use super::*;
use quinn_proto::crypto::rustls::QuicClientConfig;
use tokio::net::UdpSocket;

const TEST_DEADLINE: Duration = Duration::from_secs(3);
// Quinn retains closing connections for three PTOs (about three seconds at
// its default initial RTT). Allow that protocol cleanup after cancellation.
const DRAIN_DEADLINE: Duration = Duration::from_secs(6);

struct TestServer {
    endpoint: QuinnEndpoint,
    listener: JoinHandle<()>,
    registry: Arc<ListenerRegistry>,
    addr: SocketAddr,
    accepted: mpsc::Receiver<ConnectionId>,
    client_config: quinn::ClientConfig,
}

impl TestServer {
    fn new(runtime: &Runtime, handshake_timeout: Duration) -> Self {
        Self::with_backlog(runtime, handshake_timeout, 16)
    }

    fn with_backlog(runtime: &Runtime, handshake_timeout: Duration, backlog: usize) -> Self {
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".to_owned()])
            .expect("test certificate");
        let mut roots = rustls::RootCertStore::empty();
        roots.add(identity.cert.der().clone()).unwrap();
        let mut client_crypto = rustls::ClientConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
        client_crypto.alpn_protocols = vec![b"h3".to_vec()];
        let client_config =
            quinn::ClientConfig::new(Arc::new(QuicClientConfig::try_from(client_crypto).unwrap()));
        let config = config::EndpointRuntimeConfig {
            host: "127.0.0.1".to_owned(),
            port: 0,
            tls_mode: config::TlsMode::Native,
            client_auth: None,
            protocols: vec![TransportProtocol::Http3],
            idle_timeout: None,
            heartbeat_interval: None,
            heartbeat_timeout: None,
            handshake_timeout,
            max_http_content_length: None,
            max_rawsocket_size_exponent: config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
            max_rawsocket_size: 1u64 << config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
            max_upgrade_exponent: None,
            outbound_send_queue_capacity: config::DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY,
            websocket_path: None,
            sni_certificates: vec![config::SniCertificate {
                hostname: "localhost".to_owned(),
                certificate_chain_pem: identity.cert.pem(),
                private_key_pem: identity.key_pair.serialize_pem(),
            }],
            http_routes: Vec::new(),
            http: None,
        };
        let registry = Arc::new(ListenerRegistry::default());
        let (sender, accepted) = mpsc::channel(16);
        let (endpoint, listener, addr) = start_http3_listener(
            ListenerId(1),
            "127.0.0.1:0".parse().unwrap(),
            Arc::new(ListenerConfigState::new(Arc::new(config), None)),
            Arc::clone(&registry),
            sender,
            runtime.handle().clone(),
            backlog,
        )
        .expect("HTTP/3 listener");
        Self {
            endpoint,
            listener,
            registry,
            addr,
            accepted,
            client_config,
        }
    }

    fn client(&self) -> QuinnEndpoint {
        let mut endpoint = QuinnEndpoint::client("127.0.0.1:0".parse().unwrap()).unwrap();
        endpoint.set_default_client_config(self.client_config.clone());
        endpoint
    }

    async fn ordinary_request(&mut self) {
        time::timeout(TEST_DEADLINE, async {
            let endpoint = self.client();
            let connection = endpoint
                .connect(self.addr, "localhost")
                .unwrap()
                .await
                .unwrap();
            let (mut driver, mut requests) = h3::client::builder()
                .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                .await
                .unwrap();
            let driver = tokio::spawn(async move {
                std::future::poll_fn(|cx| driver.poll_close(cx)).await;
            });
            let request = HttpRequest::builder()
                .uri(format!(
                    "https://localhost:{}/admission-control",
                    self.addr.port()
                ))
                .body(())
                .unwrap();
            let mut stream = requests.send_request(request).await.unwrap();
            stream.finish().await.unwrap();
            assert_eq!(
                stream.recv_response().await.unwrap().status(),
                StatusCode::NOT_FOUND
            );
            while stream.recv_data().await.unwrap().is_some() {}
            let id = self.accepted.recv().await.expect("registered client");
            assert_eq!(
                self.registry.connection_protocol(id).unwrap(),
                ConnectionProtocol::Http3
            );
            endpoint.close(VarInt::from_u32(0), b"test done");
            driver.abort();
        })
        .await
        .expect("independent HTTP/3 client must finish while another handshake is incomplete");
    }

    async fn incomplete_handshake(&self) -> PendingHandshake {
        // Forward actual QUIC Initial packets, but never deliver server replies.
        // Observing a reply proves admission without a sleep-based ordering guess.
        let relay = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let relay_addr = relay.local_addr().unwrap();
        let endpoint = self.client();
        let connecting = endpoint.connect(relay_addr, "localhost").unwrap();
        let server_addr = self.addr;
        let (first_reply, reply_seen) = oneshot::channel();
        let relay = tokio::spawn(async move {
            let mut first_reply = Some(first_reply);
            let mut packet = vec![0u8; 65536];
            loop {
                let (len, source) = relay.recv_from(&mut packet).await.unwrap();
                if source == server_addr {
                    if let Some(signal) = first_reply.take() {
                        let _ = signal.send(());
                    }
                } else {
                    relay.send_to(&packet[..len], server_addr).await.unwrap();
                }
            }
        });
        let pending = PendingHandshake {
            endpoint,
            _connecting: connecting,
            relay,
        };
        time::timeout(TEST_DEADLINE, reply_seen)
            .await
            .expect("server must begin the incomplete handshake")
            .expect("relay remains alive");
        pending
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.endpoint.close(VarInt::from_u32(0), b"test cleanup");
        self.listener.abort();
        self.registry.shutdown();
    }
}

struct PendingHandshake {
    endpoint: QuinnEndpoint,
    _connecting: quinn::Connecting,
    relay: JoinHandle<()>,
}

impl Drop for PendingHandshake {
    fn drop(&mut self) {
        self.endpoint.close(VarInt::from_u32(0), b"test cleanup");
        self.relay.abort();
    }
}

#[test]
fn http3_admission_ordinary_client_positive_control() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::new(&runtime, Duration::from_secs(30));
    runtime.block_on(server.ordinary_request());
}

#[test]
fn http3_admission_connection_churn_releases_native_owners() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::new(&runtime, Duration::from_secs(30));
    let initial_registry_owners = Arc::strong_count(&server.registry);
    runtime.block_on(async {
        let mut total_events = 0;
        for burst in 0..4 {
            let release = Arc::new(tokio::sync::Barrier::new(9));
            let mut clients = JoinSet::new();
            let mut connection_owners = Vec::new();
            let mut stream_owners = Vec::new();
            let mut ids = std::collections::HashSet::new();
            time::timeout(TEST_DEADLINE, async {
                for _ in 0..8 {
                    let endpoint = server.client();
                    let addr = server.addr;
                    let release = Arc::clone(&release);
                    clients.spawn(async move {
                        let connection =
                            endpoint.connect(addr, "localhost").unwrap().await.unwrap();
                        let (mut driver, mut requests) = h3::client::builder()
                            .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                            .await
                            .unwrap();
                        let driver = tokio::spawn(async move {
                            std::future::poll_fn(|cx| driver.poll_close(cx)).await;
                        });
                        if burst % 2 == 0 {
                            let request = HttpRequest::builder()
                                .uri(format!("https://localhost:{}/churn", addr.port()))
                                .body(())
                                .unwrap();
                            let mut stream = requests.send_request(request).await.unwrap();
                            stream.finish().await.unwrap();
                            assert_eq!(
                                stream.recv_response().await.unwrap().status(),
                                StatusCode::NOT_FOUND
                            );
                            while stream.recv_data().await.unwrap().is_some() {}
                        }
                        // Keep completed and requestless connections alive until
                        // the parent has captured their native weak owners.
                        release.wait().await;
                        endpoint.close(VarInt::from_u32(0), b"churn client done");
                        driver.abort();
                    });
                }
                for _ in 0..8 {
                    let id = server.accepted.recv().await.unwrap();
                    assert!(ids.insert(id));
                    let connections = server.registry.connections.lock().unwrap();
                    let entry = connections.get(&id).expect("live registered connection");
                    let ConnectionRecord::Http3Pending {
                        connection,
                        streams,
                        ..
                    } = &entry.record
                    else {
                        panic!("expected HTTP/3 record");
                    };
                    connection_owners
                        .push(Arc::downgrade(connection.lock().unwrap().as_ref().unwrap()));
                    stream_owners.push(Arc::downgrade(streams));
                }
                release.wait().await;
                while let Some(client) = clients.join_next().await {
                    client.unwrap();
                }
            })
            .await
            .expect("all churn clients must complete without a shutdown");

            time::timeout(DRAIN_DEADLINE, async {
                server.endpoint.wait_idle().await;
                loop {
                    if server.registry.connections.lock().unwrap().is_empty()
                        && connection_owners
                            .iter()
                            .all(|owner| owner.upgrade().is_none())
                        && stream_owners.iter().all(|owner| owner.upgrade().is_none())
                        && Arc::strong_count(&server.registry) == initial_registry_owners
                    {
                        break;
                    }
                    time::sleep(Duration::from_millis(1)).await;
                }
            })
            .await
            .expect("QUIC and native owners must drain with the listener still open");
            assert_eq!(server.endpoint.open_connections(), 0);
            assert!(!server.listener.is_finished());
            assert!(server.accepted.try_recv().is_err());
            let mut events = std::collections::HashSet::new();
            while let Some(event) = server.registry.poll_http_connection_event() {
                assert!(events.insert(event.connection_id));
                assert_eq!(event.protocol, ConnectionProtocol::Http3);
                assert_eq!(event.reason, HttpConnectionCloseReason::Graceful);
                assert_eq!(event.request_count, if burst % 2 == 0 { 1 } else { 0 });
            }
            assert_eq!(events, ids);
            total_events += events.len();
        }
        assert_eq!(total_events, 32);
    });
}

#[test]
fn http3_admission_incomplete_handshake_does_not_block_other_clients() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::new(&runtime, Duration::from_secs(30));
    runtime.block_on(async {
        let _pending = server.incomplete_handshake().await;
        assert_eq!(server.endpoint.open_connections(), 1);
        server.ordinary_request().await;
    });
}

#[test]
fn http3_admission_honors_configured_handshake_deadline() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::new(&runtime, Duration::from_millis(150));
    runtime.block_on(async {
        let _pending = server.incomplete_handshake().await;
        time::timeout(DRAIN_DEADLINE, server.endpoint.wait_idle())
            .await
            .expect("configured deadline must release the incomplete handshake");
        assert!(
            server.accepted.try_recv().is_err(),
            "unauthenticated peer was registered"
        );
        server.ordinary_request().await;
    });
}

#[test]
fn http3_admission_shutdown_cancels_incomplete_handshake() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::new(&runtime, Duration::from_secs(30));
    runtime.block_on(async {
        let _pending = server.incomplete_handshake().await;
        server.listener.abort();
        server
            .endpoint
            .close(VarInt::from_u32(0), b"listener closed");
        let _ = (&mut server.listener).await;
        time::timeout(DRAIN_DEADLINE, server.endpoint.wait_idle())
            .await
            .expect("shutdown releases incomplete handshakes");
        assert!(server.registry.connections.lock().unwrap().is_empty());
        assert!(server.accepted.try_recv().is_err());
    });
}

#[test]
fn http3_admission_backlog_rejects_excess_and_recovers_after_expiry() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::with_backlog(&runtime, Duration::from_millis(1500), 2);
    runtime.block_on(async {
        let _first = server.incomplete_handshake().await;
        let _second = server.incomplete_handshake().await;
        assert_eq!(server.endpoint.open_connections(), 2);
        let client = server.client();
        let refused = time::timeout(
            TEST_DEADLINE,
            client.connect(server.addr, "localhost").unwrap(),
        )
        .await
        .expect("excess handshake must be refused, not queued")
        .expect_err("handshake backlog must be bounded");
        assert!(
            matches!(&refused, quinn::ConnectionError::ConnectionClosed(close)
                if close.error_code == quinn::TransportErrorCode::CONNECTION_REFUSED),
            "expected stateless CONNECTION_REFUSED, got {refused:?}"
        );
        assert!(server.accepted.try_recv().is_err());
        time::timeout(DRAIN_DEADLINE, server.endpoint.wait_idle())
            .await
            .expect("expired handshakes drain");
        server.ordinary_request().await;
    });
}

#[test]
fn http3_admission_closed_receiver_cancels_pending_work() {
    let runtime = Runtime::new().unwrap();
    let mut server = TestServer::new(&runtime, Duration::from_secs(30));
    runtime.block_on(async {
        let _pending = server.incomplete_handshake().await;
        server.accepted.close();
        time::timeout(TEST_DEADLINE, &mut server.listener)
            .await
            .expect("closed receiver stops listener despite incomplete handshake")
            .expect("listener exits cleanly");
        time::timeout(DRAIN_DEADLINE, server.endpoint.wait_idle())
            .await
            .expect("listener owns and cancels pending handshakes");
        assert!(server.registry.connections.lock().unwrap().is_empty());
    });
}
