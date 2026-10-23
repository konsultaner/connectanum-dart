use super::rawsocket_writer_tests::FixtureFile;
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
    async fn new(serializer: rawsocket::Serializer, masked: bool) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await;
        assert!(listener.is_ok());
        let listener = listener.unwrap();
        let address = listener.local_addr();
        assert!(address.is_ok());
        let pair = time::timeout(Duration::from_secs(5), async {
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
        let task = spawn_websocket_writer(
            tokio::runtime::Handle::current(),
            ConnectionId(73),
            serializer,
            writer,
            receiver,
            close,
            masked,
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
        let read = time::timeout(Duration::from_secs(5), self.peer.read_to_end(&mut bytes)).await;
        assert!(read.is_ok());
        assert!(read.unwrap().is_ok());
        let closed = time::timeout(Duration::from_secs(5), self.closed.recv()).await;
        assert!(closed.is_ok());
        assert_eq!(closed.unwrap(), Some(ConnectionTaskSignal::WriterClosed));
        let duplicate = time::timeout(Duration::from_secs(5), self.closed.recv()).await;
        assert!(duplicate.is_ok());
        assert_eq!(duplicate.unwrap(), None);
        bytes
    }
}

fn decode(mut wire: &[u8], masked: bool) -> Vec<(u8, Vec<u8>)> {
    // Independent wire oracle: no production frame parser or mask helper.
    let mut frames = Vec::new();
    while !wire.is_empty() {
        assert!(wire.len() >= 2);
        let first = wire[0];
        assert_eq!(first & 0x70, 0, "reserved bits must remain clear");
        assert_eq!(wire[1] & 0x80 != 0, masked);
        let mut offset = 2;
        let len = match wire[1] & 0x7f {
            126 => {
                assert!(wire.len() >= 4);
                offset = 4;
                usize::from(u16::from_be_bytes([wire[2], wire[3]]))
            }
            127 => {
                assert!(wire.len() >= 10);
                offset = 10;
                let length = u64::from_be_bytes(wire[2..10].try_into().unwrap());
                assert!(usize::try_from(length).is_ok());
                length as usize
            }
            short => usize::from(short),
        };
        let mask = if masked {
            assert!(wire.len() >= offset + 4);
            let key: [u8; 4] = wire[offset..offset + 4].try_into().unwrap();
            offset += 4;
            key
        } else {
            [0; 4]
        };
        assert!(len <= wire.len() - offset, "truncated frame");
        let payload = wire[offset..offset + len]
            .iter()
            .enumerate()
            .map(|(index, byte)| byte ^ mask[index % 4])
            .collect();
        frames.push((first, payload));
        wire = &wire[offset + len..];
    }
    frames
}

#[tokio::test]
async fn websocket_continuation_writer_preserves_empty_segment_boundaries() {
    for masked in [false, true] {
        for opcode in [1, 2] {
            for segments in [
                vec![],
                vec![Bytes::new(), Bytes::new()],
                vec![Bytes::from_static(b"ABC")],
                vec![Bytes::new(), Bytes::from_static(b"ABC"), Bytes::new()],
            ] {
                let expected: Vec<u8> = segments
                    .iter()
                    .flat_map(|bytes| bytes.iter().copied())
                    .collect();
                let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let address = listener.local_addr().unwrap();
                let exchange = time::timeout(Duration::from_secs(5), async {
                    let (client, server) =
                        tokio::join!(tokio::net::TcpStream::connect(address), listener.accept());
                    let mut client = client?;
                    let (_, mut writer) = tokio::io::split(IoStream::plain(server?.0));
                    let mut wire = Vec::new();
                    let (sent, read) = tokio::join!(
                        async {
                            write_websocket_continuation_frames(
                                &mut writer,
                                opcode,
                                &segments,
                                masked,
                                &mut Vec::new(),
                            )
                            .await?;
                            writer.shutdown().await
                        },
                        client.read_to_end(&mut wire)
                    );
                    sent?;
                    read?;
                    Ok::<_, io::Error>(wire)
                })
                .await
                .expect("continuation frame exchange timed out");
                assert!(exchange.is_ok());
                assert_eq!(
                    decode(&exchange.unwrap(), masked),
                    vec![(0x80 | opcode, expected)]
                );
            }
        }
    }
}

#[tokio::test]
async fn websocket_writer_dispatches_types_and_closes_after_channel_end() {
    for masked in [false, true] {
        for (serializer, data_opcode) in [
            (rawsocket::Serializer::Json, 0x81),
            (rawsocket::Serializer::MessagePack, 0x82),
            (rawsocket::Serializer::Cbor, 0x82),
        ] {
            let fixture = WriterFixture::new(serializer, masked).await;
            let mut invalid = OutboundFrame::message(Bytes::from_static(b"discard"));
            invalid.frame_type = 255;
            fixture.enqueue(invalid);
            for kind in [0, 1, 2] {
                let mut frame = OutboundFrame::message(Bytes::from_static(b"ABC"));
                frame.frame_type = kind;
                fixture.enqueue(frame);
            }
            fixture.enqueue(OutboundFrame::message(Bytes::new()));
            assert_eq!(
                decode(&fixture.finish().await, masked),
                vec![
                    (data_opcode, b"ABC".to_vec()),
                    (0x89, b"ABC".to_vec()),
                    (0x8a, b"ABC".to_vec()),
                    (data_opcode, vec![]),
                    (0x88, vec![0x03, 0xe8]),
                ]
            );
        }
    }
}

#[tokio::test]
async fn websocket_writer_explicit_close_discards_queued_frames_without_extra_close() {
    for masked in [false, true] {
        let fixture = WriterFixture::new(rawsocket::Serializer::Json, masked).await;
        fixture.enqueue(OutboundFrame::close(Some(1001), "bye"));
        fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"discard")));
        assert_eq!(
            decode(&fixture.finish().await, masked),
            vec![(0x88, vec![0x03, 0xe9, b'b', b'y', b'e'])]
        );
    }
}

