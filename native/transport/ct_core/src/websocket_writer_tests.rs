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
