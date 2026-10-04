use super::*;
use crate::runtime::*;
use ct_core::{WampMessage, WampPayload};
use std::mem::MaybeUninit;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicUsize};
use std::thread;

#[cfg(any(target_os = "linux", target_os = "macos"))]
mod network;

fn frozen(bytes: &[u8]) -> i32 {
    let handle = ct_owned_buffer_allocate((bytes.len() + 8) as i32);
    assert!(handle > 0);
    let info = buffer_info(handle);
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), info.base.cast_mut().add(3), bytes.len());
    }
    assert_eq!(ct_owned_buffer_freeze(handle, 3, bytes.len()), SUCCESS);
    handle
}

fn buffer_info(handle: i32) -> CtOwnedBufferInfo {
    let mut out = MaybeUninit::uninit();
    assert_eq!(ct_owned_buffer_info(handle, out.as_mut_ptr()), SUCCESS);
    unsafe { out.assume_init() }
}

fn call(payload: WampPayload) -> WampMessage {
    WampMessage::Call {
        request_id: (1 << 53) - 1,
        options: Default::default(),
        procedure: "com.example.echo".into(),
        payload,
    }
}

fn control(message: WampMessage) -> i32 {
    frozen(&ct_core::encode_flatbuffers_message(&message).unwrap())
}

fn compose_frame(control: i32, args: i32, kwargs: i32, opaque: i32) -> i32 {
    let handle = ct_native_frame_compose(store_identity(), control, args, kwargs, opaque);
    assert!(handle > 0, "valid frame composition failed: {handle}");
    handle
}

fn decode(handle: i32) -> WampMessage {
    let frame = frames().get(handle).unwrap();
    let wire: Vec<u8> = frame
        .segments
        .iter()
        .flat_map(|segment| segment.iter().copied())
        .collect();
    assert_eq!(wire.len(), frame.length);
    ct_core::parse_message(RawSocketSerializer::Flatbuffers, Bytes::from(wire))
        .unwrap()
        .message
}

#[test]
fn native_frames_retain_original_owned_ranges_and_control_views() {
    let ctrl = control(call(WampPayload::default()));
    let values = serde_cbor::to_vec(&vec![vec![0x37u8; 128 * 1024]]).unwrap();
    let args = frozen(&values);
    let kwargs = frozen(&[0xa1, 0x61, b'k', 1]);
    let arg_info = buffer_info(args);
    let kw_info = buffer_info(kwargs);
    let frame = compose_frame(ctrl, args, kwargs, 0);
    let retained = ct_native_frame_retain(frame);
    assert!(retained > 0 && retained != frame);
    let control_view = ct_native_frame_control(frame);
    assert!(control_view > 0);
    assert_eq!(buffer_info(ctrl).base, buffer_info(control_view).base);
    for (info, bytes) in [
        (arg_info, &values[..]),
        (kw_info, &[0xa1, 0x61, b'k', 1][..]),
    ] {
        let expected = unsafe { info.base.add(info.offset) };
        let reference = frames().get(frame).unwrap();
        let found: Vec<_> = reference
            .segments
            .iter()
            .filter(|part| part.as_ptr() == expected && part.len() == bytes.len())
            .collect();
        assert_eq!(
            found.len(),
            1,
            "application bytes must keep the original allocation slice"
        );
        assert_eq!(&found[0][..], bytes);
    }
    for handle in [ctrl, args, kwargs] {
        assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
    }
    assert_eq!(
        decode(frame),
        call(WampPayload {
            args: Some(Bytes::from(values)),
            kwargs: Some(Bytes::from_static(&[0xa1, 0x61, b'k', 1])),
            transparent: None
        })
    );
    assert_eq!(ct_native_frame_release(frame), SUCCESS);
    assert!(matches!(decode(retained), WampMessage::Call { .. }));
    assert_eq!(ct_native_frame_release(retained), SUCCESS);
    assert_eq!(buffer_info(control_view).writable, 0);
    assert_eq!(ct_owned_buffer_release(control_view), SUCCESS);
}

#[test]
fn native_frames_preserve_absent_empty_containers_and_empty_opaque() {
    for (args_bytes, kwargs_bytes, opaque_bytes) in [
        (None, None, None),
        (Some(&[0x80][..]), None, None),
        (None, Some(&[0xa0][..]), None),
        (None, None, Some(&[][..])),
    ] {
        let ctrl = control(call(WampPayload::default()));
        let args = args_bytes.map(frozen).unwrap_or(0);
        let kwargs = kwargs_bytes.map(frozen).unwrap_or(0);
        let opaque = opaque_bytes.map(frozen).unwrap_or(0);
        let frame = compose_frame(ctrl, args, kwargs, opaque);
        let WampMessage::Call { payload, .. } = decode(frame) else {
            panic!("CALL expected")
        };
        assert_eq!(payload.args.as_deref(), args_bytes);
        assert_eq!(payload.kwargs.as_deref(), kwargs_bytes);
        assert_eq!(payload.transparent.as_deref(), opaque_bytes);
        assert_eq!(ct_native_frame_release(frame), SUCCESS);
        for handle in [ctrl, args, kwargs, opaque].into_iter().filter(|h| *h != 0) {
            assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
        }
    }
    let ctrl = control(call(WampPayload {
        transparent: Some(Bytes::new()),
        ..Default::default()
    }));
    let opaque = frozen(&[0, 255, 128]);
    let frame = compose_frame(ctrl, 0, 0, opaque);
    assert_eq!(
        decode(frame),
        call(WampPayload {
            transparent: Some(Bytes::from_static(&[0, 255, 128])),
            ..Default::default()
        })
    );
    assert_eq!(ct_native_frame_release(frame), SUCCESS);
    assert_eq!(ct_owned_buffer_release(ctrl), SUCCESS);
    assert_eq!(ct_owned_buffer_release(opaque), SUCCESS);
}

