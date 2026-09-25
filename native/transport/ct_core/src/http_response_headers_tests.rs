use super::*;
use quinn_proto::crypto::rustls::QuicClientConfig;

const COOKIE_A: &str = "sid=opaque; HttpOnly";
const COOKIE_B: &str = "language=de; Expires=Wed, 09 Jun 2032 10:18:14 GMT";
const BODY: &[u8] = b"independent response fields";

#[derive(Clone, Copy, Debug)]
enum Mode {
    Plain,
    Buffered,
    Streaming,
}

fn headers() -> Vec<(String, String)> {
    vec![
        ("Set-Cookie".into(), COOKIE_A.into()),
        ("set-cookie".into(), COOKIE_B.into()),
        ("X-Repeated".into(), "first".into()),
        ("x-repeated".into(), "second".into()),
        ("Content-Length".into(), "999".into()),
        ("content-length".into(), "777".into()),
    ]
}

async fn dispatch(mode: Mode) -> HttpResponseDispatch {
    let body = match mode {
        Mode::Buffered => HttpResponseBody::Buffered(BODY.to_vec()),
        Mode::Streaming => {
            let (writer, reader) = response_stream_channel(2);
            tokio::task::spawn_blocking(move || {
                writer.write_chunk(Bytes::from_static(BODY)).unwrap();
                writer.finish().unwrap();
            })
            .await
            .unwrap();
            HttpResponseBody::Streaming(reader)
        }
        Mode::Plain => unreachable!("plain replies use their own response path"),
    };
    HttpResponseDispatch {
        status: 200,
        headers: headers(),
        body,
    }
}

fn assert_headers(response: &HttpResponse<impl Sized>, mode: Mode) {
    assert_eq!(response.status(), StatusCode::OK);
    let cookies: Vec<_> = response.headers().get_all("set-cookie").iter().collect();
    assert_eq!(cookies, [COOKIE_A, COOKIE_B]);
    let repeated: Vec<_> = response.headers().get_all("x-repeated").iter().collect();
    assert_eq!(repeated, ["first", "second"]);
    let lengths: Vec<_> = response
        .headers()
        .get_all("content-length")
        .iter()
        .collect();
    if matches!(mode, Mode::Streaming) {
        assert!(lengths.is_empty());
    } else {
        assert_eq!(lengths, [BODY.len().to_string().as_str()]);
    }
}

async fn check_http2(mode: Mode) {
    time::timeout(Duration::from_secs(5), async {
        let (server_io, client_io) = tokio::io::duplex(65536);
        let server = tokio::spawn(async move {
            let mut connection = http2_server_builder()
                .handshake::<_, Bytes>(server_io)
                .await
                .unwrap();
            let (_, respond) = connection.accept().await.unwrap().unwrap();
            let driver = tokio::spawn(async move { while connection.accept().await.is_some() {} });
            match mode {
                Mode::Plain => {
                    let fields = headers();
                    let fields: Vec<_> = fields
                        .iter()
                        .map(|(n, v)| (n.as_str(), v.as_str()))
                        .collect();
                    send_http2_plain_response(respond, StatusCode::OK, BODY, &fields)
                        .await
                        .unwrap();
                }
                _ => send_http2_response_from_dispatch(
                    respond,
                    dispatch(mode).await,
                    Arc::new(Http2ConnectionWriteTracker::default()),
                )
                .await
                .unwrap(),
            }
            driver
        });
        let (mut requests, connection) = h2::client::handshake(client_io).await.unwrap();
        let driver = tokio::spawn(connection);
        let request = HttpRequest::builder()
            .uri("https://localhost/cookies")
            .body(())
            .unwrap();
        let (response, _) = requests.send_request(request, true).unwrap();
        let response = response.await.unwrap();
        assert_headers(&response, mode);
        let mut body = response.into_body();
        let mut bytes = Vec::new();
        while let Some(data) = body.data().await {
            let data = data.unwrap();
            body.flow_control().release_capacity(data.len()).unwrap();
            bytes.extend_from_slice(&data);
        }
        assert_eq!(bytes, BODY);
        let server_driver = server.await.unwrap();
        server_driver.abort();
        let _ = server_driver.await;
        driver.abort();
        let _ = driver.await;
    })
    .await
    .expect("bounded HTTP/2 header fixture");
}