#[tokio::test]
async fn websocket_writer_deferred_failure_emits_neither_frame_nor_close() {
    for masked in [false, true] {
        for preparation_error in [false, true] {
            let fixture = WriterFixture::new(rawsocket::Serializer::Json, masked).await;
            let mut frame = OutboundFrame::message(Bytes::from_static(b"P"));
            frame.payload_len = 2;
            frame.deferred_segment = Some(Box::new(move || {
                if preparation_error {
                    Err("fixture preparation failure".into())
                } else {
                    Ok(Bytes::from_static(b"length mismatch"))
                }
            }));
            fixture.enqueue(frame);
            fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"discard")));
            assert_eq!(fixture.finish().await, Vec::<u8>::new());
        }
    }
}

fn file_frame(
    file: &FixtureFile,
    len: usize,
    encoded_len: usize,
    encoding: FileSegmentEncoding,
) -> OutboundFrame {
    let mut frame = OutboundFrame::message(Bytes::from_static(b"["));
    frame.payload_len = encoded_len + 2;
    frame.file_segment = Some(OutboundFileSegment {
        file: Arc::clone(&file.file),
        offset: 2,
        len,
        encoding,
    });
    frame.suffix_segments = vec![Bytes::new(), Bytes::from_static(b"]")];
    frame
}

#[tokio::test]
async fn websocket_writer_file_subranges_preserve_mask_offsets_and_base64_padding() {
    let file = FixtureFile::new(b"xx\x00\x7f\x80\xffyy");
    for masked in [false, true] {
        for (len, literal) in [b"".as_slice(), b"AA==", b"AH8=", b"AH+A", b"AH+A/w=="]
            .into_iter()
            .enumerate()
        {
            for encoding in [FileSegmentEncoding::Identity, FileSegmentEncoding::Base64] {
                let payload = if encoding == FileSegmentEncoding::Identity {
                    [b"[".as_slice(), &b"\x00\x7f\x80\xff"[..len], b"]"].concat()
                } else {
                    [b"[".as_slice(), literal, b"]"].concat()
                };
                let fixture = WriterFixture::new(rawsocket::Serializer::Cbor, masked).await;
                fixture.enqueue(file_frame(&file, len, payload.len() - 2, encoding));
                fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"next")));
                assert_eq!(
                    decode(&fixture.finish().await, masked),
                    vec![
                        (0x82, payload),
                        (0x82, b"next".to_vec()),
                        (0x88, vec![0x03, 0xe8])
                    ]
                );
            }
        }
    }
}

