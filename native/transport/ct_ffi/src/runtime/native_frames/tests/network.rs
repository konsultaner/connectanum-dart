use super::*;
use crate::tests::test_guard;
use base64::{engine::general_purpose::STANDARD, Engine};
use sha1::{Digest, Sha1};
use std::ffi::CString;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::time::{Duration, Instant};

struct Runtime;
impl Runtime {
    fn new() -> Self {
        assert_eq!(ct_start_runtime(), SUCCESS);
        Self
    }
}
impl Drop for Runtime {
    fn drop(&mut self) {
        let _ = ct_shutdown();
    }
}

fn until(predicate: impl Fn() -> bool) {
    until_boundary("native frame completion", predicate)
}

fn until_boundary(boundary: &str, predicate: impl Fn() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !predicate() {
        assert!(
            Instant::now() < deadline,
            "native frame boundary did not arrive: {boundary}"
        );
        thread::sleep(Duration::from_millis(1));
    }
}

fn connect(websocket: bool, serializer: i32) -> (i32, TcpStream) {
    connect_with_backpressure(websocket, serializer, false)
}

fn connect_with_backpressure(websocket: bool, serializer: i32, slow: bool) -> (i32, TcpStream) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let protocol = match serializer {
        5 => "wamp.2.flatbuffers",
        3 => "wamp.2.cbor",
        2 => "wamp.2.msgpack",
        _ => "wamp.2.json",
    };
    let (sender, receiver) = mpsc::channel();
    let peer = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        if slow {
            socket2::SockRef::from(&stream)
                .set_recv_buffer_size(4096)
                .unwrap();
        }
        if websocket {
            let mut request = Vec::new();
            while !request.ends_with(b"\r\n\r\n") {
                let mut byte = [0];
                stream.read_exact(&mut byte).unwrap();
                request.push(byte[0]);
                assert!(request.len() < 8192);
            }
            let request = String::from_utf8(request).unwrap();
            assert!(request
                .lines()
                .any(|line| line.split_once(':').is_some_and(|(name, value)| name
                    .eq_ignore_ascii_case("sec-websocket-protocol")
                    && value.trim() == protocol)));
            let key = request
                .lines()
                .find_map(|line| {
                    let (name, value) = line.split_once(':')?;
                    name.eq_ignore_ascii_case("sec-websocket-key")
                        .then(|| value.trim())
                })
                .unwrap();
            let mut hash = Sha1::new();
            hash.update(key.as_bytes());
            hash.update(b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
            let accept = STANDARD.encode(hash.finalize());
            let response = format!("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\nSec-WebSocket-Protocol: {protocol}\r\n\r\n");
            stream.write_all(response.as_bytes()).unwrap();
        } else {
            let mut handshake = [0; 4];
            stream.read_exact(&mut handshake).unwrap();
            assert_eq!(handshake[0], 0x7f);
            assert_eq!(handshake[1] & 0xf, serializer as u8);
            stream.write_all(&handshake).unwrap();
        }
        sender.send(stream).unwrap();
    });
    let host = CString::new("127.0.0.1").unwrap();
    let target = CString::new("/").unwrap();
    let connection = if websocket {
        ct_client_connect_websocket(
            host.as_ptr(),
            port.into(),
            target.as_ptr(),
            0,
            0,
            serializer,
            ptr::null(),
            0,
            0,
            0,
        )
    } else {
        ct_client_connect_rawsocket(host.as_ptr(), port.into(), 0, 0, serializer, 24, 0, 0)
    };
    assert!(connection > 0, "native connection failed: {connection}");
    let stream = receiver.recv_timeout(Duration::from_secs(5)).unwrap();
    peer.join().unwrap();
    (connection, stream)
}

fn read_frame(stream: &mut TcpStream, websocket: bool) -> Vec<u8> {
    read_frame_bounded(stream, websocket, 2 * 1024 * 1024)
}

