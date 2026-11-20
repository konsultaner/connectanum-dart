use super::*;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::io::ReadBuf;

struct FrameReadProbe {
    wire: Vec<u8>,
    offset: usize,
    payload_start: usize,
    initialized_payload_bytes: Option<usize>,
    yielded: bool,
}

impl AsyncRead for FrameReadProbe {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if this.offset >= this.payload_start {
            this.initialized_payload_bytes
                .get_or_insert(buffer.initialized().len());
            if !this.yielded {
                this.yielded = true;
                cx.waker().wake_by_ref();
                return Poll::Pending;
            }
        }
        let end = this
            .wire
            .len()
            .min(this.offset + buffer.remaining().min(4093));
        buffer.put_slice(&this.wire[this.offset..end]);
        this.offset = end;
        Poll::Ready(Ok(()))
    }
}

fn frame(payload: &[u8], masked: bool) -> (Vec<u8>, usize) {
    let mut wire = vec![0x82];
    let flag = if masked { 0x80 } else { 0 };
    match payload.len() {
        0..=125 => wire.push(flag | payload.len() as u8),
        126..=65535 => {
            wire.push(flag | 126);
            wire.extend_from_slice(&(payload.len() as u16).to_be_bytes());
        }
        _ => {
            wire.push(flag | 127);
            wire.extend_from_slice(&(payload.len() as u64).to_be_bytes());
        }
    }
    let mask = [0x13, 0x57, 0x9b, 0xdf];
    if masked {
        wire.extend_from_slice(&mask);
    }
    let start = wire.len();
    wire.extend(payload.iter().enumerate().map(
        |(i, value)| {
            if masked {
                value ^ mask[i & 3]
            } else {
                *value
            }
        },
    ));
    (wire, start)
}

#[tokio::test]
async fn fresh_websocket_payload_avoids_full_buffer_initialization_and_next_frame_read() {
    for masked in [false, true] {
        for len in [1, 125, 126, 4097, 131071] {
            let payload: Vec<u8> = (0..len).map(|i| (i % 251) as u8).collect();
            let (mut wire, payload_start) = frame(&payload, masked);
            let frame_end = wire.len();
            let (next, _) = frame(b"next", masked);
            wire.extend(next);
            let mut reader = FrameReadProbe {
                wire,
                offset: 0,
                payload_start,
                initialized_payload_bytes: None,
                yielded: false,
            };
            let pool = Arc::new(WebSocketBufferPool::default());
            let received = read_websocket_frame_mode(&mut reader, &pool, masked)
                .await
                .unwrap();
            let WebSocketFrame::Data { payload: first, .. } = received else {
                panic!("expected data frame");
            };
            assert_eq!(first.as_ref(), payload, "len={len} masked={masked}");
            assert_eq!(reader.offset, frame_end, "read consumed the next frame");
            assert_eq!(
                reader.initialized_payload_bytes,
                Some(0),
                "the full payload buffer was initialized before being overwritten"
            );
            let next = read_websocket_frame_mode(&mut reader, &pool, masked)
                .await
                .unwrap();
            let WebSocketFrame::Data {
                payload: second, ..
            } = next
            else {
                panic!("expected next data frame");
            };
            assert_eq!(second.as_ref(), b"next");
            assert_eq!(first.as_ref(), payload, "retained bytes changed");
        }
    }
}

#[tokio::test]
async fn truncated_websocket_payload_never_exposes_or_reuses_stale_bytes() {
    for masked in [false, true] {
        let pool = Arc::new(WebSocketBufferPool::default());
        let mut stale = pool.acquire(131071);
        stale.as_mut_slice().fill(0xee);
        drop(stale);
        let (mut wire, start) = frame(&vec![0x5a; 8193], masked);
        wire.truncate(start + 17);
        let error = read_websocket_frame_mode(&mut wire.as_slice(), &pool, masked)
            .await
            .expect_err("truncated payload accepted");
        assert!(error.is_peer_disconnect());
        assert_eq!(pool.available_buffers(), 1, "partial read leaked its owner");
        let (wire, _) = frame(b"new", masked);
        let received = read_websocket_frame_mode(&mut wire.as_slice(), &pool, masked)
            .await
            .unwrap();
        let WebSocketFrame::Data { payload, .. } = received else {
            panic!("expected fresh data frame");
        };
        assert_eq!(payload.as_ref(), b"new");
        assert_eq!(pool.available_buffers(), 0);
        drop(payload);
        assert_eq!(pool.available_buffers(), 1);
    }
}
