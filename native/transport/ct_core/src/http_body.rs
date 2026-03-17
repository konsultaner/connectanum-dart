use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    time::Duration,
};

use bytes::Bytes;
use tokio::{
    io::AsyncReadExt,
    sync::oneshot::{self, Receiver},
    time,
};

use crate::io_stream::IoReadHalf;
use crate::HttpBodySlice;

const STREAMING_CHUNK_SIZE: usize = 64 * 1024;

#[derive(Debug)]
pub struct StreamingBodyState {
    chunks: Mutex<VecDeque<StreamingChunk>>,
    ready: Condvar,
    last_chunk: Mutex<Option<Bytes>>,
    finished: AtomicBool,
    finish_requested: AtomicBool,
    total_len: AtomicUsize,
    error: Mutex<Option<String>>,
}

#[derive(Debug)]
struct StreamingChunk {
    data: Bytes,
    offset: usize,
}

impl StreamingChunk {
    fn new(data: Bytes) -> Self {
        Self { data, offset: 0 }
    }

    fn remaining(&self) -> usize {
        self.data.len().saturating_sub(self.offset)
    }
}

#[derive(Debug)]
pub struct Http1BodyReclaim {
    receiver: Receiver<IoReadHalf>,
}

impl Http1BodyReclaim {
    pub async fn wait(self) -> Result<IoReadHalf, oneshot::error::RecvError> {
        self.receiver.await
    }
}

#[derive(Debug)]
pub enum StreamingError {
    Io(String),
}

impl StreamingBodyState {
    pub fn new(total_len: usize) -> Arc<Self> {
        Arc::new(Self {
            chunks: Mutex::new(VecDeque::new()),
            ready: Condvar::new(),
            last_chunk: Mutex::new(None),
            finished: AtomicBool::new(false),
            finish_requested: AtomicBool::new(false),
            total_len: AtomicUsize::new(total_len),
            error: Mutex::new(None),
        })
    }

    pub fn total_len(&self) -> usize {
        self.total_len.load(Ordering::SeqCst)
    }

    pub fn extend_total_len(&self, delta: usize) {
        if delta == 0 {
            return;
        }
        self.total_len.fetch_add(delta, Ordering::SeqCst);
    }

    pub fn enqueue_prefix(&self, prefix: Bytes) {
        self.enqueue_bytes(prefix);
    }

    pub fn enqueue_vec(&self, bytes: Vec<u8>) {
        self.enqueue_bytes(Bytes::from(bytes));
    }

    pub fn enqueue_bytes(&self, bytes: Bytes) {
        if bytes.is_empty() {
            return;
        }
        {
            let mut chunks = self.chunks.lock().unwrap();
            chunks.push_back(StreamingChunk::new(bytes));
        }
        self.ready.notify_all();
    }

    pub fn request_finish(&self) {
        self.finish_requested.store(true, Ordering::SeqCst);
        self.ready.notify_all();
    }

    pub fn finish_requested(&self) -> bool {
        self.finish_requested.load(Ordering::SeqCst)
    }

    pub fn mark_error(&self, message: String) {
        *self.error.lock().unwrap() = Some(message);
        self.mark_finished();
    }

    pub fn mark_finished(&self) {
        self.finished.store(true, Ordering::SeqCst);
        self.ready.notify_all();
    }

    pub fn take_slice(&self, len: usize) -> Result<Option<HttpBodySlice>, StreamingError> {
        let mut guard = self.chunks.lock().unwrap();
        loop {
            if let Some(chunk) = guard.front_mut() {
                let available = chunk.remaining();
                if available == 0 {
                    guard.pop_front();
                    continue;
                }
                let request_len = len.max(1).min(available);
                let ptr = unsafe { chunk.data.as_ptr().add(chunk.offset) };
                chunk.offset += request_len;
                if chunk.offset >= chunk.data.len() {
                    let finished_chunk = guard.pop_front().unwrap();
                    drop(guard);
                    *self.last_chunk.lock().unwrap() = Some(finished_chunk.data);
                } else {
                    let bytes = chunk.data.clone();
                    drop(guard);
                    *self.last_chunk.lock().unwrap() = Some(bytes);
                }
                return Ok(Some(HttpBodySlice {
                    ptr,
                    len: request_len,
                }));
            }

            if self.finished.load(Ordering::SeqCst) {
                if let Some(err) = self.error.lock().unwrap().clone() {
                    return Err(StreamingError::Io(err));
                }
                return Ok(None);
            }

            guard = self.ready.wait(guard).unwrap();
        }
    }
}

pub fn spawn_http1_streaming_body(
    prefix: Bytes,
    reader: IoReadHalf,
    remaining: usize,
    read_timeout: Duration,
) -> (Arc<StreamingBodyState>, Http1BodyReclaim) {
    let total_len = prefix.len() + remaining;
    let state = StreamingBodyState::new(total_len);
    state.enqueue_prefix(prefix);
    let (tx, rx) = oneshot::channel();
    tokio::spawn(run_http1_stream_reader(
        state.clone(),
        reader,
        remaining,
        read_timeout,
        tx,
    ));
    (state, Http1BodyReclaim { receiver: rx })
}