#[tokio::test]
async fn websocket_writer_file_chunks_preserve_wire_payload() {
    let len = FILE_SEGMENT_BUFFER_SIZE + 3;
    let file = FixtureFile::new(&vec![0; len + 2]);
    for masked in [false, true] {
        for encoding in [FileSegmentEncoding::Identity, FileSegmentEncoding::Base64] {
            let mut content = if encoding == FileSegmentEncoding::Identity {
                vec![0; len]
            } else {
                // Independent Base64 oracle for all-zero input, including padding.
                let mut encoded = vec![b'A'; len.div_ceil(3) * 4];
                let padding = (3 - len % 3) % 3;
                let end = encoded.len();
                encoded[end - padding..].fill(b'=');
                encoded
            };
            let fixture = WriterFixture::new(rawsocket::Serializer::Cbor, masked).await;
            fixture.enqueue(file_frame(&file, len, content.len(), encoding));
            content.insert(0, b'[');
            content.push(b']');
            assert_eq!(
                decode(&fixture.finish().await, masked),
                vec![(0x82, content), (0x88, vec![0x03, 0xe8])]
            );
        }
    }
}

#[tokio::test]
async fn websocket_writer_file_failure_stops_before_following_frame_or_close() {
    let file = FixtureFile::new(b"xxDATA");
    for truncated in [false, true] {
        let fixture = WriterFixture::new(rawsocket::Serializer::Cbor, false).await;
        let frame = file_frame(
            &file,
            if truncated { 5 } else { 4 },
            5,
            FileSegmentEncoding::Identity,
        );
        fixture.enqueue(frame);
        fixture.enqueue(OutboundFrame::message(Bytes::from_static(b"discard")));
        let expected = if truncated {
            vec![0x82, 7, b'[']
        } else {
            vec![0x82, 7, b'[', b'D', b'A', b'T', b'A', b']']
        };
        assert_eq!(fixture.finish().await, expected);
    }
}

#[derive(Default)]
struct BatchWriteTrace {
    bytes: Vec<u8>,
    offers: Vec<(usize, usize)>,
    vectored: usize,
    flushes: usize,
    blocked: bool,
}

struct BatchWriteSink {
    trace: Arc<Mutex<BatchWriteTrace>>,
    vectored: bool,
    maximum: usize,
    pending_once: bool,
    error_once: Option<io::ErrorKind>,
    zero_once: bool,
    fail_flush: bool,
    stall_after: Option<usize>,
}

impl BatchWriteSink {
    fn new(vectored: bool) -> Self {
        Self {
            trace: Arc::new(Mutex::new(BatchWriteTrace::default())),
            vectored,
            maximum: usize::MAX,
            pending_once: false,
            error_once: None,
            zero_once: false,
            fail_flush: false,
            stall_after: None,
        }
    }
}

impl AsyncWrite for BatchWriteSink {
    fn poll_write(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        bytes: &[u8],
    ) -> std::task::Poll<io::Result<usize>> {
        let this = self.get_mut();
        if this.pending_once {
            this.pending_once = false;
            cx.waker().wake_by_ref();
            return std::task::Poll::Pending;
        }
        if let Some(error) = this.error_once.take() {
            return std::task::Poll::Ready(Err(error.into()));
        }
        if this.zero_once {
            this.zero_once = false;
            return std::task::Poll::Ready(Ok(0));
        }
        let mut trace = this.trace.lock().unwrap();
        if this
            .stall_after
            .is_some_and(|limit| trace.bytes.len() >= limit)
        {
            trace.blocked = true;
            return std::task::Poll::Pending;
        }
        trace.offers.push((bytes.as_ptr() as usize, bytes.len()));
        let written = bytes.len().min(this.maximum);
        trace.bytes.extend_from_slice(&bytes[..written]);
        std::task::Poll::Ready(Ok(written))
    }

