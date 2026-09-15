use super::{protocol, response_stream_channel, write_http1_chunked_response};
use bytes::Bytes;
use std::{
    io,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};
use tokio::io::{AsyncReadExt, AsyncWrite, AsyncWriteExt, DuplexStream};
use tokio::time::{timeout, Duration};
use tokio_rustls::{client, server, TlsAcceptor, TlsConnector};

async fn tls_pair() -> (
    server::TlsStream<DuplexStream>,
    client::TlsStream<DuplexStream>,
) {
    let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut server = rustls::ServerConfig::builder_with_provider(provider.clone())
        .with_protocol_versions(&[&rustls::version::TLS13])
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(
            vec![identity.cert.der().clone()],
            rustls::pki_types::PrivatePkcs8KeyDer::from(identity.key_pair.serialize_der()).into(),
        )
        .unwrap();
    // Do not fill the tiny fixture pipe with post-handshake session tickets
    // before the client application starts reading response bytes.
    server.send_tls13_tickets = 0;
    let mut roots = rustls::RootCertStore::empty();
    roots.add(identity.cert.der().clone()).unwrap();
    let client = rustls::ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
    let acceptor = TlsAcceptor::from(Arc::new(server));
    let connector = TlsConnector::from(Arc::new(client));
    // Less than a TLS record: accepted plaintext can leave ciphertext pending.
    let (server, client) = tokio::io::duplex(64);
    let (server, client) = tokio::join!(
        acceptor.accept(server),
        connector.connect("localhost".try_into().unwrap(), client),
    );
    (server.unwrap(), client.unwrap())
}

async fn send_response<W: AsyncWrite + Unpin>(
    writer: &mut W,
    chunked: bool,
    body: Vec<u8>,
) -> io::Result<()> {
    if chunked {
        let (producer, mut reader) = response_stream_channel(2);
        let fill = tokio::task::spawn_blocking(move || {
            producer.write_chunk(Bytes::from(body)).unwrap();
            producer.finish().unwrap();
        });
        fill.await.unwrap();
        write_http1_chunked_response(
            writer,
            1,
            200,
            &[
                ("Transfer-Encoding".into(), "chunked".into()),
                ("Connection".into(), "keep-alive".into()),
            ],
            &mut reader,
        )
        .await
    } else {
        protocol::write_http_response_shared(writer, 1, 200, &[], &body).await
    }
}

fn expected_response(chunked: bool, body: &[u8]) -> Vec<u8> {
    let mut result = if chunked {
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n".to_vec()
    } else {
        format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: keep-alive\r\n\r\n",
            body.len()
        )
        .into_bytes()
    };
    if chunked && !body.is_empty() {
        result.extend_from_slice(format!("{:X}\r\n", body.len()).as_bytes());
    }
    result.extend_from_slice(body);
    if chunked {
        if !body.is_empty() {
            result.extend_from_slice(b"\r\n");
        }
        result.extend_from_slice(b"0\r\n\r\n");
    }
    result
}

async fn assert_tls_response_completion(chunked: bool, len: usize) {
    timeout(Duration::from_secs(5), async {
        let (mut server, mut client) = tls_pair().await;
        let body = vec![0x5a; len];
        let expected = expected_response(chunked, &body);
        let server = tokio::spawn(async move {
            send_response(&mut server, chunked, body).await.unwrap();
            assert!(
                !server.get_ref().1.wants_write(),
                "HTTP/1 response returned with unflushed TLS ciphertext"
            );
            // No shutdown or extra write may implicitly flush the first response.
            let mut next = [0; 4];
            server.read_exact(&mut next).await.unwrap();
            assert_eq!(&next, b"next");
            send_response(&mut server, false, b"second".to_vec())
                .await
                .unwrap();
            assert!(!server.get_ref().1.wants_write());
        });
        let mut received = vec![0; expected.len()];
        client
            .read_exact(&mut received)
            .await
            .expect("complete first response before the next request");
        assert_eq!(received, expected);
        client.write_all(b"next").await.unwrap();
        client.flush().await.unwrap();
        let expected = expected_response(false, b"second");
        let mut received = vec![0; expected.len()];
        client.read_exact(&mut received).await.unwrap();
        assert_eq!(received, expected);
        server.await.unwrap();
    })
    .await
    .expect("bounded HTTP/1 TLS completion test");
}

#[tokio::test]
async fn http1_tls_buffered_response_flushes_before_keepalive_wait() {
    assert_tls_response_completion(false, 8192).await;
}