#[test]
fn owned_segments_send_cbor_and_msgpack_on_rawsocket_and_websocket() {
    let _guard = test_guard();
    let _runtime = Runtime::new();
    for websocket in [false, true] {
        for (serializer, codec) in [
            (3, RawSocketSerializer::Cbor),
            (2, RawSocketSerializer::MessagePack),
        ] {
            let (connection, mut peer) = connect(websocket, serializer);
            let length = 128 * 1024;
            let mut prefix = if serializer == 3 {
                vec![0x85, 0x18, 48, 7, 0xa0, 0x68]
            } else {
                vec![0x95, 48, 7, 0x80, 0xa8]
            };
            prefix.extend_from_slice(b"com.echo");
            prefix.extend_from_slice(if serializer == 3 {
                &[0x81, 0x5a]
            } else {
                &[0x91, 0xc6]
            });
            prefix.extend_from_slice(&(length as u32).to_be_bytes());
            let prefix_handle = frozen(&prefix);
            let (owner, body, released, wrong_thread) =
                producer_span(vec![0x37; length + 6], 3, length);
            let (empty_owner, empty, empty_released, empty_wrong_thread) = producer(0);
            let handles = [empty, prefix_handle, body, empty];
            let receipt = unsafe {
                ct_owned_buffer_send_segments_tracked(
                    store_identity(),
                    connection,
                    handles.as_ptr(),
                    handles.len(),
                )
            };
            assert!(receipt > 0, "shared native submission failed: {receipt}");
            for handle in [empty, prefix_handle, body] {
                assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
            }
            let wire = read_frame(&mut peer, websocket);
            assert_eq!(&wire[..prefix.len()], &prefix);
            assert!(wire[prefix.len()..].iter().all(|&byte| byte == 0x37));
            assert_eq!(wire.len(), prefix.len() + length);
            assert!(matches!(
                ct_core::parse_message(codec, Bytes::from(wire))
                    .unwrap()
                    .message,
                WampMessage::Call { request_id: 7, .. }
            ));
            until(|| ct_write_receipt_state(receipt) != 0);
            assert_eq!(ct_write_receipt_state(receipt), 1);
            for (producer, released, wrong_thread) in [
                (owner, released, wrong_thread),
                (empty_owner, empty_released, empty_wrong_thread),
            ] {
                until(|| ct_external_owner_dispatch(producer, 8) > 0);
                assert_eq!(released.load(Ordering::Acquire), 1);
                assert!(!wrong_thread.load(Ordering::Acquire));
                assert_eq!(ct_external_owner_destroy(producer), SUCCESS);
            }
            assert_eq!(ct_write_receipt_release(receipt), SUCCESS);
            assert_eq!(ct_connection_close(connection), SUCCESS);
        }
    }
}

