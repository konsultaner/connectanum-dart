use super::*;

struct WriterFixture {
    peer: tokio::net::TcpStream,
    frames: Option<mpsc::Sender<OutboundFrame>>,
    closed: tokio::sync::mpsc::UnboundedReceiver<ConnectionTaskSignal>,
    task: AbortHandle,
}

impl Drop for WriterFixture {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl WriterFixture {
    async fn new(exponent: u32) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await;
        assert!(listener.is_ok());
        let listener = listener.unwrap();
        let address = listener.local_addr();
        assert!(address.is_ok());
        let pair = time::timeout(Duration::from_secs(2), async {
            tokio::join!(
                tokio::net::TcpStream::connect(address.unwrap()),
                listener.accept()
            )
        })
        .await;
        assert!(pair.is_ok());
        let (peer, server) = pair.unwrap();
        assert!(peer.is_ok());
        assert!(server.is_ok());
        let (_reader, writer) = tokio::io::split(IoStream::plain(server.unwrap().0));
        let (frames, receiver) = mpsc::channel(8);
        let (close, closed) = mpsc::unbounded_channel();
        let task = spawn_connection_writer(
            tokio::runtime::Handle::current(),
            ConnectionId(72),
            writer,
            None,
            exponent,
            receiver,
            close,
        );
        Self {
            peer: peer.unwrap(),
            frames: Some(frames),
            closed,
            task,
        }
    }

    fn enqueue(&self, frame: OutboundFrame) {
        assert!(self.frames.as_ref().unwrap().try_send(frame).is_ok());
    }

    async fn finish(mut self) -> Vec<u8> {
        self.frames.take();
        let mut bytes = Vec::new();
        let read = time::timeout(Duration::from_secs(2), self.peer.read_to_end(&mut bytes)).await;
        assert!(read.is_ok());
        assert!(read.unwrap().is_ok());
        let closed = time::timeout(Duration::from_secs(2), self.closed.recv()).await;
        assert!(closed.is_ok());
        assert_eq!(closed.unwrap(), Some(ConnectionTaskSignal::WriterClosed));
        let duplicate = time::timeout(Duration::from_secs(2), self.closed.recv()).await;
        assert!(duplicate.is_ok());
        assert_eq!(duplicate.unwrap(), None);
        bytes
    }
}

fn wire(kind: u8, payload: &[u8], upgraded: bool) -> Vec<u8> {
    // Independent oracle: never call the production frame-header encoder.
    let length = (payload.len() as u32).to_be_bytes();
    let mut bytes = vec![kind];
    bytes.extend_from_slice(if upgraded { &length } else { &length[1..] });
    bytes.extend_from_slice(payload);
    bytes
}

pub(super) struct FixtureFile {
    pub(super) file: Arc<File>,
    path: std::path::PathBuf,
}

impl FixtureFile {
    pub(super) fn new(bytes: &[u8]) -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH);
        assert!(nonce.is_ok());
        let path = std::env::temp_dir().join(format!(
            "connectanum-writer-{}-{}-{}",
            std::process::id(),
            nonce.unwrap().as_nanos(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path);
        assert!(file.is_ok());
        let fixture = Self {
            file: Arc::new(file.unwrap()),
            path,
        };
        let mut file = fixture.file.as_ref();
        assert!(std::io::Write::write_all(&mut file, bytes).is_ok());
        fixture
    }
}

impl Drop for FixtureFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

#[test]
fn rawsocket_header_encodes_each_length_byte_and_protocol_limits() {
    for kind in [0, 1, 2, 7] {
        for (len, expected) in [
            (0, [kind, 0, 0, 0]),
            (0xff, [kind, 0, 0, 0xff]),
            (0x100, [kind, 0, 1, 0]),
            (0x010203, [kind, 1, 2, 3]),
            (0xffffff, [kind, 0xff, 0xff, 0xff]),
            (0x1000000, [kind | 8, 0, 0, 0]),
        ] {
            let header = encode_frame_header(kind, len, false);
            assert!(header.is_ok());
            assert_eq!(header.unwrap().as_bytes(), expected);
        }
        assert!(encode_frame_header(kind, 0x1000001, false).is_err());
        for (len, expected) in [
            (0, [kind, 0, 0, 0, 0]),
            (0x01020304, [kind, 1, 2, 3, 4]),
            (u32::MAX as usize, [kind, 0xff, 0xff, 0xff, 0xff]),
        ] {
            let header = encode_frame_header(kind, len, true);
            assert!(header.is_ok());
            assert_eq!(header.unwrap().as_bytes(), expected);
        }
        if let Some(too_large) = (u32::MAX as usize).checked_add(1) {
            assert!(encode_frame_header(kind, too_large, true).is_err());
        }
    }
    for upgraded in [false, true] {
        for kind in [8, 0xff] {
            assert!(encode_frame_header(kind, 0, upgraded).is_err());
        }
    }
}