async fn run_http1_stream_reader(
    state: Arc<StreamingBodyState>,
    mut reader: IoReadHalf,
    mut remaining: usize,
    read_timeout: Duration,
    reclaim: oneshot::Sender<IoReadHalf>,
) {
    while remaining > 0 {
        let request = remaining.min(STREAMING_CHUNK_SIZE);
        let mut chunk = bytes::BytesMut::with_capacity(request);
        chunk.resize(request, 0);
        match time::timeout(read_timeout, reader.read(&mut chunk[..])).await {
            Ok(Ok(0)) => {
                eprintln!("http/1 body reader: connection closed before body drained");
                state.mark_error("connection closed before body drained".into());
                break;
            }
            Ok(Ok(read)) => {
                remaining = remaining.saturating_sub(read);
                if !state.finish_requested() {
                    chunk.truncate(read);
                    state.enqueue_bytes(chunk.freeze());
                }
            }
            Ok(Err(err)) => {
                eprintln!("http/1 body reader: read failed: {}", err);
                state.mark_error(format!("http/1 body read failed: {}", err));
                break;
            }
            Err(_) => {
                eprintln!("http/1 body reader: idle timeout");
                state.mark_error("http/1 body read timed out".into());
                break;
            }
        }
    }
    state.mark_finished();
    if remaining == 0 {
        let _ = reclaim.send(reader);
    }
}

#[cfg(test)]
mod tests {
    use super::{spawn_http1_streaming_body, StreamingBodyState};
    use crate::io_stream::IoStream;
    use bytes::Bytes;
    use std::time::Duration;
    use tokio::{io::AsyncWriteExt, net::TcpListener};

    #[test]
    fn streaming_body_state_reports_length() {
        let state = StreamingBodyState::new(42);
        assert_eq!(state.total_len(), 42);
    }

    #[test]
    fn streaming_body_state_produces_chunks_in_order() {
        let prefix = Bytes::copy_from_slice(&[9, 9]);
        let payload = vec![1, 2, 3, 4];
        let state = StreamingBodyState::new(prefix.len() + payload.len());
        state.enqueue_prefix(prefix);
        state.enqueue_vec(payload);
        let slice = state.take_slice(3).unwrap().unwrap();
        assert_eq!(
            unsafe { std::slice::from_raw_parts(slice.ptr, slice.len) },
            &[9, 9]
        );
        let next = state.take_slice(3).unwrap().unwrap();
        assert_eq!(
            unsafe { std::slice::from_raw_parts(next.ptr, next.len) },
            &[1, 2, 3]
        );
        let final_chunk = state.take_slice(3).unwrap().unwrap();
        assert_eq!(
            unsafe { std::slice::from_raw_parts(final_chunk.ptr, final_chunk.len) },
            &[4]
        );
        state.mark_finished();
        assert!(state.take_slice(3).unwrap().is_none());
    }

    #[test]
    fn streaming_body_state_reuses_prefix_bytes_without_copy() {
        let prefix = Bytes::from(vec![7u8, 8, 9]);
        let ptr = prefix.as_ptr();
        let state = StreamingBodyState::new(prefix.len());
        state.enqueue_prefix(prefix);
        let slice = state.take_slice(8).unwrap().unwrap();
        assert_eq!(slice.ptr, ptr);
        assert_eq!(
            unsafe { std::slice::from_raw_parts(slice.ptr, slice.len) },
            &[7, 8, 9]
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn http1_stream_reader_reclaims_after_completion() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client = tokio::spawn(async move {
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            stream.write_all(b"6789").await.unwrap();
            stream.flush().await.unwrap();
        });

        let (socket, _) = listener.accept().await.unwrap();
        let (read_half, _write_half) = tokio::io::split(IoStream::plain(socket));
        let prefix = Bytes::from_static(b"12345");
        let (state, reclaim) =
            spawn_http1_streaming_body(prefix.clone(), read_half, 4, Duration::from_millis(200));

        let reader_state = state.clone();
        let reader = tokio::task::spawn_blocking(move || {
            let mut collected = Vec::new();
            loop {
                match reader_state.take_slice(8) {
                    Ok(Some(slice)) => unsafe {
                        let data = std::slice::from_raw_parts(slice.ptr, slice.len);
                        collected.extend_from_slice(data);
                    },
                    Ok(None) => break,
                    Err(err) => panic!("stream reader error: {:?}", err),
                }
            }
            collected
        });

        client.await.unwrap();
        let bytes = reader.await.unwrap();
        assert_eq!(bytes, b"123456789");
        let _read_half = reclaim.wait().await.expect("read half returned");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn http1_stream_reader_times_out_when_client_stalls() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let _client = tokio::spawn(async move {
            let _stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            tokio::time::sleep(Duration::from_millis(200)).await;
        });

        let (socket, _) = listener.accept().await.unwrap();
        let (read_half, _write_half) = tokio::io::split(IoStream::plain(socket));
        let prefix = Bytes::from_static(b"");
        let (state, reclaim) =
            spawn_http1_streaming_body(prefix, read_half, 8, Duration::from_millis(100));

        let reader_state = state.clone();
        let reader = tokio::task::spawn_blocking(move || match reader_state.take_slice(4) {
            Ok(_) => Ok(()),
            Err(err) => Err(err),
        });
        let result = reader.await.unwrap();
        assert!(result.is_err(), "expected streaming error on timeout");
        assert!(
            reclaim.wait().await.is_err(),
            "connection should close on timeout"
        );
    }
}
