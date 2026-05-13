use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Instant;

use bytes::Bytes;
use thiserror::Error;
use tokio::sync::mpsc;

/// Default in-flight chunk capacity for HTTP response streams.
pub const RESPONSE_STREAM_BUFFER: usize = 8;

/// Events emitted by a streaming HTTP response.
#[derive(Debug)]
pub enum ResponseStreamFrame {
    Chunk { bytes: Bytes, queued_at: Instant },
    Finished { queued_at: Instant },
}

/// Errors that can occur while interacting with a streaming HTTP response.
#[derive(Debug, Error)]
pub enum ResponseStreamError {
    #[error("response stream closed")]
    Closed,
}

/// Writer exposed to Dart so chunks can be forwarded into the native runtime.
#[derive(Clone)]
pub struct ResponseStreamWriter {
    tx: mpsc::Sender<ResponseStreamFrame>,
    closed: Arc<AtomicBool>,
}

impl ResponseStreamWriter {
    pub fn write_chunk(&self, chunk: Bytes) -> Result<(), ResponseStreamError> {
        if chunk.is_empty() {
            return Ok(());
        }
        if self.closed.load(Ordering::SeqCst) {
            return Err(ResponseStreamError::Closed);
        }
        self.tx
            .blocking_send(ResponseStreamFrame::Chunk {
                bytes: chunk,
                queued_at: Instant::now(),
            })
            .map_err(|_| {
                self.closed.store(true, Ordering::SeqCst);
                ResponseStreamError::Closed
            })
    }

    pub fn finish(&self) -> Result<(), ResponseStreamError> {
        if self.closed.swap(true, Ordering::SeqCst) {
            return Ok(());
        }
        self.tx
            .blocking_send(ResponseStreamFrame::Finished {
                queued_at: Instant::now(),
            })
            .map_err(|_| ResponseStreamError::Closed)
    }

    pub fn abort(&self) {
        self.closed.store(true, Ordering::SeqCst);
    }
}

/// Reader owned by the native HTTP/2+HTTP/3 send tasks.
#[derive(Debug)]
pub struct ResponseStreamReader {
    rx: mpsc::Receiver<ResponseStreamFrame>,
    opened_at: Instant,
}

impl ResponseStreamReader {
    pub async fn next(&mut self) -> Result<ResponseStreamFrame, ResponseStreamError> {
        self.rx.recv().await.ok_or(ResponseStreamError::Closed)
    }

    pub fn opened_at(&self) -> Instant {
        self.opened_at
    }

    pub fn close(&mut self) {
        self.rx.close();
    }
}

pub fn response_stream_channel(capacity: usize) -> (ResponseStreamWriter, ResponseStreamReader) {
    let (tx, rx) = mpsc::channel(capacity.max(1));
    let opened_at = Instant::now();
    let writer = ResponseStreamWriter {
        tx,
        closed: Arc::new(AtomicBool::new(false)),
    };
    let reader = ResponseStreamReader { rx, opened_at };
    (writer, reader)
}