#[test]
fn native_mixed_cbor_flatbuffers_forwarding_uses_actual_connection_and_retains_queued_payload() {
    use crate::runtime::ffi::{
        ct_forward_call_invocation_v2_wide, ct_forward_error_from_error_wide,
        ct_forward_publish_event_wide, ct_forward_result_from_call_wide,
        ct_forward_result_from_yield_wide, ct_message_can_forward_to_connection_v1_wide,
        ct_message_can_forward_to_v1_wide,
    };
    use crate::runtime::state::{StoredMessage, StoredRawFrame};
    struct PayloadOwner {
        bytes: Vec<u8>,
        released: Arc<AtomicUsize>,
    }
    impl AsRef<[u8]> for PayloadOwner {
        fn as_ref(&self) -> &[u8] {
            &self.bytes
        }
    }
    impl Drop for PayloadOwner {
        fn drop(&mut self) {
            self.released.fetch_add(1, Ordering::AcqRel);
        }
    }
    for websocket in [false, true] {
        let _guard = test_guard();
        let _runtime = Runtime::new();
        for (source, target) in [
            (RawSocketSerializer::Cbor, RawSocketSerializer::Flatbuffers),
            (RawSocketSerializer::Flatbuffers, RawSocketSerializer::Cbor),
        ] {
            let target_id = if target == RawSocketSerializer::Cbor {
                3
            } else {
                5
            };
            let (connection, mut peer) = connect(websocket, target_id);
            let (incompatible, mut incompatible_peer) = connect(websocket, 1);
            for kind in 0..5 {
                let expected =
                    serde_cbor::to_vec(&vec![serde_value::Value::Bytes(vec![0x37; 128 * 1024])])
                        .unwrap();
                let released = Arc::new(AtomicUsize::new(0));
                let args = Bytes::from_owner(PayloadOwner {
                    bytes: expected.clone(),
                    released: released.clone(),
                });
                let payload = WampPayload {
                    args: Some(args),
                    ..Default::default()
                };
                let message = match kind {
                    0 => WampMessage::Publish {
                        request_id: 1,
                        options: Default::default(),
                        topic: "source.topic".into(),
                        payload: payload.clone(),
                    },
                    1 | 3 => call(payload.clone()),
                    2 => WampMessage::Yield {
                        request_id: 1,
                        options: Default::default(),
                        payload: payload.clone(),
                    },
                    _ => WampMessage::Error {
                        request_type: 68,
                        request_id: 1,
                        details: Default::default(),
                        error: "com.failure".into(),
                        payload: payload.clone(),
                    },
                };
                let handle = crate::runtime::message_handles::insert(StoredMessage {
                    serializer: source,
                    code: message.code(),
                    message,
                    raw: StoredRawFrame::from_bytes(Bytes::new()),
                    details: None,
                    args: payload.args.clone(),
                    kwargs: None,
                })
                .unwrap() as i64;
                drop(payload);
                assert_eq!(
                    ct_message_can_forward_to_connection_v1_wide(handle, connection),
                    1
                );
                assert_eq!(
                    ct_message_can_forward_to_connection_v1_wide(handle, incompatible),
                    0
                );
                assert_eq!(
                    ct_message_can_forward_to_connection_v1_wide(handle, -1),
                    ERR_INVALID_ARGUMENT
                );
                // An incompatible destination rejects before sending any frame
                // and leaves the source handle available for ordinary fallback.
                if kind == 3 {
                    assert_eq!(
                        ct_forward_result_from_call_wide(handle, incompatible, 79),
                        ERR_UNSUPPORTED
                    );
                    assert_eq!(ct_message_can_forward_to_v1_wide(handle, target_id), 1);
                }
                let result = match kind {
                    0 => ct_forward_publish_event_wide(
                        handle,
                        connection,
                        77,
                        78,
                        0,
                        0,
                        ptr::null(),
                        0,
                    ),
                    1 => ct_forward_call_invocation_v2_wide(
                        handle,
                        connection,
                        79,
                        80,
                        0,
                        0,
                        ptr::null(),
                        0,
                        ptr::null(),
                        0,
                        ptr::null(),
                        0,
                        1,
                        1,
                    ),
                    2 => ct_forward_result_from_yield_wide(handle, connection, 79, 1),
                    3 => ct_forward_result_from_call_wide(handle, connection, 79),
                    _ => ct_forward_error_from_error_wide(handle, connection, 48, 79),
                };
                assert_eq!(result, SUCCESS);
                assert_eq!(released.load(Ordering::Acquire), 0);
                // The writer must retain the payload after the caller's native
                // message handle has gone, before the delayed peer consumes it.
                ct_message_release_wide(handle);
                assert_eq!(
                    ct_message_can_forward_to_v1_wide(handle, target_id),
                    ERR_INVALID_ARGUMENT
                );
                let received =
                    ct_core::parse_message(target, Bytes::from(read_frame(&mut peer, websocket)))
                        .unwrap()
                        .message;
                assert_eq!(received.code(), [36, 68, 50, 50, 8][kind]);
                let received_payload = match received {
                    WampMessage::Event { payload, .. }
                    | WampMessage::Invocation { payload, .. }
                    | WampMessage::Result { payload, .. }
                    | WampMessage::Error { payload, .. } => payload,
                    other => panic!("wrong replacement envelope: {other:?}"),
                };
                assert_eq!(received_payload.args.as_deref(), Some(expected.as_slice()));
                assert!(received_payload.kwargs.is_none());
                assert!(received_payload.transparent.is_none());
                until(|| released.load(Ordering::Acquire) == 1);
            }
            incompatible_peer
                .set_read_timeout(Some(Duration::from_millis(100)))
                .unwrap();
            let mut byte = [0];
            assert!(matches!(incompatible_peer.read(&mut byte), Err(error)
                if matches!(error.kind(), std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock)));
            assert_eq!(ct_connection_close(connection), SUCCESS);
            assert_eq!(ct_connection_close(incompatible), SUCCESS);
        }
    }
}

