use super::*;
use quinn_proto::crypto::rustls::QuicServerConfig;
use rustls::pki_types::{PrivateKeyDer, PrivatePkcs8KeyDer};

pub(super) async fn spawn(steps: Vec<Step>) -> Peer {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let certified = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let mut crypto = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(
            vec![certified.cert.der().clone()],
            PrivateKeyDer::from(PrivatePkcs8KeyDer::from(certified.key_pair.serialize_der())),
        )
        .unwrap();
    crypto.alpn_protocols = vec![b"h3".to_vec()];
    let config =
        quinn::ServerConfig::with_crypto(Arc::new(QuicServerConfig::try_from(crypto).unwrap()));
    let endpoint = quinn::Endpoint::server(config, (Ipv4Addr::LOCALHOST, 0).into()).unwrap();
    let address = HttpEndpoint {
        scheme: "https".into(),
        host: "127.0.0.1".into(),
        port: endpoint.local_addr().unwrap().port(),
        http3_port: Some(endpoint.local_addr().unwrap().port()),
    };
    let requests = Arc::new(Mutex::new(Vec::new()));
    let recorded = Arc::clone(&requests);
    let connections = Arc::new(AtomicUsize::new(0));
    let accepted = Arc::clone(&connections);
    let steps = Arc::new(steps);
    let (stop, mut stopping) = oneshot::channel();
    let server = tokio::spawn(async move {
        let mut workers = JoinSet::new();
        loop {
            tokio::select! {
                _ = &mut stopping => break,
                Some(result) = workers.join_next(), if !workers.is_empty() => {
                    result.expect("HTTP/3 fixture worker panicked");
                }
                incoming = endpoint.accept() => {
                    let incoming = incoming.expect("HTTP/3 fixture closed early");
                    let id = accepted.fetch_add(1, Ordering::SeqCst);
                    assert!(id < 16);
                    let recorded = recorded.clone();
                    let steps = steps.clone();
                    workers.spawn(async move {
                        let connection = incoming.await.unwrap();
                        let mut server = h3::server::builder()
                            .build(H3QuinnConnection::new(connection.clone())).await.unwrap();
                        loop {
                            let resolver = match server.accept().await {
                                Ok(Some(resolver)) => resolver,
                                Ok(None) => break,
                                Err(error) => {
                                    // The benchmark explicitly closes QUIC endpoints with code zero.
                                    let closed = matches!(connection.close_reason(),
                                        Some(quinn::ConnectionError::ApplicationClosed(ref close))
                                        if close.error_code == 0u32.into());
                                    assert!(closed || error.is_h3_no_error(), "{error:?}");
                                    break;
                                }
                            };
                            let (request, mut stream) = resolver.resolve_request().await.unwrap();
                            let mut bytes = Vec::new();
                            while let Some(mut chunk) = stream.recv_data().await.unwrap() {
                                bytes.extend_from_slice(&chunk.copy_to_bytes(chunk.remaining()));
                            }
                            let observed = Observed {
                                connection: id,
                                method: request.method().to_string(),
                                path: request.uri().path().into(),
                                bearer: request.headers().get("authorization")
                                    .map(|value| value.to_str().unwrap().into()),
                                body: bytes,
                            };
                            let step = {
                                let mut recorded = recorded.lock().unwrap();
                                let index = recorded.len();
                                recorded.push(observed);
                                steps.get(index).cloned().expect("unexpected extra request")
                            };
                            stream.send_response(http3::Response::builder()
                                .status(step.status).body(()).unwrap()).await.unwrap();
                            if !step.body.is_empty() {
                                stream.send_data(Bytes::from(step.body)).await.unwrap();
                            }
                            stream.finish().await.unwrap();
                        }
                    });
                }
            }
        }
        workers.abort_all();
        while let Some(result) = workers.join_next().await {
            if let Err(error) = result {
                assert!(error.is_cancelled(), "fixture task failed: {error}");
            }
        }
        endpoint.close(0u32.into(), b"fixture complete");
    });
    Peer {
        endpoint: address,
        requests,
        connections,
        stop: Some(stop),
        server: Some(server),
    }
}
