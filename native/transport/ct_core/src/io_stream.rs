use std::{
    fmt, io,
    pin::Pin,
    task::{Context, Poll},
};

#[cfg(any(target_os = "linux", target_os = "macos"))]
use std::os::fd::{AsFd, OwnedFd};

use bytes::BytesMut;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::net::TcpStream;
use tokio_rustls::{client::TlsStream as ClientTlsStream, server::TlsStream as ServerTlsStream};

#[cfg(target_os = "linux")]
type ServerKtlsSession = rustls::kernel::KernelConnection<rustls::server::ServerConnectionData>;
#[cfg(target_os = "linux")]
type ServerKtlsStream = ktls_stream::Stream<TcpStream, ServerKtlsSession>;

pub(crate) type IoReadHalf = tokio::io::ReadHalf<IoStream>;
pub(crate) type IoWriteHalf = tokio::io::WriteHalf<IoStream>;

#[cfg(test)]
thread_local! {
    // Test-local observation keeps exact assertions independent of other
    // connections' process-wide counters on parallel test threads.
    static TEST_INPUT_COPIES: std::cell::Cell<(u64, u64)> = const {
        std::cell::Cell::new((0, 0))
    };
}

fn record_front_copy(bytes: usize) {
    super::transport_copy_metrics()
        .io_buffer_front_copy_bytes_total
        .fetch_add(bytes as u64, std::sync::atomic::Ordering::Relaxed);
    #[cfg(test)]
    TEST_INPUT_COPIES.with(|value| {
        let (front, read) = value.get();
        value.set((front + bytes as u64, read));
    });
}

fn record_replay_copy(bytes: usize) {
    super::transport_copy_metrics()
        .io_buffered_read_copy_bytes_total
        .fetch_add(bytes as u64, std::sync::atomic::Ordering::Relaxed);
    #[cfg(test)]
    TEST_INPUT_COPIES.with(|value| {
        let (front, read) = value.get();
        value.set((front, read + bytes as u64));
    });
}

pub(crate) enum StreamInner {
    Tcp(TcpStream),
    TlsServer(ServerTlsStream<TcpStream>),
    TlsClient(ClientTlsStream<TcpStream>),
    #[cfg(target_os = "linux")]
    KtlsServer(ServerKtlsStream),
}

pub(crate) struct IoStream {
    inner: StreamInner,
    negotiated_alpn: Option<String>,
    buffered: BytesMut,
    buffered_offset: usize,
}

impl fmt::Debug for StreamInner {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Tcp(_) => f.write_str("Tcp"),
            Self::TlsServer(_) => f.write_str("TlsServer"),
            Self::TlsClient(_) => f.write_str("TlsClient"),
            #[cfg(target_os = "linux")]
            Self::KtlsServer(_) => f.write_str("KtlsServer"),
        }
    }
}

impl fmt::Debug for IoStream {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("IoStream")
            .field("inner", &self.inner)
            .field("negotiated_alpn", &self.negotiated_alpn)
            .field("buffered_len", &self.buffered.len())
            .field("buffered_offset", &self.buffered_offset)
            .finish()
    }
}

