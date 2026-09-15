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
    let mut header = [0; 9];
    peer.read_exact(&mut header).await.unwrap();
    let length = u32::from_be_bytes([0, header[0], header[1], header[2]]) as usize;
    assert!(
        length <= 1024 * 1024,
        "test peer frame exceeds bounded fixture"
    );
    let mut body = vec![0; length];
    peer.read_exact(&mut body).await.unwrap();
    (header[3], header[4], body)
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