#[test]
fn native_frames_reject_cbor_root_truncation_keys_and_payload_conflicts_without_consuming() {
    let ctrl = control(call(WampPayload::default()));
    for (bytes, keyword) in [
        (&[][..], false),
        (&[][..], true),
        (&[0xa0][..], false),
        (&[0x80][..], true),
        (&[0x81][..], false),
        (&[0x80, 0][..], false),
        (&[0xa1, 1, 2][..], true),
        (&[0xa2, 0x61, b'k', 1, 0x61, b'k', 2][..], true),
    ] {
        let payload = frozen(bytes);
        let (args, kwargs) = if keyword { (0, payload) } else { (payload, 0) };
        assert_eq!(
            ct_native_frame_compose(store_identity(), ctrl, args, kwargs, 0),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(buffer_info(ctrl).writable, 0);
        assert_eq!(buffer_info(payload).length, bytes.len());
        assert_eq!(ct_owned_buffer_release(payload), SUCCESS);
    }
    let args = frozen(&[0x80]);
    let opaque = frozen(&[]);
    assert_eq!(
        ct_native_frame_compose(store_identity(), ctrl, args, 0, opaque),
        ERR_INVALID_ARGUMENT
    );
    let opaque_ctrl = control(call(WampPayload {
        transparent: Some(Bytes::new()),
        ..Default::default()
    }));
    assert_eq!(
        ct_native_frame_compose(store_identity(), opaque_ctrl, args, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    for handle in [ctrl, args, opaque, opaque_ctrl] {
        assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
    }
}

#[test]
fn native_frames_reject_wrong_identity_mutable_handles_and_envelope_payloads() {
    let ctrl = control(call(WampPayload::default()));
    let payload = frozen(&[0x80]);
    let wrong_identity: u8 = 0;
    assert_eq!(
        ct_native_frame_compose((&wrong_identity as *const u8).cast(), ctrl, payload, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    let mutable = ct_owned_buffer_allocate(8);
    assert!(mutable > 0);
    assert_eq!(
        ct_native_frame_compose(store_identity(), ctrl, mutable, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_native_frame_compose(store_identity(), mutable, 0, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    let malformed = frozen(&[0, 1, 2]);
    assert_eq!(
        ct_native_frame_compose(store_identity(), malformed, payload, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    let populated = control(call(WampPayload {
        args: Some(Bytes::from_static(&[0x80])),
        ..Default::default()
    }));
    assert_eq!(
        ct_native_frame_compose(store_identity(), populated, 0, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    let hello = control(WampMessage::Hello {
        realm: "com.realm".into(),
        details: Default::default(),
    });
    assert_eq!(
        ct_native_frame_compose(store_identity(), hello, payload, 0, 0),
        ERR_INVALID_ARGUMENT
    );
    let ordinary = compose_frame(hello, 0, 0, 0);
    assert_eq!(frames().get(ordinary).unwrap().segments.len(), 1);
    assert_eq!(ct_native_frame_release(ordinary), SUCCESS);
    assert_eq!(buffer_info(mutable).writable, 1);
    for handle in [ctrl, payload, mutable, malformed, populated, hello] {
        assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
    }
}

#[test]
fn native_frames_transfer_rejection_consumes_only_submitted_reference() {
    for tracked in [false, true] {
        let ctrl = control(call(WampPayload::default()));
        let frame = compose_frame(ctrl, 0, 0, 0);
        let retained = ct_native_frame_retain(frame);
        assert!(retained > 0);
        let result = if tracked {
            ct_native_frame_send_tracked(0, frame)
        } else {
            ct_native_frame_send(0, frame)
        };
        assert_eq!(result, ERR_INVALID_ARGUMENT);
        assert_eq!(ct_native_frame_release(frame), ERR_INVALID_ARGUMENT);
        assert!(matches!(decode(retained), WampMessage::Call { .. }));
        assert_eq!(ct_native_frame_release(retained), SUCCESS);
        assert_eq!(ct_owned_buffer_release(ctrl), SUCCESS);
    }
}

#[test]
fn native_frames_bounded_store_rollback_and_non_recycled_ids() {
    let ctrl = control(call(WampPayload::default()));
    let frame = compose(store_identity(), ctrl, 0, 0, 0).unwrap();
    let store = FrameStore::new(1);
    let first = store.insert(frame.clone()).unwrap();
    assert_eq!(store.insert(frame.clone()), Err(ERR_HANDLE_UNAVAILABLE));
    assert_eq!(store.count.load(Ordering::Acquire), 1);
    drop(store.take(first).unwrap());
    assert!(store.get(first).is_err());
    assert_eq!(store.count.load(Ordering::Acquire), 0);
    let second = store.insert(frame).unwrap();
    assert_ne!(first, second);
    drop(store.take(second).unwrap());
    assert_eq!(ct_owned_buffer_release(ctrl), SUCCESS);
}

struct ProducerResource {
    bytes: Vec<u8>,
    thread: thread::ThreadId,
    released: Arc<AtomicUsize>,
    wrong_thread: Arc<AtomicBool>,
}

unsafe extern "C" fn release_resource(token: *mut c_void) {
    let resource = unsafe { Box::from_raw(token.cast::<ProducerResource>()) };
    resource
        .wrong_thread
        .store(resource.thread != thread::current().id(), Ordering::Release);
    resource.released.fetch_add(1, Ordering::AcqRel);
}

fn producer(length: usize) -> (i32, i32, Arc<AtomicUsize>, Arc<AtomicBool>) {
    producer_span(vec![0xfe, 0x80, 0xfd], 1, length)
}

fn producer_span(
    bytes: Vec<u8>,
    offset: usize,
    length: usize,
) -> (i32, i32, Arc<AtomicUsize>, Arc<AtomicBool>) {
    let released = Arc::new(AtomicUsize::new(0));
    let wrong_thread = Arc::new(AtomicBool::new(false));
    let owner = ct_external_owner_create(bytes.len(), 1);
    assert!(owner > 0);
    let resource = Box::new(ProducerResource {
        bytes,
        thread: thread::current().id(),
        released: released.clone(),
        wrong_thread: wrong_thread.clone(),
    });
    let base = resource.bytes.as_ptr();
    let span_length = resource.bytes.len();
    let token = Box::into_raw(resource).cast();
    let mut buffer = CtExternalBufferToken {
        handle: 0,
        identity: ptr::null(),
    };
    assert_eq!(
        unsafe {
            ct_external_buffer_register(
                owner,
                base,
                span_length,
                offset,
                length,
                Some(release_resource),
                token,
                &mut buffer,
            )
        },
        SUCCESS
    );
    assert_eq!(buffer.identity, store_identity());
    (owner, buffer.handle, released, wrong_thread)
}

#[test]
fn native_frames_fanout_and_empty_external_spans_keep_producer_affine_release() {
    for length in [0, 1] {
        let ctrl = control(call(WampPayload::default()));
        let (owner, payload, released, wrong_thread) = producer(length);
        let frame = if length == 0 {
            compose_frame(ctrl, 0, 0, payload)
        } else {
            compose_frame(ctrl, payload, 0, 0)
        };
        let first = frames().get(frame).unwrap().submission();
        let second = frames().get(frame).unwrap().submission();
        assert_eq!(ct_owned_buffer_release(ctrl), SUCCESS);
        assert_eq!(ct_owned_buffer_release(payload), SUCCESS);
        assert_eq!(ct_native_frame_release(frame), SUCCESS);
        assert_eq!(released.load(Ordering::Acquire), 0);
        thread::spawn(move || drop(first)).join().unwrap();
        assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
        assert_eq!(released.load(Ordering::Acquire), 0);
        thread::spawn(move || {
            drop(second);
            assert_eq!(ct_external_owner_dispatch(owner, 8), ERR_LEASE_WRONG_THREAD);
        })
        .join()
        .unwrap();
        assert_eq!(released.load(Ordering::Acquire), 0);
        assert_eq!(ct_external_owner_dispatch(owner, 8), 1);
        assert_eq!(released.load(Ordering::Acquire), 1);
        assert!(!wrong_thread.load(Ordering::Acquire));
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    }
}

#[test]
fn native_frames_composition_failure_releases_staging_refs_without_consuming_producer() {
    let ctrl = control(call(WampPayload::default()));
    let (owner, args, released, wrong_thread) = producer(1);
    let bad_kwargs = frozen(&[0x80]);
    assert_eq!(
        ct_native_frame_compose(store_identity(), ctrl, args, bad_kwargs, 0),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
    assert_eq!(buffer_info(args).length, 1);
    assert_eq!(released.load(Ordering::Acquire), 0);
    assert_eq!(ct_owned_buffer_release(args), SUCCESS);
    assert_eq!(ct_external_owner_dispatch(owner, 8), 1);
    assert_eq!(released.load(Ordering::Acquire), 1);
    assert!(!wrong_thread.load(Ordering::Acquire));
    assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    assert_eq!(ct_owned_buffer_release(ctrl), SUCCESS);
    assert_eq!(ct_owned_buffer_release(bad_kwargs), SUCCESS);
}