    fn poll_write_vectored(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        bytes: &[io::IoSlice<'_>],
    ) -> std::task::Poll<io::Result<usize>> {
        let this = self.get_mut();
        this.trace.lock().unwrap().vectored += 1;
        let first = bytes
            .iter()
            .find(|part| !part.is_empty())
            .map(|part| part.as_ref())
            .unwrap_or(&[]);
        std::pin::Pin::new(this).poll_write(cx, first)
    }

    fn is_write_vectored(&self) -> bool {
        self.vectored
    }

    fn poll_flush(
        self: std::pin::Pin<&mut Self>,
        _cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<io::Result<()>> {
        self.trace.lock().unwrap().flushes += 1;
        std::task::Poll::Ready(if self.fail_flush {
            Err(io::ErrorKind::BrokenPipe.into())
        } else {
            Ok(())
        })
    }

    fn poll_shutdown(
        self: std::pin::Pin<&mut Self>,
        _cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<io::Result<()>> {
        std::task::Poll::Ready(Ok(()))
    }
}

fn batch_payload(length: usize) -> Vec<u8> {
    (0..length)
        .map(|index| (index.wrapping_mul(17) & 255) as u8)
        .collect()
}

#[tokio::test]
async fn large_unmasked_bounded_borrowed_writes_preserve_full_wire_and_partial_progress() {
    let payload = batch_payload(128 * 1024 + 17);
    for vectored in [false, true] {
        for (opcode, fin) in [(0x2, true), (0x0, false)] {
            let (header, _) = websocket_frame_header(opcode, fin, payload.len(), false);
            let mut sink = BatchWriteSink::new(vectored);
            sink.maximum = 8191;
            sink.pending_once = true;
            write_unmasked_websocket_frame(&mut sink, &header, &payload, &mut Vec::new())
                .await
                .unwrap();
            let trace = sink.trace.lock().unwrap();
            assert_eq!(
                decode(&trace.bytes, false),
                vec![(opcode | if fin { 0x80 } else { 0 }, payload.clone())]
            );
            assert!(trace.offers.iter().all(|(_, length)| *length <= 32 * 1024));
            for (address, length) in &trace.offers {
                assert!(
                    (*address >= header.as_ptr() as usize
                        && address + length <= header.as_ptr() as usize + header.len())
                        || (*address >= payload.as_ptr() as usize
                            && address + length <= payload.as_ptr() as usize + payload.len())
                );
            }
            assert_eq!(trace.flushes, 5);
            assert_eq!(trace.vectored, 0);
        }
    }
}

#[tokio::test]
async fn large_unmasked_threshold_and_small_control_paths_remain_frame_identical() {
    for length in [0, 3, 65536, 128 * 1024 - 1, 128 * 1024, 128 * 1024 + 1] {
        let payload = batch_payload(length);
        let (header, _) = websocket_frame_header(0x2, true, length, false);
        let mut sink = BatchWriteSink::new(true);
        write_unmasked_websocket_frame(&mut sink, &header, &payload, &mut Vec::new())
            .await
            .unwrap();
        let trace = sink.trace.lock().unwrap();
        assert_eq!(decode(&trace.bytes, false), vec![(0x82, payload)]);
        if length < 128 * 1024 {
            assert_eq!(trace.flushes, 0);
            if length > 0 {
                assert!(trace.vectored > 0);
            }
        } else {
            assert!(trace.offers.iter().all(|(_, bytes)| *bytes <= 32 * 1024));
            assert!(trace.flushes >= 4);
        }
    }
    let payload = b"ping";
    let (header, _) = websocket_frame_header(0x9, true, payload.len(), false);
    let mut sink = BatchWriteSink::new(true);
    write_unmasked_websocket_frame(&mut sink, &header, payload, &mut Vec::new())
        .await
        .unwrap();
    let trace = sink.trace.lock().unwrap();
    assert_eq!(decode(&trace.bytes, false), vec![(0x89, payload.to_vec())]);
    assert_eq!(trace.flushes, 0);
}

#[tokio::test]
async fn large_unmasked_zero_and_interrupted_writes_remain_errors() {
    let payload = batch_payload(128 * 1024 + 1);
    let (header, _) = websocket_frame_header(0x2, true, payload.len(), false);
    for vectored in [false, true] {
        for error in [
            io::ErrorKind::Interrupted,
            io::ErrorKind::BrokenPipe,
            io::ErrorKind::WriteZero,
        ] {
            let mut sink = BatchWriteSink::new(vectored);
            if error == io::ErrorKind::WriteZero {
                sink.zero_once = true;
            } else {
                sink.error_once = Some(error);
            }
            let result =
                write_unmasked_websocket_frame(&mut sink, &header, &payload, &mut Vec::new()).await;
            assert_eq!(result.unwrap_err().kind(), error);
            assert!(sink.trace.lock().unwrap().bytes.is_empty());
        }
    }
}

struct BatchNoopWake;
impl std::task::Wake for BatchNoopWake {
    fn wake(self: Arc<Self>) {}
}

#[tokio::test]
async fn large_unmasked_write_yields_before_completing_even_when_sink_is_always_ready() {
    let payload = batch_payload(256 * 1024);
    let (header, _) = websocket_frame_header(0x2, true, payload.len(), false);
    let mut sink = BatchWriteSink::new(true);
    let trace = sink.trace.clone();
    let mut scratch = Vec::new();
    let mut future = Box::pin(write_unmasked_websocket_frame(
        &mut sink,
        &header,
        &payload,
        &mut scratch,
    ));
    let first = {
        let waker = std::task::Waker::from(Arc::new(BatchNoopWake));
        let mut context = std::task::Context::from_waker(&waker);
        std::future::Future::poll(future.as_mut(), &mut context)
    };
    assert!(first.is_pending());
    assert_eq!(trace.lock().unwrap().bytes.len(), header.len() + 32 * 1024);
    assert_eq!(trace.lock().unwrap().flushes, 1);
    future.await.unwrap();
    assert_eq!(
        decode(&trace.lock().unwrap().bytes, false),
        vec![(0x82, payload)]
    );
}

struct BatchOwnedPayload {
    bytes: Vec<u8>,
    drops: Arc<std::sync::atomic::AtomicUsize>,
}
impl AsRef<[u8]> for BatchOwnedPayload {
    fn as_ref(&self) -> &[u8] {
        &self.bytes
    }
}
impl Drop for BatchOwnedPayload {
    fn drop(&mut self) {
        self.drops.fetch_add(1, Ordering::SeqCst);
    }
}

fn owned_batch_payload(length: usize, drops: &Arc<std::sync::atomic::AtomicUsize>) -> Bytes {
    Bytes::from_owner(BatchOwnedPayload {
        bytes: batch_payload(length),
        drops: drops.clone(),
    })
}

#[tokio::test]
async fn large_unmasked_flush_failure_closes_queue_without_following_or_close_frame_and_releases_owners(
) {
    let drops = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let mut sink = BatchWriteSink::new(true);
    sink.fail_flush = true;
    let trace = sink.trace.clone();
    let payload = owned_batch_payload(256 * 1024, &drops);
    let (header, _) = websocket_frame_header(0x2, true, payload.len(), false);
    let (sender, receiver) = mpsc::channel(2);
    let (closed, mut signals) = mpsc::unbounded_channel();
    assert!(sender.try_send(OutboundFrame::message(payload)).is_ok());
    assert!(sender
        .try_send(OutboundFrame::message(owned_batch_payload(3, &drops)))
        .is_ok());
    let _abort = spawn_websocket_writer(
        tokio::runtime::Handle::current(),
        ConnectionId(99),
        rawsocket::Serializer::Flatbuffers,
        sink,
        receiver,
        closed,
        false,
    );
    assert_eq!(
        time::timeout(Duration::from_secs(5), signals.recv())
            .await
            .unwrap(),
        Some(ConnectionTaskSignal::WriterClosed)
    );
    assert_eq!(
        time::timeout(Duration::from_secs(5), signals.recv())
            .await
            .unwrap(),
        None
    );
    assert!(sender.is_closed());
    assert_eq!(drops.load(Ordering::SeqCst), 2);
    let state = trace.lock().unwrap();
    assert_eq!(state.bytes.len(), header.len() + 32 * 1024);
    assert_eq!(&state.bytes[..header.len()], &header);
    assert_eq!(&state.bytes[header.len()..], &batch_payload(32 * 1024));
    assert_eq!(state.flushes, 1);
}

#[tokio::test]
async fn large_unmasked_pending_write_retains_owner_until_whole_task_cancellation() {
    let drops = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let payload = owned_batch_payload(256 * 1024, &drops);
    let (header, _) = websocket_frame_header(0x2, true, payload.len(), false);
    let mut sink = BatchWriteSink::new(true);
    sink.maximum = 32 * 1024;
    sink.stall_after = Some(header.len() + 32 * 1024);
    let trace = sink.trace.clone();
    let task = tokio::spawn(async move {
        write_unmasked_websocket_frame(&mut sink, &header, &payload, &mut Vec::new()).await
    });
    time::timeout(Duration::from_secs(5), async {
        while !trace.lock().unwrap().blocked {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(drops.load(Ordering::SeqCst), 0);
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    assert_eq!(drops.load(Ordering::SeqCst), 1);
}