#[tokio::test]
async fn rawsocket_writer_preserves_nonzero_middle_length_byte() {
    let payload = Bytes::from(vec![0xa5; 0x010203]);
    for (exponent, upgraded) in [(24, false), (25, true)] {
        let fixture = WriterFixture::new(exponent).await;
        fixture.enqueue(OutboundFrame::message(payload.clone()));
        fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"sentinel")));
        let expected = [wire(0, &payload, upgraded), wire(0, b"sentinel", upgraded)].concat();
        assert_eq!(fixture.finish().await, expected);
    }
}

#[tokio::test]
async fn rawsocket_writer_preserves_segments_suffixes_and_frame_order() {
    for (exponent, upgraded) in [(16, false), (24, false), (25, true)] {
        let fixture = WriterFixture::new(exponent).await;
        let mut expected = Vec::new();
        for kind in 0..=2 {
            let mut frame = OutboundFrame::message_segments(vec![
                Bytes::new(),
                Bytes::from_static(b"A"),
                Bytes::from_static(b"B"),
                Bytes::new(),
            ]);
            frame.frame_type = kind;
            frame.payload_len = 3;
            frame.suffix_segments = vec![Bytes::new(), Bytes::from_static(b"C"), Bytes::new()];
            fixture.enqueue(frame);
            expected.extend(wire(kind, b"ABC", upgraded));
        }
        fixture.enqueue(OutboundFrame::message(Bytes::new()));
        expected.extend(wire(0, b"", upgraded));
        assert_eq!(fixture.finish().await, expected);
    }
}

#[tokio::test]
async fn rawsocket_writer_skips_invalid_frames_but_delivers_the_next_frame() {
    for (exponent, upgraded) in [(24, false), (25, true)] {
        let fixture = WriterFixture::new(exponent).await;
        for kind in [3, 7, 8, 255] {
            let mut frame = OutboundFrame::message(Bytes::from_static(b"not on wire"));
            frame.frame_type = kind;
            fixture.enqueue(frame);
        }
        let invalid_length = if upgraded {
            usize::try_from(u64::from(u32::MAX) + 1).ok()
        } else {
            Some((1usize << 24) + 1)
        };
        if let Some(length) = invalid_length {
            let mut frame = OutboundFrame::message(Bytes::new());
            frame.payload_len = length;
            fixture.enqueue(frame);
        }
        fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"next")));
        assert_eq!(fixture.finish().await, wire(0, b"next", upgraded));
    }
}

#[tokio::test]
async fn rawsocket_writer_resolves_deferred_bytes_before_suffixes() {
    let fixture = WriterFixture::new(16).await;
    let mut frame = OutboundFrame::message(Bytes::from_static(b"P"));
    frame.payload_len = 3;
    frame.deferred_segment = Some(Box::new(|| Ok(Bytes::from_static(b"D"))));
    frame.suffix_segments = vec![Bytes::from_static(b"S")];
    fixture.enqueue(frame);
    fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"next")));
    assert_eq!(
        fixture.finish().await,
        [wire(0, b"PDS", false), wire(0, b"next", false)].concat()
    );
}

#[tokio::test]
async fn rawsocket_writer_closes_before_emitting_failed_deferred_frames() {
    for preparation_error in [false, true] {
        let fixture = WriterFixture::new(16).await;
        let mut frame = OutboundFrame::message(Bytes::from_static(b"prefix"));
        frame.payload_len = 7;
        frame.deferred_segment = Some(Box::new(move || {
            if preparation_error {
                Err("fixture preparation failure".into())
            } else {
                Ok(Bytes::from_static(b"wrong length"))
            }
        }));
        fixture.enqueue(frame);
        fixture.enqueue(OutboundFrame::message(Bytes::from_static(
            b"must not be sent",
        )));
        assert_eq!(fixture.finish().await, Vec::<u8>::new());
    }
}