#[tokio::test]
async fn http1_tls_empty_buffered_response_flushes_headers() {
    assert_tls_response_completion(false, 0).await;
}

#[tokio::test]
async fn http1_tls_chunked_response_flushes_terminal_frame() {
    assert_tls_response_completion(true, 1024 * 1024).await;
}

#[tokio::test]
async fn http1_tls_empty_chunked_response_flushes_terminal_frame() {
    assert_tls_response_completion(true, 0).await;
}

#[tokio::test]
async fn http1_tls_stream_headers_flush_before_first_chunk() {
    timeout(Duration::from_secs(5), async {
        let (mut server, mut client) = tls_pair().await;
        let (producer, mut reader) = response_stream_channel(2);
        let server = tokio::spawn(async move {
            write_http1_chunked_response(
                &mut server,
                1,
                200,
                &[
                    ("Transfer-Encoding".into(), "chunked".into()),
                    ("Connection".into(), "keep-alive".into()),
                ],
                &mut reader,
            )
            .await
            .unwrap();
        });

        let expected = expected_response(true, b"");
        let header_len = expected.len() - b"0\r\n\r\n".len();
        let mut received = vec![0; header_len];
        timeout(Duration::from_millis(250), client.read_exact(&mut received))
            .await
            .expect("stream headers must be readable before the first chunk")
            .unwrap();
        assert_eq!(received, expected[..header_len]);

        tokio::task::spawn_blocking(move || producer.finish().unwrap())
            .await
            .unwrap();
        let mut terminal = [0; 5];
        client.read_exact(&mut terminal).await.unwrap();
        assert_eq!(&terminal, b"0\r\n\r\n");
        server.await.unwrap();
    })
    .await
    .expect("bounded pre-chunk HTTP/1 TLS test");
}

#[tokio::test]
async fn http1_tls_streamed_chunk_flushes_before_producer_finishes() {
    timeout(Duration::from_secs(5), async {
        let (mut server, mut client) = tls_pair().await;
        let (producer, mut reader) = response_stream_channel(2);
        let server = tokio::spawn(async move {
            write_http1_chunked_response(
                &mut server,
                1,
                200,
                &[
                    ("Transfer-Encoding".into(), "chunked".into()),
                    ("Connection".into(), "keep-alive".into()),
                ],
                &mut reader,
            )
            .await
            .unwrap();
        });

        let body = Bytes::from_static(b"data: ready\n\n");
        let queued = body.clone();
        let writer = producer.clone();
        tokio::task::spawn_blocking(move || writer.write_chunk(queued).unwrap())
            .await
            .unwrap();

        let mut expected = expected_response(true, body.as_ref());
        expected.truncate(expected.len() - b"0\r\n\r\n".len());
        let mut received = vec![0; expected.len()];
        timeout(Duration::from_millis(250), client.read_exact(&mut received))
            .await
            .expect("SSE chunk must be readable while the producer remains open")
            .unwrap();
        assert_eq!(received, expected);

        tokio::task::spawn_blocking(move || producer.finish().unwrap())
            .await
            .unwrap();
        let mut terminal = [0; 5];
        client.read_exact(&mut terminal).await.unwrap();
        assert_eq!(&terminal, b"0\r\n\r\n");
        server.await.unwrap();
    })
    .await
    .expect("bounded paused-producer HTTP/1 TLS test");
}

#[tokio::test]
async fn http1_plain_response_preserves_exact_wire_bytes() {
    for chunked in [false, true] {
        let body = b"plain positive control".to_vec();
        let expected = expected_response(chunked, &body);
        let mut writer = Vec::new();
        send_response(&mut writer, chunked, body).await.unwrap();
        assert_eq!(writer, expected);
    }
}

struct FlushFailure;

impl AsyncWrite for FlushFailure {
    fn poll_write(
        self: Pin<&mut Self>,
        _: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<io::Result<usize>> {
        Poll::Ready(Ok(data.len()))
    }
    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()))
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        panic!("response completion must not shut down a reusable connection")
    }
}

struct FailOnNthFlush {
    flushes: usize,
    fail_on: usize,
}

impl AsyncWrite for FailOnNthFlush {
    fn poll_write(
        self: Pin<&mut Self>,
        _: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<io::Result<usize>> {
        Poll::Ready(Ok(data.len()))
    }
    fn poll_flush(mut self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.flushes += 1;
        if self.flushes == self.fail_on {
            Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()))
        } else {
            Poll::Ready(Ok(()))
        }
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        panic!("stream flush failure must not shut down through the writer")
    }
}