fn read_frame_bounded(stream: &mut TcpStream, websocket: bool, maximum: usize) -> Vec<u8> {
    if websocket {
        let mut wire = Vec::new();
        let mut fragments = 0;
        loop {
            let mut header = [0; 2];
            stream.read_exact(&mut header).unwrap();
            assert_eq!(header[0] & 0x70, 0, "reserved WebSocket bits");
            assert_eq!(
                header[0] & 0x0f,
                if fragments == 0 { 2 } else { 0 },
                "binary message followed by continuation frames"
            );
            assert_ne!(header[1] & 0x80, 0, "client frames must be masked");
            let length = match header[1] & 0x7f {
                126 => {
                    let mut bytes = [0; 2];
                    stream.read_exact(&mut bytes).unwrap();
                    u16::from_be_bytes(bytes) as usize
                }
                127 => {
                    let mut bytes = [0; 8];
                    stream.read_exact(&mut bytes).unwrap();
                    usize::try_from(u64::from_be_bytes(bytes)).unwrap()
                }
                value => value as usize,
            };
            let mut mask = [0; 4];
            stream.read_exact(&mut mask).unwrap();
            let start = wire.len();
            assert!(start
                .checked_add(length)
                .is_some_and(|length| length <= maximum));
            wire.resize(start + length, 0);
            stream.read_exact(&mut wire[start..]).unwrap();
            for (index, byte) in wire[start..].iter_mut().enumerate() {
                *byte ^= mask[index % 4];
            }
            fragments += 1;
            assert!(fragments < 32, "bounded segment/continuation count");
            if header[0] & 0x80 != 0 {
                assert!(
                    fragments > 1,
                    "segmented native frame must exercise continuations"
                );
                return wire;
            }
        }
    }
    let mut header = [0; 4];
    stream.read_exact(&mut header).unwrap();
    assert_eq!(header[0], 0);
    let length = u32::from_be_bytes(header) as usize;
    assert!(length <= maximum);
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes).unwrap();
    bytes
}

#[test]
fn native_frames_public_abi_sends_mixed_owner_fanout_over_real_rawsocket_and_websocket() {
    let _guard = test_guard();
    for websocket in [false, true] {
        let _runtime = Runtime::new();
        let (first, mut first_peer) = connect(websocket, 5);
        let (second, mut second_peer) = connect(websocket, 5);
        let mut bytes = vec![0xaa, 0xbb, 0xcc, 0x81, 0x5a];
        bytes.extend((128 * 1024u32).to_be_bytes());
        bytes.resize(3 + 6 + 128 * 1024, 0x37);
        bytes.extend([0xdd, 0xee]);
        let (owner, args, released, wrong_thread) = producer_span(bytes, 3, 6 + 128 * 1024);
        let kwargs = frozen(&[0xa1, 0x61, b'k', 1]);
        let ctrl = control(call(WampPayload::default()));
        let arg_info = buffer_info(args);
        let frame = compose_frame(ctrl, args, kwargs, 0);
        {
            let reference = frames().get(frame).unwrap();
            assert_eq!(
                reference
                    .segments
                    .iter()
                    .filter(
                        |part| part.as_ptr() == unsafe { arg_info.base.add(arg_info.offset) }
                            && part.len() == arg_info.length
                    )
                    .count(),
                1
            );
        }
        let first_send = ct_native_frame_retain(frame);
        let second_send = ct_native_frame_retain(frame);
        assert!(first_send > 0 && second_send > 0);
        let first_receipt = ct_native_frame_send_tracked(first, first_send);
        let second_receipt = ct_native_frame_send_tracked(second, second_send);
        assert!(first_receipt > 0 && second_receipt > 0);
        assert_eq!(ct_native_frame_release(first_send), ERR_INVALID_ARGUMENT);
        assert_eq!(ct_native_frame_release(second_send), ERR_INVALID_ARGUMENT);
        for handle in [ctrl, args, kwargs] {
            assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
        }
        let first_reader = thread::spawn(move || {
            let wire = read_frame(&mut first_peer, websocket);
            (first_peer, wire)
        });
        let second_reader = thread::spawn(move || {
            let wire = read_frame(&mut second_peer, websocket);
            (second_peer, wire)
        });
        until(|| {
            ct_write_receipt_state(first_receipt) == 1
                && ct_write_receipt_state(second_receipt) == 1
        });
        let (_first_peer, first_wire) = first_reader.join().unwrap();
        let (_second_peer, second_wire) = second_reader.join().unwrap();
        assert_eq!(first_wire, second_wire);
        let WampMessage::Call {
            request_id,
            procedure,
            payload,
            ..
        } = ct_core::parse_message(RawSocketSerializer::Flatbuffers, Bytes::from(first_wire))
            .unwrap()
            .message
        else {
            panic!("CALL expected")
        };
        assert_eq!(request_id, (1 << 53) - 1);
        assert_eq!(procedure, "com.example.echo");
        assert_eq!(
            &payload.args.as_ref().unwrap()[..6],
            &[0x81, 0x5a, 0, 2, 0, 0]
        );
        assert!(payload.args.as_ref().unwrap()[6..]
            .iter()
            .all(|&byte| byte == 0x37));
        assert_eq!(payload.kwargs.as_deref(), Some(&[0xa1, 0x61, b'k', 1][..]));
        assert_eq!(
            ct_external_owner_dispatch(owner, 8),
            0,
            "written receipts do not release the caller's retained frame"
        );
        assert_eq!(released.load(Ordering::Acquire), 0);
        assert_eq!(ct_native_frame_release(frame), SUCCESS);
        until(|| ct_external_owner_dispatch(owner, 8) > 0);
        assert_eq!(released.load(Ordering::Acquire), 1);
        assert!(!wrong_thread.load(Ordering::Acquire));
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
        assert_eq!(ct_write_receipt_release(first_receipt), SUCCESS);
        assert_eq!(ct_write_receipt_release(second_receipt), SUCCESS);
        assert_eq!(ct_connection_close(first), SUCCESS);
        assert_eq!(ct_connection_close(second), SUCCESS);
    }
}