#[tokio::test]
async fn rawsocket_writer_buffers_file_subranges_and_base64_padding() {
    let file = FixtureFile::new(b"xx\x00\x7f\x80\xffyy");
    for (encoding, expected) in [
        (
            FileSegmentEncoding::Identity,
            vec![
                b"".as_slice(),
                b"\x00",
                b"\x00\x7f",
                b"\x00\x7f\x80",
                b"\x00\x7f\x80\xff",
            ],
        ),
        (
            FileSegmentEncoding::Base64,
            vec![b"".as_slice(), b"AA==", b"AH8=", b"AH+A", b"AH+A/w=="],
        ),
    ] {
        for (len, encoded) in expected.into_iter().enumerate() {
            let fixture = WriterFixture::new(16).await;
            let mut frame = OutboundFrame::message(Bytes::from_static(b"["));
            frame.payload_len = encoded.len() + 2;
            frame.file_segment = Some(OutboundFileSegment {
                file: Arc::clone(&file.file),
                offset: 2,
                len,
                encoding,
            });
            frame.suffix_segments = vec![Bytes::from_static(b"]")];
            fixture.enqueue(frame);
            let payload = [b"[".as_slice(), encoded, b"]"].concat();
            assert_eq!(fixture.finish().await, wire(0, &payload, false));
        }
    }
}

#[tokio::test]
async fn rawsocket_writer_file_truncation_closes_without_suffix_or_next_frame() {
    let file = FixtureFile::new(b"xxDATA");
    let fixture = WriterFixture::new(16).await;
    let mut frame = OutboundFrame::message(Bytes::from_static(b"["));
    frame.payload_len = 7;
    frame.file_segment = Some(OutboundFileSegment {
        file: Arc::clone(&file.file),
        offset: 2,
        len: 5,
        encoding: FileSegmentEncoding::Identity,
    });
    frame.suffix_segments = vec![Bytes::from_static(b"]")];
    fixture.enqueue(frame);
    fixture.enqueue(OutboundFrame::message(Bytes::from_static(
        b"must not be sent",
    )));
    assert_eq!(fixture.finish().await, [0, 0, 0, 7, b'[']);
}

#[derive(Clone, Default)]
struct RawWriteTrace {
    wire: Vec<u8>,
    scalar_calls: usize,
    vectors: Vec<Vec<(usize, usize)>>,
}

#[derive(Clone, Default)]
struct RawRecordingWriter(Arc<Mutex<RawWriteTrace>>);

