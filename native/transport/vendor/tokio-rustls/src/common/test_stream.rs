#![cfg(any(feature = "aws_lc_rs", feature = "ring"))]

use std::io::{self, Cursor, Read, Write};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use futures_util::future::poll_fn;
use futures_util::task::noop_waker_ref;
use rustls::pki_types::ServerName;
use rustls::{ClientConnection, Connection, ServerConnection};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};

use super::Stream;

struct Good<'a>(&'a mut Connection);

impl AsyncRead for Good<'_> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let mut buf2 = buf.initialize_unfilled();

        Poll::Ready(match self.0.write_tls(buf2.by_ref()) {
            Ok(n) => {
                buf.advance(n);
                Ok(())
            }
            Err(err) => Err(err),
        })
    }
}

impl AsyncWrite for Good<'_> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        mut buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let len = self.0.read_tls(buf.by_ref())?;
        self.0
            .process_new_packets()
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
        Poll::Ready(Ok(len))
    }

    fn poll_flush(mut self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.0
            .process_new_packets()
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.0.send_close_notify();
        dbg!("sent close notify");
        self.poll_flush(cx)
    }
}

struct Pending;

impl AsyncRead for Pending {
    fn poll_read(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        _: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        Poll::Pending
    }
}

impl AsyncWrite for Pending {
    fn poll_write(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        _buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Poll::Pending
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

struct Expected(Cursor<Vec<u8>>);

impl AsyncRead for Expected {
    fn poll_read(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let n = std::io::Read::read(&mut this.0, buf.initialize_unfilled())?;
        buf.advance(n);

        Poll::Ready(Ok(()))
    }
}

impl AsyncWrite for Expected {
    fn poll_write(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Poll::Ready(Ok(buf.len()))
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

struct Eof;

impl AsyncRead for Eof {
    fn poll_read(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        _buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

impl AsyncWrite for Eof {
    fn poll_write(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        _buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Poll::Ready(Ok(0))
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

#[tokio::test]
async fn stream_good() -> io::Result<()> {
    stream_good_impl(false, false).await
}

#[tokio::test]
async fn stream_good_vectored() -> io::Result<()> {
    stream_good_impl(true, false).await
}

#[tokio::test]
async fn stream_good_bufread() -> io::Result<()> {
    stream_good_impl(false, true).await
}

async fn stream_good_impl(vectored: bool, bufread: bool) -> io::Result<()> {
    const FILE: &[u8] = include_bytes!("../../README.md");

    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);
    poll_fn(|cx| do_handshake(&mut client, &mut server, cx)).await?;

    io::copy(&mut Cursor::new(FILE), &mut server.writer())?;
    server.send_close_notify();

    {
        let mut good = Good(&mut server);
        let mut stream = Stream::new(&mut good, &mut client);

        let mut buf = Vec::new();
        if bufread {
            dbg!(tokio::io::copy_buf(&mut stream, &mut buf).await)?;
        } else {
            dbg!(stream.read_to_end(&mut buf).await)?;
        }
        assert_eq!(buf, FILE);

        dbg!(utils::write(&mut stream, b"Hello World!", vectored).await)?;
        stream.session.send_close_notify();

        dbg!(stream.shutdown().await)?;
    }

    let mut buf = String::new();
    dbg!(server.process_new_packets()).map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;
    dbg!(server.reader().read_to_string(&mut buf))?;
    assert_eq!(buf, "Hello World!");

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_bad() -> io::Result<()> {
    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);
    poll_fn(|cx| do_handshake(&mut client, &mut server, cx)).await?;
    client.set_buffer_limit(Some(1024));

    let mut bad = Pending;
    let mut stream = Stream::new(&mut bad, &mut client);
    assert_eq!(
        poll_fn(|cx| stream.as_mut_pin().poll_write(cx, &[0x42; 8])).await?,
        8
    );
    assert_eq!(
        poll_fn(|cx| stream.as_mut_pin().poll_write(cx, &[0x42; 8])).await?,
        8
    );
    let r = poll_fn(|cx| stream.as_mut_pin().poll_write(cx, &[0x00; 1024])).await?; // fill buffer
    assert!(r < 1024);

    let mut cx = Context::from_waker(noop_waker_ref());
    let ret = stream.as_mut_pin().poll_write(&mut cx, &[0x01]);
    assert!(ret.is_pending());

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_handshake() -> io::Result<()> {
    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);

    {
        let mut good = Good(&mut server);
        let mut stream = Stream::new(&mut good, &mut client);
        let (r, w) = poll_fn(|cx| stream.handshake(cx)).await?;

        assert!(r > 0);
        assert!(w > 0);

        poll_fn(|cx| stream.handshake(cx)).await?; // finish server handshake
    }

    assert!(!server.is_handshaking());
    assert!(!client.is_handshaking());

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_buffered_handshake() -> io::Result<()> {
    use tokio::io::BufWriter;

    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);

    {
        let mut good = BufWriter::new(Good(&mut server));
        let mut stream = Stream::new(&mut good, &mut client);
        let (r, w) = poll_fn(|cx| stream.handshake(cx)).await?;

        assert!(r > 0);
        assert!(w > 0);

        poll_fn(|cx| stream.handshake(cx)).await?; // finish server handshake
    }

    assert!(!server.is_handshaking());
    assert!(!client.is_handshaking());

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_handshake_eof() -> io::Result<()> {
    let (_, mut client) = make_pair();

    let mut bad = Expected(Cursor::new(Vec::new()));
    let mut stream = Stream::new(&mut bad, &mut client);

    let mut cx = Context::from_waker(noop_waker_ref());
    let r = stream.handshake(&mut cx);
    assert_eq!(
        r.map_err(|err| err.kind()),
        Poll::Ready(Err(io::ErrorKind::UnexpectedEof))
    );

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_handshake_write_eof() -> io::Result<()> {
    let (_, mut client) = make_pair();

    let mut io = Eof;
    let mut stream = Stream::new(&mut io, &mut client);

    let mut cx = Context::from_waker(noop_waker_ref());
    let r = stream.handshake(&mut cx);
    assert_eq!(
        r.map_err(|err| err.kind()),
        Poll::Ready(Err(io::ErrorKind::WriteZero))
    );

    Ok(()) as io::Result<()>
}

// see https://github.com/tokio-rs/tls/issues/77
#[tokio::test]
async fn stream_handshake_regression_issues_77() -> io::Result<()> {
    let (_, mut client) = make_pair();

    let mut bad = Expected(Cursor::new(b"\x15\x03\x01\x00\x02\x02\x00".to_vec()));
    let mut stream = Stream::new(&mut bad, &mut client);

    let mut cx = Context::from_waker(noop_waker_ref());
    let r = stream.handshake(&mut cx);
    assert_eq!(
        r.map_err(|err| err.kind()),
        Poll::Ready(Err(io::ErrorKind::InvalidData))
    );

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_eof() -> io::Result<()> {
    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);
    poll_fn(|cx| do_handshake(&mut client, &mut server, cx)).await?;

    let mut bad = Expected(Cursor::new(Vec::new()));
    let mut stream = Stream::new(&mut bad, &mut client);

    let mut buf = Vec::new();
    let result = stream.read_to_end(&mut buf).await;
    assert_eq!(
        result.err().map(|e| e.kind()),
        Some(io::ErrorKind::UnexpectedEof)
    );

    Ok(()) as io::Result<()>
}

#[tokio::test]
async fn stream_write_zero() -> io::Result<()> {
    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);
    poll_fn(|cx| do_handshake(&mut client, &mut server, cx)).await?;

    let mut io = Eof;
    let mut stream = Stream::new(&mut io, &mut client);

    stream.write_all(b"1").await.unwrap();
    let result = stream.flush().await;
    assert_eq!(
        result.err().map(|e| e.kind()),
        Some(io::ErrorKind::WriteZero)
    );

    Ok(()) as io::Result<()>
}

fn make_pair() -> (ServerConnection, ClientConnection) {
    let (sconfig, cconfig) = utils::make_configs();
    let server = ServerConnection::new(Arc::new(sconfig)).unwrap();

    let domain = ServerName::try_from("foobar.com").unwrap();
    let client = ClientConnection::new(Arc::new(cconfig), domain).unwrap();

    (server, client)
}

fn do_handshake(
    client: &mut ClientConnection,
    server: &mut Connection,
    cx: &mut Context<'_>,
) -> Poll<io::Result<()>> {
    let mut good = Good(server);
    let mut stream = Stream::new(&mut good, client);

    while stream.session.is_handshaking() {
        ready!(stream.handshake(cx))?;
    }

    while stream.session.wants_write() {
        ready!(stream.write_io(cx))?;
    }

    Poll::Ready(Ok(()))
}

#[cfg(feature = "connectanum-copy-observer")]
#[tokio::test]
async fn copy_observer_bounded_plaintext_reads() -> io::Result<()> {
    use crate::copy_observer::observed_on_current_thread;

    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);
    poll_fn(|cx| do_handshake(&mut client, &mut server, cx)).await?;
    server.writer().write_all(b"123456789")?;
    server.send_close_notify();
    let mut good = Good(&mut server);
    let mut stream = Stream::new(&mut good, &mut client);
    let before = observed_on_current_thread();

    let mut storage = [0x55; 5];
    let mut output = ReadBuf::new(&mut storage);
    output.put_slice(b"xx");
    poll_fn(|cx| Pin::new(&mut stream).poll_read(cx, &mut output)).await?;
    assert_eq!(output.filled(), b"xx123");
    assert_eq!(observed_on_current_thread() - before, 3);
    let mut rest = Vec::new();
    stream.read_to_end(&mut rest).await?;
    assert_eq!(rest, b"456789");
    assert_eq!(observed_on_current_thread() - before, 9);
    let mut empty = [];
    assert_eq!(stream.read(&mut empty).await?, 0);
    assert_eq!(stream.read(&mut storage).await?, 0);
    assert_eq!(observed_on_current_thread() - before, 9);
    Ok(())
}

#[cfg(feature = "connectanum-copy-observer")]
#[tokio::test]
async fn copy_observer_borrow_and_consume_preserve_storage() -> io::Result<()> {
    use crate::copy_observer::observed_on_current_thread;
    use tokio::io::{AsyncBufRead, AsyncBufReadExt};

    let (server, mut client) = make_pair();
    let mut server = Connection::from(server);
    poll_fn(|cx| do_handshake(&mut client, &mut server, cx)).await?;
    server.writer().write_all(b"abcdefghij")?;
    server.send_close_notify();
    let mut good = Good(&mut server);
    let mut stream = Stream::new(&mut good, &mut client);
    let before = observed_on_current_thread();
    let pointer = {
        let bytes = stream.fill_buf().await?;
        assert_eq!(bytes, b"abcdefghij");
        bytes.as_ptr()
    };
    assert_eq!(stream.fill_buf().await?.as_ptr(), pointer);
    Pin::new(&mut stream).consume(4);
    {
        let bytes = stream.fill_buf().await?;
        assert_eq!(bytes, b"efghij");
        assert_eq!(bytes.as_ptr(), pointer.wrapping_add(4));
    }
    assert_eq!(observed_on_current_thread(), before);
    let mut rest = Vec::new();
    stream.read_to_end(&mut rest).await?;
    assert_eq!(rest, b"efghij");
    assert_eq!(observed_on_current_thread() - before, 6);
    Ok(())
}

#[cfg(feature = "connectanum-copy-observer")]
#[tokio::test]
async fn copy_observer_pending_and_error_copy_nothing() -> io::Result<()> {
    use crate::copy_observer::observed_on_current_thread;

    let (_, mut client) = make_pair();
    client.write_tls(&mut Vec::new())?;
    let before = observed_on_current_thread();
    let mut pending = Pending;
    let mut stream = Stream::new(&mut pending, &mut client);
    let mut storage = [0x55; 7];
    let mut output = ReadBuf::new(&mut storage);
    let mut cx = Context::from_waker(noop_waker_ref());
    assert!(Pin::new(&mut stream).poll_read(&mut cx, &mut output).is_pending());
    assert!(output.filled().is_empty());
    assert_eq!(observed_on_current_thread(), before);
    let mut invalid = Expected(Cursor::new(vec![0xff, 0x03, 0x03, 0x00, 0x00]));
    let mut stream = Stream::new(&mut invalid, &mut client);
    let Poll::Ready(Err(error)) = Pin::new(&mut stream).poll_read(&mut cx, &mut output) else {
        panic!("invalid TLS header must fail immediately");
    };
    assert_eq!(error.kind(), io::ErrorKind::InvalidData);
    assert!(output.filled().is_empty());
    assert_eq!(observed_on_current_thread(), before);
    Ok(())
}

// Share `utils` module with integration tests
include!("../../tests/utils.rs");