#[derive(Default)]
struct FlushCounter {
    bytes: Vec<u8>,
    flushes: usize,
}

impl AsyncWrite for FlushCounter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<io::Result<usize>> {
        self.bytes.extend_from_slice(data);
        Poll::Ready(Ok(data.len()))
    }
    fn poll_flush(mut self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.flushes += 1;
        Poll::Ready(Ok(()))
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        panic!("stream batching must not shut down through the writer")
    }
}

#[tokio::test]
async fn http1_buffered_response_propagates_flush_failure() {
    assert_eq!(
        send_response(&mut FlushFailure, false, vec![1])
            .await
            .unwrap_err()
            .kind(),
        io::ErrorKind::BrokenPipe
    );
}

#[tokio::test]
async fn http1_chunked_response_propagates_flush_failure() {
    assert_eq!(
        send_response(&mut FlushFailure, true, vec![1])
            .await
            .unwrap_err()
            .kind(),
        io::ErrorKind::BrokenPipe
    );
}

#[tokio::test]
async fn http1_chunk_flush_failure_closes_the_response_stream() {
    let (producer, mut reader) = response_stream_channel(2);
    let queued = producer.clone();
    tokio::task::spawn_blocking(move || {
        queued
            .write_chunk(Bytes::from_static(b"data: unavailable\n\n"))
            .unwrap();
    })
    .await
    .unwrap();

    let mut writer = FailOnNthFlush {
        flushes: 0,
        fail_on: 2,
    };
    let error = write_http1_chunked_response(
        &mut writer,
        1,
        200,
        &[("Transfer-Encoding".into(), "chunked".into())],
        &mut reader,
    )
    .await
    .unwrap_err();
    assert_eq!(error.kind(), io::ErrorKind::BrokenPipe);
    assert_eq!(writer.flushes, 2);

    tokio::task::spawn_blocking(move || {
        assert!(producer.write_chunk(Bytes::from_static(b"late")).is_err());
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn http1_prequeued_chunks_flush_as_one_completed_batch() {
    let chunks = [
        Bytes::from_static(b"first"),
        Bytes::from_static(b"second"),
        Bytes::from_static(b"third"),
    ];
    let (producer, mut reader) = response_stream_channel(chunks.len() + 1);
    let queued = chunks.clone();
    tokio::task::spawn_blocking(move || {
        for chunk in queued {
            producer.write_chunk(chunk).unwrap();
        }
        producer.finish().unwrap();
    })
    .await
    .unwrap();

    let mut writer = FlushCounter::default();
    write_http1_chunked_response(
        &mut writer,
        1,
        200,
        &[("Transfer-Encoding".into(), "chunked".into())],
        &mut reader,
    )
    .await
    .unwrap();

    let mut expected = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n".to_vec();
    for chunk in chunks {
        expected.extend_from_slice(format!("{:X}\r\n", chunk.len()).as_bytes());
        expected.extend_from_slice(&chunk);
        expected.extend_from_slice(b"\r\n");
    }
    expected.extend_from_slice(b"0\r\n\r\n");
    assert_eq!(writer.bytes, expected);
    assert_eq!(writer.flushes, 2, "headers plus one completed body batch");
}

#[tokio::test]
async fn http1_continuously_ready_chunks_have_a_bounded_flush_batch() {
    const CHUNK_COUNT: usize = 64;
    let chunk = Bytes::from(vec![0x5a; 256]);
    let (producer, mut reader) = response_stream_channel(CHUNK_COUNT + 1);
    let queued = chunk.clone();
    tokio::task::spawn_blocking(move || {
        for _ in 0..CHUNK_COUNT {
            producer.write_chunk(queued.clone()).unwrap();
        }
        producer.finish().unwrap();
    })
    .await
    .unwrap();

    let mut writer = FlushCounter::default();
    write_http1_chunked_response(
        &mut writer,
        1,
        200,
        &[("Transfer-Encoding".into(), "chunked".into())],
        &mut reader,
    )
    .await
    .unwrap();

    assert_eq!(writer.flushes, 3, "headers, bounded batch, and terminal");
    assert_eq!(
        writer.bytes.len(),
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n".len()
            + CHUNK_COUNT * (b"100\r\n".len() + chunk.len() + b"\r\n".len())
            + b"0\r\n\r\n".len()
    );
}