impl AsyncWrite for RawRecordingWriter {
    fn poll_write(
        self: Pin<&mut Self>,
        _: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        let mut trace = self.0.lock().unwrap();
        trace.scalar_calls += 1;
        trace.wire.extend_from_slice(bytes);
        Poll::Ready(Ok(bytes.len()))
    }
    fn poll_write_vectored(
        self: Pin<&mut Self>,
        _: &mut Context<'_>,
        slices: &[io::IoSlice<'_>],
    ) -> Poll<io::Result<usize>> {
        let mut trace = self.0.lock().unwrap();
        trace.vectors.push(
            slices
                .iter()
                .map(|b| (b.as_ptr() as usize, b.len()))
                .collect(),
        );
        let mut count = 0;
        for slice in slices {
            trace.wire.extend_from_slice(slice);
            count += slice.len();
        }
        Poll::Ready(Ok(count))
    }
    fn is_write_vectored(&self) -> bool {
        true
    }
    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

#[tokio::test]
async fn rawsocket_actual_writer_batches_header_and_borrowed_segments() {
    for upgraded in [false, true] {
        let recorder = RawRecordingWriter::default();
        let observed = recorder.clone();
        let (sender, receiver) = mpsc::channel(1);
        let (closed, mut closes) = mpsc::unbounded_channel();
        let _task = spawn_connection_writer(
            tokio::runtime::Handle::current(),
            ConnectionId(153),
            recorder,
            None,
            if upgraded { 28 } else { 24 },
            receiver,
            closed,
        );
        let source = Bytes::from(vec![99, 99, b'a', b'b', b'c', b'd', b'e', 99]);
        let first = source.slice(2..5);
        let second = source.slice(5..7);
        let pointers = [
            (first.as_ptr() as usize, first.len()),
            (second.as_ptr() as usize, second.len()),
        ];
        let (frame, receipt) =
            OutboundFrame::message_segments(vec![first, Bytes::new(), second]).tracked();
        sender.try_send(frame).unwrap();
        assert_eq!(
            time::timeout(Duration::from_secs(2), receipt.wait())
                .await
                .unwrap(),
            WriteOutcome::Written
        );
        drop(sender);
        assert_eq!(
            time::timeout(Duration::from_secs(2), closes.recv())
                .await
                .unwrap(),
            Some(ConnectionTaskSignal::WriterClosed)
        );
        let trace = observed.0.lock().unwrap().clone();
        assert_eq!(trace.wire, wire(0, b"abcde", upgraded));
        assert_eq!(
            trace.vectors.len(),
            1,
            "segmented frame used {} scalar writes and {} vectored writes",
            trace.scalar_calls,
            trace.vectors.len()
        );
        assert_eq!(trace.scalar_calls, 0);
        assert_eq!(trace.vectors[0][0].1, if upgraded { 5 } else { 4 });
        assert_eq!(trace.vectors[0][1..], pointers);
    }
}

#[cfg(test)]
mod vectored_buffer_regressions {
    use super::super::*;
    use std::{
        pin::Pin,
        task::{Context, Poll},
    };
    struct Writer {
        wire: Vec<u8>,
        vectors: Vec<Vec<(usize, usize)>>,
        scalars: usize,
        vectored: bool,
        limit: usize,
        pending: bool,
        interrupted: bool,
        stop: Option<(usize, io::ErrorKind)>,
    }
    impl Writer {
        fn new(vectored: bool, limit: usize) -> Self {
            Self {
                wire: vec![],
                vectors: vec![],
                scalars: 0,
                vectored,
                limit,
                pending: false,
                interrupted: false,
                stop: None,
            }
        }
        fn accept(
            &mut self,
            cx: &Context<'_>,
            slices: &[io::IoSlice<'_>],
        ) -> Poll<io::Result<usize>> {
            if self.pending {
                self.pending = false;
                cx.waker().wake_by_ref();
                return Poll::Pending;
            }
            if self.interrupted {
                self.interrupted = false;
                return Poll::Ready(Err(io::ErrorKind::Interrupted.into()));
            }
            let mut budget = self.limit;
            if let Some((after, kind)) = self.stop {
                if self.wire.len() >= after {
                    return Poll::Ready(if kind == io::ErrorKind::WriteZero {
                        Ok(0)
                    } else {
                        Err(kind.into())
                    });
                }
                budget = budget.min(after - self.wire.len());
            }
            let mut accepted = 0;
            for bytes in slices {
                let n = bytes.len().min(budget);
                self.wire.extend_from_slice(&bytes[..n]);
                accepted += n;
                budget -= n;
                if budget == 0 {
                    break;
                }
            }
            Poll::Ready(Ok(accepted))
        }
    }
    impl AsyncWrite for Writer {
        fn poll_write(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            bytes: &[u8],
        ) -> Poll<io::Result<usize>> {
            self.scalars += 1;
            self.accept(cx, &[io::IoSlice::new(bytes)])
        }
        fn poll_write_vectored(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            bytes: &[io::IoSlice<'_>],
        ) -> Poll<io::Result<usize>> {
            self.vectors.push(
                bytes
                    .iter()
                    .map(|b| (b.as_ptr() as usize, b.len()))
                    .collect(),
            );
            self.accept(cx, bytes)
        }
        fn is_write_vectored(&self) -> bool {
            self.vectored
        }
        fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
            Poll::Ready(Ok(()))
        }
        fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }
    #[tokio::test]
    async fn partial_vectored_and_scalar_writes_match_independent_wire_for_all_batch_edges() {
        for n in [0, 1, 14, 15, 16, 17, 31, 32, 33, 64] {
            for limit in [1, 2, 3, 7, 31, usize::MAX] {
                for vectored in [false, true] {
                    let header = [0, 1, 2, 3, 4];
                    let segments: Vec<_> = (0..n)
                        .flat_map(|i| {
                            [
                                Bytes::new(),
                                Bytes::from(vec![i as u8; i % 13 + 2]).slice(1..),
                                Bytes::new(),
                            ]
                        })
                        .collect();
                    let expected: Vec<_> = header
                        .iter()
                        .chain(segments.iter().flat_map(|b| b.iter()))
                        .copied()
                        .collect();
                    let mut writer = Writer::new(vectored, limit);
                    writer.pending = true;
                    writer.interrupted = vectored;
                    write_rawsocket_buffers(&mut writer, &header, segments.to_vec())
                        .await
                        .unwrap();
                    assert_eq!(
                        writer.wire, expected,
                        "n={n} limit={limit} vectored={vectored}"
                    );
                    if vectored {
                        assert_eq!(writer.scalars, 0);
                        assert!(writer
                            .vectors
                            .iter()
                            .all(|v| v.len() <= 16 && v.iter().all(|x| x.1 > 0)));
                    } else {
                        assert!(writer.vectors.is_empty());
                    }
                }
            }
        }
    }
    #[tokio::test]
    async fn vectored_boundary_borrows_original_pointer_and_writes_once() {
        let header = [0, 0, 0, 5];
        let base = Bytes::from(vec![99, 99, 1, 2, 3, 4, 5, 99]);
        let a = base.slice(2..5);
        let b = base.slice(5..7);
        let mut writer = Writer::new(true, usize::MAX);
        write_rawsocket_buffers(
            &mut writer,
            &header,
            vec![a.clone(), Bytes::new(), b.clone()],
        )
        .await
        .unwrap();
        assert_eq!(
            writer.vectors,
            vec![vec![
                (header.as_ptr() as usize, 4),
                (a.as_ptr() as usize, 3),
                (b.as_ptr() as usize, 2)
            ]]
        );
        assert_eq!(writer.scalars, 0);
        assert_eq!(writer.wire, [0, 0, 0, 5, 1, 2, 3, 4, 5]);
    }
    #[tokio::test]
    async fn write_zero_and_error_retain_only_the_exact_written_prefix() {
        let header = [1, 2, 3, 4];
        let segments = [Bytes::from_static(b"abc"), Bytes::from_static(b"defghi")];
        let expected: Vec<_> = header.iter().chain(b"abcdefghi").copied().collect();
        for vectored in [false, true] {
            for after in 0..expected.len() {
                for kind in [io::ErrorKind::WriteZero, io::ErrorKind::BrokenPipe] {
                    let mut writer = Writer::new(vectored, 2);
                    writer.stop = Some((after, kind));
                    assert_eq!(
                        write_rawsocket_buffers(&mut writer, &header, segments.to_vec())
                            .await
                            .unwrap_err()
                            .kind(),
                        kind
                    );
                    assert_eq!(writer.wire, expected[..after]);
                }
            }
        }
    }
    #[tokio::test]
    async fn complete_batches_use_the_minimum_bounded_number_of_calls() {
        for n in [0usize, 1, 14, 15, 16, 17, 30, 31, 32, 33, 64, 1025] {
            let parts = vec![Bytes::from_static(b"a"); n];
            let mut writer = Writer::new(true, usize::MAX);
            write_rawsocket_buffers(&mut writer, b"HEAD", parts)
                .await
                .unwrap();
            assert_eq!(writer.vectors.len(), (n + 1).div_ceil(16));
            assert_eq!(writer.wire.len(), 4 + n);
        }
    }

    #[tokio::test]
    async fn repeated_interrupts_yield_and_cancellation_releases_the_owner() {
        use std::sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        };
        struct Owner {
            bytes: Box<[u8]>,
            dropped: Arc<AtomicUsize>,
        }
        impl AsRef<[u8]> for Owner {
            fn as_ref(&self) -> &[u8] {
                &self.bytes
            }
        }
        impl Drop for Owner {
            fn drop(&mut self) {
                self.dropped.fetch_add(1, Ordering::SeqCst);
            }
        }
        let dropped = Arc::new(AtomicUsize::new(0));
        let body = Bytes::from_owner(Owner {
            bytes: Box::new([1, 2, 3, 4]),
            dropped: dropped.clone(),
        });
        let task = tokio::spawn(async move {
            let mut writer = Writer::new(true, usize::MAX);
            writer.stop = Some((0, io::ErrorKind::Interrupted));
            write_rawsocket_buffers(&mut writer, b"HEAD", vec![body]).await
        });
        tokio::task::yield_now().await;
        tokio::task::yield_now().await;
        assert!(!task.is_finished());
        assert_eq!(dropped.load(Ordering::SeqCst), 0);
        task.abort();
        assert!(task.await.unwrap_err().is_cancelled());
        assert_eq!(dropped.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn no_header_or_payload_means_no_write_call() {
        for vectored in [false, true] {
            let mut writer = Writer::new(vectored, usize::MAX);
            write_rawsocket_buffers(&mut writer, &[], vec![Bytes::new(), Bytes::new()])
                .await
                .unwrap();
            assert_eq!(writer.scalars, 0);
            assert!(writer.vectors.is_empty());
        }
    }
}