impl IoStream {
    pub(crate) fn plain(stream: TcpStream) -> Self {
        Self {
            inner: StreamInner::Tcp(stream),
            negotiated_alpn: None,
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    pub(crate) fn tls(stream: ServerTlsStream<TcpStream>) -> Self {
        let negotiated_alpn = stream
            .get_ref()
            .1
            .alpn_protocol()
            .map(|bytes| String::from_utf8_lossy(bytes).to_string());
        Self {
            inner: StreamInner::TlsServer(stream),
            negotiated_alpn,
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    pub(crate) fn tls_client(stream: ClientTlsStream<TcpStream>) -> Self {
        let negotiated_alpn = stream
            .get_ref()
            .1
            .alpn_protocol()
            .map(|bytes| String::from_utf8_lossy(bytes).to_string());
        Self {
            inner: StreamInner::TlsClient(stream),
            negotiated_alpn,
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    #[cfg(target_os = "linux")]
    pub(crate) fn ktls_server(stream: ServerKtlsStream, negotiated_alpn: Option<String>) -> Self {
        Self {
            inner: StreamInner::KtlsServer(stream),
            negotiated_alpn,
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    pub(crate) fn set_nodelay(&self, enabled: bool) -> io::Result<()> {
        match &self.inner {
            StreamInner::Tcp(stream) => stream.set_nodelay(enabled),
            StreamInner::TlsServer(stream) => stream.get_ref().0.set_nodelay(enabled),
            StreamInner::TlsClient(stream) => stream.get_ref().0.set_nodelay(enabled),
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(_) => Ok(()),
        }
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    pub(crate) fn try_clone_plain_fd(&self) -> io::Result<Option<OwnedFd>> {
        match &self.inner {
            StreamInner::Tcp(stream) => stream.as_fd().try_clone_to_owned().map(Some),
            _ => Ok(None),
        }
    }

    pub(crate) fn negotiated_alpn(&self) -> Option<String> {
        self.negotiated_alpn.clone()
    }

    pub(crate) fn buffer_front(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        if self.buffered_offset < self.buffered.len() {
            let remaining = &self.buffered[self.buffered_offset..];
            let mut combined = BytesMut::with_capacity(bytes.len() + remaining.len());
            combined.extend_from_slice(bytes);
            record_front_copy(bytes.len());
            combined.extend_from_slice(remaining);
            record_front_copy(remaining.len());
            self.buffered = combined;
        } else {
            self.buffered.clear();
            self.buffered.extend_from_slice(bytes);
            record_front_copy(bytes.len());
        }
        self.buffered_offset = 0;
    }
}

impl AsyncRead for IoStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let me = self.get_mut();
        if me.buffered_offset < me.buffered.len() {
            let remaining = &me.buffered[me.buffered_offset..];
            let to_copy = remaining.len().min(buf.remaining());
            buf.put_slice(&remaining[..to_copy]);
            record_replay_copy(to_copy);
            me.buffered_offset += to_copy;
            if me.buffered_offset >= me.buffered.len() {
                me.buffered.clear();
                me.buffered_offset = 0;
            }
            return Poll::Ready(Ok(()));
        }

        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_read(cx, buf),
            StreamInner::TlsServer(stream) => Pin::new(stream).poll_read(cx, buf),
            StreamInner::TlsClient(stream) => Pin::new(stream).poll_read(cx, buf),
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(stream) => Pin::new(stream).poll_read(cx, buf),
        }
    }
}

impl AsyncWrite for IoStream {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize, io::Error>> {
        let me = self.get_mut();
        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_write(cx, buf),
            StreamInner::TlsServer(stream) => {
                let result = Pin::new(stream).poll_write(cx, buf);
                if let Poll::Ready(Ok(written)) = &result {
                    super::record_tls_plaintext_accepted(*written);
                }
                result
            }
            StreamInner::TlsClient(stream) => {
                let result = Pin::new(stream).poll_write(cx, buf);
                if let Poll::Ready(Ok(written)) = &result {
                    super::record_tls_plaintext_accepted(*written);
                }
                result
            }
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(stream) => Pin::new(stream).poll_write(cx, buf),
        }
    }

    fn poll_write_vectored(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bufs: &[io::IoSlice<'_>],
    ) -> Poll<Result<usize, io::Error>> {
        let me = self.get_mut();
        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_write_vectored(cx, bufs),
            StreamInner::TlsServer(stream) => {
                let result = Pin::new(stream).poll_write_vectored(cx, bufs);
                if let Poll::Ready(Ok(written)) = &result {
                    super::record_tls_plaintext_accepted(*written);
                }
                result
            }
            StreamInner::TlsClient(stream) => {
                let result = Pin::new(stream).poll_write_vectored(cx, bufs);
                if let Poll::Ready(Ok(written)) = &result {
                    super::record_tls_plaintext_accepted(*written);
                }
                result
            }
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(stream) => Pin::new(stream).poll_write_vectored(cx, bufs),
        }
    }

    fn is_write_vectored(&self) -> bool {
        match &self.inner {
            StreamInner::Tcp(stream) => stream.is_write_vectored(),
            StreamInner::TlsServer(stream) => stream.is_write_vectored(),
            StreamInner::TlsClient(stream) => stream.is_write_vectored(),
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(stream) => stream.is_write_vectored(),
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let me = self.get_mut();
        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_flush(cx),
            StreamInner::TlsServer(stream) => Pin::new(stream).poll_flush(cx),
            StreamInner::TlsClient(stream) => Pin::new(stream).poll_flush(cx),
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(stream) => Pin::new(stream).poll_flush(cx),
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let me = self.get_mut();
        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_shutdown(cx),
            StreamInner::TlsServer(stream) => Pin::new(stream).poll_shutdown(cx),
            StreamInner::TlsClient(stream) => Pin::new(stream).poll_shutdown(cx),
            #[cfg(target_os = "linux")]
            StreamInner::KtlsServer(stream) => Pin::new(stream).poll_shutdown(cx),
        }
    }
}

#[cfg(test)]
mod copy_tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    async fn pair() -> (IoStream, TcpStream) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let (client, server) = tokio::join!(TcpStream::connect(address), listener.accept());
        (IoStream::plain(server.unwrap().0), client.unwrap())
    }

    #[tokio::test(flavor = "current_thread")]
    async fn prefetched_input_counts_each_staging_and_replay_copy_once() {
        let (mut stream, mut peer) = pair().await;
        TEST_INPUT_COPIES.with(|value| value.set((0, 0)));
        let before = super::super::transport_copy_metrics_snapshot();
        stream.buffer_front(b"abc");
        let mut first = [0; 1];
        stream.read_exact(&mut first).await.unwrap();
        assert_eq!(&first, b"a");
        stream.buffer_front(b"de");
        peer.write_all(b"fg").await.unwrap();
        let mut rest = [0; 6];
        stream.read_exact(&mut rest).await.unwrap();
        assert_eq!(&rest, b"debcfg");
        // Three initial bytes, then two new bytes plus two unread bytes.
        assert_eq!(TEST_INPUT_COPIES.with(|value| value.get()), (7, 5));
        let after = super::super::transport_copy_metrics_snapshot();
        assert!(
            after.io_buffer_front_copy_bytes_total - before.io_buffer_front_copy_bytes_total >= 7
        );
        assert!(
            after.io_buffered_read_copy_bytes_total - before.io_buffered_read_copy_bytes_total >= 5
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn empty_prefetch_and_zero_capacity_read_do_not_copy() {
        let (mut stream, _peer) = pair().await;
        TEST_INPUT_COPIES.with(|value| value.set((0, 0)));
        stream.buffer_front(b"");
        stream.buffer_front(b"abc");
        stream.buffer_front(b"");
        assert_eq!(stream.read(&mut []).await.unwrap(), 0);
        assert_eq!(TEST_INPUT_COPIES.with(|value| value.get()), (3, 0));
        let mut bytes = [0; 3];
        stream.read_exact(&mut bytes).await.unwrap();
        assert_eq!(&bytes, b"abc");
        assert_eq!(TEST_INPUT_COPIES.with(|value| value.get()), (3, 3));
    }
}