#[test]
fn native_frames_public_abi_rejects_other_connection_serializers_without_emitting_a_frame() {
    let _guard = test_guard();
    for websocket in [false, true] {
        let _runtime = Runtime::new();
        let (connection, mut peer) = connect(websocket, 1);
        for tracked in [false, true] {
            let ctrl = control(call(WampPayload::default()));
            let frame = compose_frame(ctrl, 0, 0, 0);
            let retained = ct_native_frame_retain(frame);
            assert!(retained > 0);
            let result = if tracked {
                ct_native_frame_send_tracked(connection, frame)
            } else {
                ct_native_frame_send(connection, frame)
            };
            assert_eq!(result, ERR_UNSUPPORTED_SERIALIZER);
            assert_eq!(ct_native_frame_release(frame), ERR_INVALID_ARGUMENT);
            assert!(matches!(decode(retained), WampMessage::Call { .. }));
            assert_eq!(ct_native_frame_release(retained), SUCCESS);
            assert_eq!(ct_owned_buffer_release(ctrl), SUCCESS);
        }
        let barrier = ct_connection_drain_writes(connection);
        assert!(barrier > 0);
        until(|| ct_write_receipt_state(barrier) == 1);
        peer.set_read_timeout(Some(Duration::from_millis(100)))
            .unwrap();
        let mut byte = [0];
        assert!(
            matches!(peer.read(&mut byte), Err(error) if matches!(error.kind(), std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock))
        );
        assert_eq!(ct_write_receipt_release(barrier), SUCCESS);
        assert_eq!(ct_connection_close(connection), SUCCESS);
    }
}

const SLOW_PAYLOAD_LENGTH: usize = 8 * 1024 * 1024;

fn large_borrowed_arguments() -> (i32, i32, Arc<AtomicUsize>, Arc<AtomicBool>) {
    let mut bytes = vec![0xfd; SLOW_PAYLOAD_LENGTH + 8];
    bytes[1] = 0x81; // CBOR array containing one binary value.
    bytes[2] = 0x5a;
    bytes[3..7].copy_from_slice(&(SLOW_PAYLOAD_LENGTH as u32).to_be_bytes());
    for (index, byte) in bytes[7..7 + SLOW_PAYLOAD_LENGTH].iter_mut().enumerate() {
        *byte = (index % 251) as u8;
    }
    producer_span(bytes, 1, SLOW_PAYLOAD_LENGTH + 6)
}

