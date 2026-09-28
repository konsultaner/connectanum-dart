use super::http2_server_builder;
use bytes::Bytes;
use h2::Reason;
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream};
use tokio::sync::oneshot;
use tokio::time::{timeout, Duration};

async fn send_frame(peer: &mut DuplexStream, kind: u8, flags: u8, id: u32, body: &[u8]) {
    let length = (body.len() as u32).to_be_bytes();
    peer.write_all(&length[1..]).await.unwrap();
    peer.write_all(&[kind, flags]).await.unwrap();
    peer.write_all(&id.to_be_bytes()).await.unwrap();
    peer.write_all(body).await.unwrap();
}

async fn read_frame(peer: &mut DuplexStream) -> (u8, u8, Vec<u8>) {
    let (kind, flags, _, body) = read_wire_frame(peer).await;
    (kind, flags, body)
}

async fn read_wire_frame(peer: &mut DuplexStream) -> (u8, u8, u32, Vec<u8>) {
    let mut header = [0; 9];
    peer.read_exact(&mut header).await.unwrap();
    let length = u32::from_be_bytes([0, header[0], header[1], header[2]]) as usize;
    assert!(
        length <= 1024 * 1024,
        "test peer frame exceeds bounded fixture"
    );
    let mut body = vec![0; length];
    peer.read_exact(&mut body).await.unwrap();
    let stream_id = u32::from_be_bytes(header[5..9].try_into().unwrap()) & 0x7fff_ffff;
    (header[3], header[4], stream_id, body)
}

