use std::{
    io,
    pin::Pin,
    task::{Context, Poll},
};

use bytes::BytesMut;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::net::TcpStream;
use tokio_rustls::{client::TlsStream as ClientTlsStream, server::TlsStream as ServerTlsStream};

pub(crate) type IoReadHalf = tokio::io::ReadHalf<IoStream>;
pub(crate) type IoWriteHalf = tokio::io::WriteHalf<IoStream>;

#[derive(Debug)]
pub(crate) enum StreamInner {
    Tcp(TcpStream),
    TlsServer(ServerTlsStream<TcpStream>),
    TlsClient(ClientTlsStream<TcpStream>),
}

#[derive(Debug)]
pub(crate) struct IoStream {
    inner: StreamInner,
    buffered: BytesMut,
    buffered_offset: usize,
}

impl IoStream {
    pub(crate) fn plain(stream: TcpStream) -> Self {
        Self {
            inner: StreamInner::Tcp(stream),
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    pub(crate) fn tls(stream: ServerTlsStream<TcpStream>) -> Self {
        Self {
            inner: StreamInner::TlsServer(stream),
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    pub(crate) fn tls_client(stream: ClientTlsStream<TcpStream>) -> Self {
        Self {
            inner: StreamInner::TlsClient(stream),
            buffered: BytesMut::new(),
            buffered_offset: 0,
        }
    }

    pub(crate) fn is_tls(&self) -> bool {
        matches!(
            self.inner,
            StreamInner::TlsServer(_) | StreamInner::TlsClient(_)
        )
    }

    pub(crate) fn set_nodelay(&self, enabled: bool) -> io::Result<()> {
        match &self.inner {
            StreamInner::Tcp(stream) => stream.set_nodelay(enabled),
            StreamInner::TlsServer(stream) => stream.get_ref().0.set_nodelay(enabled),
            StreamInner::TlsClient(stream) => stream.get_ref().0.set_nodelay(enabled),
        }
    }

    pub(crate) fn negotiated_alpn(&self) -> Option<String> {
        match &self.inner {
            StreamInner::TlsServer(stream) => stream
                .get_ref()
                .1
                .alpn_protocol()
                .map(|bytes| String::from_utf8_lossy(bytes).to_string()),
            StreamInner::TlsClient(stream) => stream
                .get_ref()
                .1
                .alpn_protocol()
                .map(|bytes| String::from_utf8_lossy(bytes).to_string()),
            StreamInner::Tcp(_) => None,
        }
    }

    pub(crate) fn buffer_front(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        if self.buffered_offset < self.buffered.len() {
            let remaining = self.buffered[self.buffered_offset..].to_vec();
            self.buffered.clear();
            self.buffered.extend_from_slice(bytes);
            self.buffered.extend_from_slice(&remaining);
        } else {
            self.buffered.clear();
            self.buffered.extend_from_slice(bytes);
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
            StreamInner::TlsServer(stream) => Pin::new(stream).poll_write(cx, buf),
            StreamInner::TlsClient(stream) => Pin::new(stream).poll_write(cx, buf),
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let me = self.get_mut();
        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_flush(cx),
            StreamInner::TlsServer(stream) => Pin::new(stream).poll_flush(cx),
            StreamInner::TlsClient(stream) => Pin::new(stream).poll_flush(cx),
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let me = self.get_mut();
        match &mut me.inner {
            StreamInner::Tcp(stream) => Pin::new(stream).poll_shutdown(cx),
            StreamInner::TlsServer(stream) => Pin::new(stream).poll_shutdown(cx),
            StreamInner::TlsClient(stream) => Pin::new(stream).poll_shutdown(cx),
        }
    }
}