fn owner_metrics(owner: i32) -> CtExternalOwnerMetrics {
    let mut metrics = MaybeUninit::uninit();
    assert_eq!(
        unsafe { ct_external_owner_metrics(owner, metrics.as_mut_ptr()) },
        SUCCESS
    );
    unsafe { metrics.assume_init() }
}

#[derive(Clone, Copy, Debug)]
enum StopSlowPeer {
    NativeClose,
    PeerReset,
    RuntimeShutdown,
}

fn mixed_owner_slow_fanout(websocket: bool, stop: StopSlowPeer) {
    let (owner, args, released, wrong_thread) = large_borrowed_arguments();
    let _runtime = Runtime::new();
    let (fast, mut fast_peer) = connect(websocket, 5);
    let (slow, slow_peer) = connect_with_backpressure(websocket, 5, true);
    let envelope = control(call(WampPayload::default()));
    let kwargs = frozen(&[0xa1, 0x61, b'n', 0x18, 42]);
    let frame = compose_frame(envelope, args, kwargs, 0);
    let info = buffer_info(args);
    assert!(frames().get(frame).unwrap().segments.iter().any(|segment| {
        segment.as_ptr() == info.base.wrapping_add(info.offset)
            && segment.len() == SLOW_PAYLOAD_LENGTH + 6
    }));
    let mut view = MaybeUninit::uninit();
    assert_eq!(ct_owned_buffer_export(args, view.as_mut_ptr()), SUCCESS);
    let view = unsafe { view.assume_init() };
    let reader = thread::spawn(move || {
        let wire = read_frame_bounded(&mut fast_peer, websocket, SLOW_PAYLOAD_LENGTH + 65536);
        (fast_peer, wire)
    });
    let fast_receipt = ct_native_frame_send_tracked(fast, ct_native_frame_retain(frame));
    let slow_receipt = ct_native_frame_send_tracked(slow, ct_native_frame_retain(frame));
    assert!(fast_receipt > 0 && slow_receipt > 0);
    assert_eq!(ct_native_frame_release(frame), SUCCESS);
    for handle in [envelope, args, kwargs] {
        assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
    }
    until(|| ct_write_receipt_state(fast_receipt) == 1);
    let (_fast_peer, wire) = reader.join().unwrap();
    let decoded = ct_core::parse_message(RawSocketSerializer::Flatbuffers, Bytes::from(wire))
        .unwrap()
        .message;
    let WampMessage::Call { payload, .. } = decoded else {
        panic!("expected a forwarded Call");
    };
    let encoded = payload.args.unwrap();
    assert_eq!(encoded.len(), SLOW_PAYLOAD_LENGTH + 6);
    assert_eq!(&encoded[..6], &[0x81, 0x5a, 0x00, 0x80, 0x00, 0x00]);
    assert!(encoded[6..]
        .iter()
        .enumerate()
        .all(|(index, byte)| *byte == (index % 251) as u8));
    assert_eq!(
        payload.kwargs.unwrap().as_ref(),
        &[0xa1, 0x61, b'n', 0x18, 42]
    );
    // Observe actual partial network output without draining the receiver window.
    let mut header = [0; 2];
    assert!(slow_peer.peek(&mut header).unwrap() > 0);
    assert_eq!(ct_write_receipt_state(slow_receipt), 0);
    assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
    assert_eq!(released.load(Ordering::Acquire), 0);
    assert_eq!(owner_metrics(owner).outstanding_leases, 1);
    match stop {
        StopSlowPeer::NativeClose => assert_eq!(ct_connection_close(slow), SUCCESS),
        StopSlowPeer::PeerReset => {
            socket2::SockRef::from(&slow_peer)
                .set_linger(Some(Duration::ZERO))
                .unwrap();
            drop(slow_peer);
        }
        StopSlowPeer::RuntimeShutdown => assert_eq!(ct_shutdown(), SUCCESS),
    }
    until_boundary(
        &format!("{stop:?}, websocket={websocket}: slow receipt abandonment"),
        || ct_write_receipt_state(slow_receipt) != 0,
    );
    assert_eq!(
        ct_write_receipt_state(slow_receipt),
        2,
        "{stop:?}, websocket={websocket}"
    );
    assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
    assert_eq!(
        released.load(Ordering::Acquire),
        0,
        "independent payload view remains live"
    );
    let borrowed = unsafe { std::slice::from_raw_parts(view.ptr, view.len) };
    assert_eq!(borrowed.len(), SLOW_PAYLOAD_LENGTH + 6);
    assert_eq!(&borrowed[..6], &[0x81, 0x5a, 0x00, 0x80, 0x00, 0x00]);
    assert_eq!(
        borrowed[borrowed.len() - 1],
        ((SLOW_PAYLOAD_LENGTH - 1) % 251) as u8
    );
    ct_owned_buffer_view_finalizer(view.owner);
    until(|| ct_external_owner_dispatch(owner, 8) > 0);
    assert_eq!(released.load(Ordering::Acquire), 1);
    assert!(!wrong_thread.load(Ordering::Acquire));
    assert_eq!(owner_metrics(owner).outstanding_leases, 0);
    assert_eq!(owner_metrics(owner).retained_bytes, 0);
    assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
    assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    assert_eq!(ct_write_receipt_release(fast_receipt), SUCCESS);
    assert_eq!(ct_write_receipt_release(slow_receipt), SUCCESS);
}

