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