#[tokio::test]
async fn http2_advertises_production_limits_and_connection_receive_window() {
    let (io, mut peer) = tokio::io::duplex(64 * 1024);
    let (ready_tx, ready_rx) = oneshot::channel();
    let server = tokio::spawn(async move {
        let mut connection = http2_server_builder()
            .handshake::<_, Bytes>(io)
            .await
            .unwrap();
        let mut ready_tx = Some(ready_tx);
        while let Some(request) = std::future::poll_fn(|cx| {
            let result = connection.poll_accept(cx);
            // h2 flushes pending flow-control updates when receive polling
            // becomes pending, which may happen after a queued PING ACK.
            if result.is_pending() {
                if let Some(tx) = ready_tx.take() {
                    let _ = tx.send(());
                }
            }
            result
        })
        .await
        {
            panic!("handshake-only peer unexpectedly opened a stream: {request:?}");
        }
    });
    let result = timeout(Duration::from_secs(5), async {
        peer.write_all(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
            .await
            .unwrap();
        send_frame(&mut peer, 4, 0, 0, &[]).await;
        ready_rx.await.unwrap();
        send_frame(&mut peer, 6, 0, 0, b"tuning!!").await;

        let mut settings = std::collections::BTreeMap::new();
        let mut connection_window = 65_535u32;
        let mut settings_ack = false;
        let mut barrier_ack = false;
        for _ in 0..16 {
            let (kind, flags, stream_id, payload) = read_wire_frame(&mut peer).await;
            assert_eq!(stream_id, 0, "handshake frames must be connection-level");
            match (kind, flags) {
                (4, 0) => {
                    assert_eq!(payload.len() % 6, 0, "malformed SETTINGS payload");
                    for setting in payload.chunks_exact(6) {
                        let id = u16::from_be_bytes(setting[..2].try_into().unwrap());
                        let value = u32::from_be_bytes(setting[2..].try_into().unwrap());
                        assert!(settings.insert(id, value).is_none());
                    }
                    send_frame(&mut peer, 4, 1, 0, &[]).await;
                }
                (4, 1) => {
                    assert!(payload.is_empty());
                    settings_ack = true;
                }
                (8, 0) => {
                    assert_eq!(payload.len(), 4);
                    let increment = u32::from_be_bytes(payload.try_into().unwrap()) & 0x7fff_ffff;
                    assert!(increment > 0);
                    connection_window = connection_window.checked_add(increment).unwrap();
                }
                (6, 1) => {
                    assert_eq!(payload, b"tuning!!");
                    barrier_ack = true;
                    break;
                }
                _ => panic!("unexpected handshake frame type={kind}, flags={flags}"),
            }
        }
        assert!(
            barrier_ack,
            "peer must acknowledge the bounded PING barrier"
        );
        assert!(settings_ack, "peer SETTINGS must be acknowledged");
        // Independent wire expectations: importing the tuning constants would
        // let a mutation change both the implementation and the expected value.
        assert_eq!(settings.get(&3), Some(&1024), "concurrent streams");
        assert_eq!(settings.get(&4), Some(&8_388_608), "stream receive window");
        assert_eq!(settings.get(&5), Some(&1_048_576), "maximum frame size");
        assert_eq!(settings.get(&6), Some(&16_777_216), "header list limit");
        assert_eq!(connection_window, 67_108_864, "connection receive window");
    })
    .await;
    server.abort();
    assert!(server.await.unwrap_err().is_cancelled());
    result.expect("bounded HTTP/2 tuning fixture timed out");
}

async fn check_empty_data(padded: bool, flood: bool) {
    timeout(Duration::from_secs(5), async {
        let (io, mut peer) = tokio::io::duplex(64 * 1024);
        let (body_tx, body_rx) = oneshot::channel();
        let server = tokio::spawn(async move {
            // Use the production builder, including its flow-control tuning.
            let mut connection = http2_server_builder()
                .handshake::<_, Bytes>(io)
                .await
                .unwrap();
            let (request, respond) = connection.accept().await.unwrap().unwrap();
            body_tx.send((request.into_body(), respond)).unwrap();
            while let Some(request) = connection.accept().await {
                if let Err(error) = request {
                    return Some(error);
                }
                panic!("unexpected second request");
            }
            None
        });

        peer.write_all(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
            .await
            .unwrap();
        send_frame(&mut peer, 4, 0, 0, &[]).await;
        // HPACK static entries: POST, http, /; literal :authority localhost.
        send_frame(&mut peer, 1, 4, 1, b"\x83\x86\x84\x01\x09localhost").await;
        let (mut body, _respond) = body_rx.await.unwrap();
        let (flags, payload): (u8, &[u8]) = if padded { (8, &[1, 0]) } else { (0, &[]) };
        let frame_count = if flood { 101 } else { 49 };
        for _ in 0..frame_count {
            send_frame(&mut peer, 0, flags, 1, payload).await;
        }
        if !flood {
            send_frame(&mut peer, 0, 0, 1, b"hello").await;
            // An empty terminal DATA frame must still finish the body.
            send_frame(&mut peer, 0, 1, 1, &[]).await;
        }
        send_frame(&mut peer, 6, 0, 0, b"barrier!").await;

        // A PING ACK proves the frames were processed while the body was NOT
        // being drained. A flood must instead produce a bounded GOAWAY.
        loop {
            let (kind, flags, payload) = read_frame(&mut peer).await;
            if kind == 4 && flags == 0 {
                send_frame(&mut peer, 4, 1, 0, &[]).await;
            } else if kind == 7 {
                assert!(
                    flood,
                    "legitimate empty frames must not close the connection"
                );
                assert!(payload.len() >= 8);
                let reason = u32::from_be_bytes(payload[4..8].try_into().unwrap());
                assert_eq!(Reason::from(reason), Reason::ENHANCE_YOUR_CALM);
                assert_eq!(&payload[8..], b"too_many_data_frames");
                let error = server.await.unwrap().expect("flood must fail closed");
                assert_eq!(error.reason(), Some(Reason::ENHANCE_YOUR_CALM));
                return;
            } else if kind == 6 && flags == 1 && payload == b"barrier!" {
                assert!(
                    !flood,
                    "empty DATA flood was accepted while body was paused"
                );
                break;
            }
        }

        let mut nonempty = Vec::new();
        let mut empty_chunks = 0;
        while let Some(chunk) = body.data().await {
            let chunk = chunk.unwrap();
            body.flow_control().release_capacity(chunk.len()).unwrap();
            if chunk.is_empty() {
                empty_chunks += 1;
            } else {
                nonempty.push(chunk);
            }
        }
        assert_eq!(nonempty, vec![Bytes::from_static(b"hello")]);
        assert!(
            empty_chunks <= 1,
            "nonterminal empty DATA was queued for the application"
        );
        server.abort();
        assert!(server.await.unwrap_err().is_cancelled());
    })
    .await
    .expect("bounded HTTP/2 security fixture timed out");
}

#[tokio::test]
async fn http2_discards_empty_data_while_body_is_paused() {
    check_empty_data(false, false).await;
}

#[tokio::test]
async fn http2_discards_padded_empty_data_and_preserves_end_stream() {
    check_empty_data(true, false).await;
}

#[tokio::test]
async fn http2_rejects_empty_data_flood_while_body_is_paused() {
    check_empty_data(false, true).await;
}

#[tokio::test]
async fn http2_rejects_padded_empty_data_flood_while_body_is_paused() {
    check_empty_data(true, true).await;
}