#[test]
fn native_frames_native_close_abandons_slow_mixed_owner_fanout() {
    let _guard = test_guard();
    for websocket in [false, true] {
        mixed_owner_slow_fanout(websocket, StopSlowPeer::NativeClose);
    }
}

#[test]
fn native_frames_peer_reset_and_shutdown_abandon_slow_mixed_owner_fanout() {
    let _guard = test_guard();
    for websocket in [false, true] {
        for stop in [StopSlowPeer::PeerReset, StopSlowPeer::RuntimeShutdown] {
            mixed_owner_slow_fanout(websocket, stop);
        }
    }
}

#[test]
fn native_frames_healthy_websocket_close_writes_queued_frame_and_close_control() {
    let _guard = test_guard();
    let _runtime = Runtime::new();
    let (connection, mut peer) = connect(true, 5);
    let length = 128 * 1024;
    let mut bytes = vec![0; length + 6];
    bytes[..6].copy_from_slice(&[0x81, 0x5a, 0x00, 0x02, 0x00, 0x00]);
    for (index, byte) in bytes[6..].iter_mut().enumerate() {
        *byte = (index % 251) as u8;
    }
    let (owner, args, released, wrong_thread) = producer_span(bytes, 0, length + 6);
    let envelope = control(call(WampPayload::default()));
    let frame = compose_frame(envelope, args, 0, 0);
    let receipt = ct_native_frame_send_tracked(connection, frame);
    assert!(receipt > 0);
    assert_eq!(ct_owned_buffer_release(envelope), SUCCESS);
    assert_eq!(ct_owned_buffer_release(args), SUCCESS);
    // Close immediately after queue acceptance, before waiting for the writer.
    assert_eq!(ct_connection_close(connection), SUCCESS);
    let wire = read_frame(&mut peer, true);
    let message = ct_core::parse_message(RawSocketSerializer::Flatbuffers, Bytes::from(wire))
        .unwrap()
        .message;
    let WampMessage::Call { payload, .. } = message else {
        panic!("queued Call was lost during healthy close");
    };
    let encoded = payload.args.unwrap();
    assert_eq!(encoded.len(), length + 6);
    assert!(encoded[6..]
        .iter()
        .enumerate()
        .all(|(index, byte)| *byte == (index % 251) as u8));
    let mut header = [0; 2];
    peer.read_exact(&mut header).unwrap();
    assert_eq!(
        header,
        [0x88, 0x82],
        "normal masked Close with two-byte status"
    );
    let mut mask = [0; 4];
    let mut status = [0; 2];
    peer.read_exact(&mut mask).unwrap();
    peer.read_exact(&mut status).unwrap();
    for (index, byte) in status.iter_mut().enumerate() {
        *byte ^= mask[index];
    }
    assert_eq!(u16::from_be_bytes(status), 1000);
    until(|| ct_write_receipt_state(receipt) == 1);
    until(|| ct_external_owner_dispatch(owner, 8) > 0);
    assert_eq!(released.load(Ordering::Acquire), 1);
    assert!(!wrong_thread.load(Ordering::Acquire));
    assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
    assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    assert_eq!(ct_write_receipt_release(receipt), SUCCESS);
}