async fn check_http3(mode: Mode) {
    time::timeout(Duration::from_secs(5), async {
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let mut server_crypto = RustlsServerConfig::builder_with_provider(provider.clone())
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(
                vec![identity.cert.der().clone()],
                rustls::pki_types::PrivatePkcs8KeyDer::from(identity.key_pair.serialize_der())
                    .into(),
            )
            .unwrap();
        server_crypto.alpn_protocols = vec![b"h3".to_vec()];
        let server_config = QuinnServerConfig::with_crypto(Arc::new(
            QuinnRustlsServerConfig::try_from(server_crypto).unwrap(),
        ));
        let endpoint =
            QuinnEndpoint::server(server_config, "127.0.0.1:0".parse().unwrap()).unwrap();
        let address = endpoint.local_addr().unwrap();
        let mut roots = rustls::RootCertStore::empty();
        roots.add(identity.cert.der().clone()).unwrap();
        let mut client_crypto = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_root_certificates(roots)
            .with_no_client_auth();
        client_crypto.alpn_protocols = vec![b"h3".to_vec()];
        let mut client = QuinnEndpoint::client("127.0.0.1:0".parse().unwrap()).unwrap();
        client.set_default_client_config(quinn::ClientConfig::new(Arc::new(
            QuicClientConfig::try_from(client_crypto).unwrap(),
        )));
        let (done, finished) = oneshot::channel();
        let server = tokio::spawn(async move {
            let connection = endpoint.accept().await.unwrap().await.unwrap();
            let mut connection = h3::server::builder()
                .build(H3QuinnConnection::new(connection))
                .await
                .unwrap();
            let (_, stream) = connection
                .accept()
                .await
                .unwrap()
                .unwrap()
                .resolve_request()
                .await
                .unwrap();
            let (mut send, _) = stream.split();
            match mode {
                Mode::Plain => {
                    let fields = headers();
                    let fields: Vec<_> = fields
                        .iter()
                        .map(|(n, v)| (n.as_str(), v.as_str()))
                        .collect();
                    send_http3_plain_response(&mut send, StatusCode::OK, BODY, &fields)
                        .await
                        .unwrap();
                }
                _ => send_http3_response_from_dispatch(&mut send, dispatch(mode).await)
                    .await
                    .unwrap(),
            }
            let _ = finished.await;
            endpoint.close(VarInt::from_u32(0), b"test complete");
        });
        let connection = client.connect(address, "localhost").unwrap().await.unwrap();
        let (mut driver, mut requests) = h3::client::builder()
            .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
            .await
            .unwrap();
        let driver = tokio::spawn(async move {
            std::future::poll_fn(|cx| driver.poll_close(cx)).await;
        });
        let request = HttpRequest::builder()
            .uri(format!("https://localhost:{}/cookies", address.port()))
            .body(())
            .unwrap();
        let mut stream = requests.send_request(request).await.unwrap();
        stream.finish().await.unwrap();
        let response = stream.recv_response().await.unwrap();
        assert_headers(&response, mode);
        let mut bytes = Vec::new();
        while let Some(mut data) = stream.recv_data().await.unwrap() {
            bytes.extend_from_slice(&data.copy_to_bytes(data.remaining()));
        }
        assert_eq!(bytes, BODY);
        done.send(()).unwrap();
        server.await.unwrap();
        client.close(VarInt::from_u32(0), b"test complete");
        driver.abort();
        let _ = driver.await;
    })
    .await
    .expect("bounded HTTP/3 header fixture");
}

#[tokio::test]
async fn http2_plain_preserves_repeated_headers() {
    check_http2(Mode::Plain).await;
}
#[tokio::test]
async fn http2_buffered_preserves_repeated_headers() {
    check_http2(Mode::Buffered).await;
}
#[tokio::test]
async fn http2_streaming_preserves_repeated_headers() {
    check_http2(Mode::Streaming).await;
}
#[tokio::test]
async fn http3_plain_preserves_repeated_headers() {
    check_http3(Mode::Plain).await;
}
#[tokio::test]
async fn http3_buffered_preserves_repeated_headers() {
    check_http3(Mode::Buffered).await;
}
#[tokio::test]
async fn http3_streaming_preserves_repeated_headers() {
    check_http3(Mode::Streaming).await;
}