#[cfg(feature = "ffi-test")]
#[test]
fn native_frames_queue_rejection_rolls_back_receipt_and_preserves_retained_caller() {
    let _guard = test_guard();
    for websocket in [false, true] {
        let _runtime = Runtime::new();
        let (slow, slow_peer) = connect_with_backpressure(websocket, 5, true);
        let (owner, args, released, wrong_thread) = large_borrowed_arguments();
        let envelope = control(call(WampPayload::default()));
        let frame = compose_frame(envelope, args, 0, 0);
        assert_eq!(ct_owned_buffer_release(envelope), SUCCESS);
        assert_eq!(ct_owned_buffer_release(args), SUCCESS);
        let before = ct_test_write_receipt_live_handles();
        let mut receipts = Vec::new();
        let capacity = ct_core::connection_runtime_config(ConnectionId(slow as u32))
            .unwrap()
            .outbound_send_queue_capacity;
        let mut rejected = false;
        for _ in 0..capacity + 2 {
            let submitted = ct_native_frame_retain(frame);
            assert!(submitted > 0);
            let receipt = ct_native_frame_send_tracked(slow, submitted);
            let mut info = MaybeUninit::uninit();
            assert_eq!(
                unsafe { ct_native_frame_info(submitted, info.as_mut_ptr()) },
                ERR_INVALID_ARGUMENT,
                "every native result consumes only the submitted reference"
            );
            if receipt > 0 {
                receipts.push(receipt);
            } else {
                assert_eq!(receipt, ERR_SEND_QUEUE_FULL);
                rejected = true;
                break;
            }
        }
        assert!(
            rejected,
            "bounded outbound queue must reject a blocked peer"
        );
        assert!(receipts.len() >= capacity);
        assert_eq!(
            ct_test_write_receipt_live_handles(),
            before + receipts.len()
        );
        assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
        assert_eq!(released.load(Ordering::Acquire), 0);
        assert_eq!(ct_connection_close(slow), SUCCESS);
        until_boundary("all queued frames abandoned on close", || {
            receipts
                .iter()
                .all(|receipt| ct_write_receipt_state(*receipt) == 2)
        });
        for receipt in receipts {
            assert_eq!(ct_write_receipt_release(receipt), SUCCESS);
        }
        assert_eq!(ct_test_write_receipt_live_handles(), before);
        assert_eq!(
            ct_external_owner_dispatch(owner, 8),
            0,
            "caller still retains frame"
        );
        assert_eq!(released.load(Ordering::Acquire), 0);
        // Queue rejection cannot invalidate a retained frame used on another peer.
        let (fresh, mut fresh_peer) = connect(websocket, 5);
        let reader = thread::spawn(move || {
            let wire = read_frame_bounded(&mut fresh_peer, websocket, SLOW_PAYLOAD_LENGTH + 65536);
            (fresh_peer, wire)
        });
        let receipt = ct_native_frame_send_tracked(fresh, ct_native_frame_retain(frame));
        assert!(receipt > 0);
        assert_eq!(ct_native_frame_release(frame), SUCCESS);
        until(|| ct_write_receipt_state(receipt) == 1);
        let (_fresh_peer, wire) = reader.join().unwrap();
        let message = ct_core::parse_message(RawSocketSerializer::Flatbuffers, Bytes::from(wire))
            .unwrap()
            .message;
        let WampMessage::Call { payload, .. } = message else {
            panic!("retained frame did not survive queue rejection");
        };
        let encoded = payload.args.unwrap();
        assert_eq!(encoded.len(), SLOW_PAYLOAD_LENGTH + 6);
        assert!(encoded[6..]
            .iter()
            .enumerate()
            .all(|(index, byte)| *byte == (index % 251) as u8));
        until(|| ct_external_owner_dispatch(owner, 8) > 0);
        assert_eq!(released.load(Ordering::Acquire), 1);
        assert!(!wrong_thread.load(Ordering::Acquire));
        assert_eq!(owner_metrics(owner).retained_bytes, 0);
        assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
        assert_eq!(ct_write_receipt_release(receipt), SUCCESS);
        assert_eq!(ct_test_write_receipt_live_handles(), before);
        drop(slow_peer);
    }
}
