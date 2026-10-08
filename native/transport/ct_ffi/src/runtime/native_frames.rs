//! Immutable segmented frames retain owned and external allocations without
//! concatenating application vectors. Handles survive runtime shutdown.

use super::constants::*;
use super::owned_buffers::{borrow_frozen, retain_frozen_buffer, store_identity, Frozen};
use super::resource_handles::insert_resource;
use super::write_receipts::submit_tracked;
use bytes::Bytes;
use ct_core::{ConnectionId, RawSocketSerializer, WampPayload};
use dashmap::DashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicU32, AtomicUsize, Ordering};
use std::sync::{Arc, OnceLock};

const MAX_HANDLES: usize = 8192;

struct Frame {
    control: Frozen,
    // Empty slices still have an owner even when Bytes::slice can elide it.
    _application_owners: Vec<Frozen>,
    segments: Vec<Bytes>,
    length: usize,
}

struct FrameHeader(Arc<Frame>, usize);

impl AsRef<[u8]> for FrameHeader {
    fn as_ref(&self) -> &[u8] {
        &self.0.segments[self.1]
    }
}

impl Frame {
    fn submission(self: Arc<Self>) -> Vec<Bytes> {
        let mut segments = self.segments.clone();
        // The writer borrows the complete segment vector through write/flush.
        // This owner also retains the original control and empty producer spans.
        // An empty Bytes may discard its owner. Anchor every allocation on a
        // nonempty segment, even when the caller starts with an empty span.
        let index = segments.iter().position(|part| !part.is_empty()).unwrap();
        segments[index] = Bytes::from_owner(FrameHeader(self, index));
        segments
    }
}

struct FrameStore {
    next: AtomicU32,
    count: AtomicUsize,
    maximum: usize,
    entries: DashMap<u32, Arc<Frame>>,
}

impl FrameStore {
    fn new(maximum: usize) -> Self {
        Self {
            next: AtomicU32::new(1),
            count: AtomicUsize::new(0),
            maximum,
            entries: DashMap::new(),
        }
    }

    fn insert(&self, frame: Arc<Frame>) -> Result<i32, i32> {
        self.count
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |count| {
                (count < self.maximum).then(|| count + 1)
            })
            .map_err(|_| ERR_HANDLE_UNAVAILABLE)?;
        match insert_resource(&self.next, &self.entries, frame) {
            Ok(handle) => Ok(handle as i32),
            Err(_) => {
                self.count.fetch_sub(1, Ordering::AcqRel);
                Err(ERR_HANDLE_UNAVAILABLE)
            }
        }
    }

    fn get(&self, handle: i32) -> Result<Arc<Frame>, i32> {
        if handle <= 0 {
            return Err(ERR_INVALID_ARGUMENT);
        }
        self.entries
            .get(&(handle as u32))
            .map(|entry| Arc::clone(entry.value()))
            .ok_or(ERR_INVALID_ARGUMENT)
    }

    fn take(&self, handle: i32) -> Result<Arc<Frame>, i32> {
        if handle <= 0 {
            return Err(ERR_INVALID_ARGUMENT);
        }
        let (_, frame) = self
            .entries
            .remove(&(handle as u32))
            .ok_or(ERR_INVALID_ARGUMENT)?;
        self.count.fetch_sub(1, Ordering::AcqRel);
        Ok(frame)
    }
}

fn frames() -> &'static FrameStore {
    static STORE: OnceLock<FrameStore> = OnceLock::new();
    STORE.get_or_init(|| FrameStore::new(MAX_HANDLES))
}

fn optional_buffer(handle: i32) -> Result<Option<Frozen>, i32> {
    if handle == 0 {
        Ok(None)
    } else {
        borrow_frozen(handle).map(Some)
    }
}

fn compose(
    identity: *const c_void,
    control: i32,
    args: i32,
    kwargs: i32,
    opaque: i32,
) -> Result<Arc<Frame>, i32> {
    if identity != store_identity() {
        return Err(ERR_INVALID_ARGUMENT);
    }
    // All staging references unwind on every validation or publication error;
    // no input handle is taken and no foreign pointer is adopted as a Vec.
    let control = borrow_frozen(control)?;
    let args = optional_buffer(args)?;
    let kwargs = optional_buffer(kwargs)?;
    let opaque = optional_buffer(opaque)?;
    let payload = WampPayload {
        args: args.as_ref().map(Frozen::bytes),
        kwargs: kwargs.as_ref().map(Frozen::bytes),
        transparent: opaque.as_ref().map(Frozen::bytes),
    };
    let segments = ct_core::compose_flatbuffers_message_segments(control.bytes(), payload)
        .map_err(|_| ERR_INVALID_ARGUMENT)?;
    let length = segments
        .iter()
        .try_fold(0usize, |sum, segment| sum.checked_add(segment.len()))
        .ok_or(ERR_INVALID_ARGUMENT)?;
    Ok(Arc::new(Frame {
        control,
        _application_owners: [args, kwargs, opaque].into_iter().flatten().collect(),
        segments,
        length,
    }))
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CtNativeFrameInfo {
    pub length: usize,
    pub segments: usize,
}

#[no_mangle]
pub extern "C" fn ct_native_frame_abi_version() -> u32 {
    1
}

/// Retains immutable handles from this library's owned-buffer store. Zero means
/// an absent application vector; an empty opaque buffer is present. Input
/// handles remain valid on both success and error. Returns a positive frame
/// handle, or error. Ordinary args/kwargs must be encoded CBOR array/dictionary.
#[no_mangle]
pub extern "C" fn ct_native_frame_compose(
    identity: *const c_void,
    control: i32,
    args: i32,
    kwargs: i32,
    opaque: i32,
) -> i32 {
    compose(identity, control, args, kwargs, opaque)
        .and_then(|frame| frames().insert(frame))
        .unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_native_frame_retain(handle: i32) -> i32 {
    frames()
        .get(handle)
        .and_then(|frame| frames().insert(frame))
        .unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_native_frame_release(handle: i32) -> i32 {
    frames()
        .take(handle)
        .map(|_| SUCCESS)
        .unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_native_frame_finalizer(token: *mut c_void) {
    let handle = token as usize;
    if handle > 0 && handle <= i32::MAX as usize {
        let _ = frames().take(handle as i32);
    }
}

/// # Safety
/// A nonnull output must be aligned and writable for CtNativeFrameInfo.
#[no_mangle]
pub unsafe extern "C" fn ct_native_frame_info(handle: i32, out: *mut CtNativeFrameInfo) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match frames().get(handle) {
        Ok(frame) => {
            unsafe {
                out.write(CtNativeFrameInfo {
                    length: frame.length,
                    segments: frame.segments.len(),
                });
            }
            SUCCESS
        }
        Err(error) => error,
    }
}

/// A new frozen owned-buffer handle retaining the actual control bytes. No
/// flattening occurs; this handle carries no application vector bytes.
#[no_mangle]
pub extern "C" fn ct_native_frame_control(handle: i32) -> i32 {
    frames()
        .get(handle)
        .and_then(|frame| retain_frozen_buffer(&frame.control))
        .unwrap_or_else(|error| error)
}

fn submit(connection: i32, handle: i32, tracked: bool) -> i32 {
    let frame = match frames().take(handle) {
        Ok(frame) => frame,
        Err(error) => return error,
    };
    if connection <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection = ConnectionId(connection as u32);
    match ct_core::connection_serializer(connection) {
        Ok(RawSocketSerializer::Flatbuffers) => {}
        Ok(_) => return ERR_UNSUPPORTED_SERIALIZER,
        Err(error) => return super::ffi::map_error(error),
    }
    if tracked {
        submit_tracked(|| ct_core::send_wamp_segments_tracked(connection, frame.submission()))
    } else {
        ct_core::send_wamp_segments(connection, frame.submission())
            .map(|_| SUCCESS)
            .unwrap_or_else(super::ffi::map_error)
    }
}

/// Consumes one valid frame handle on acceptance and every connection/queue
/// rejection. Retain first to preserve a caller reference. No payload is copied.
#[no_mangle]
pub extern "C" fn ct_native_frame_send(connection: i32, frame: i32) -> i32 {
    submit(connection, frame, false)
}

/// Like send, returning a positive bounded local write receipt on acceptance.
/// The receipt covers the entire segmented frame and flush, not peer delivery
/// or the lifetime of caller-retained frames/views.
#[no_mangle]
pub extern "C" fn ct_native_frame_send_tracked(connection: i32, frame: i32) -> i32 {
    submit(connection, frame, true)
}

const MAX_OWNED_SEGMENTS: usize = 64;

fn compose_owned_segments(identity: *const c_void, handles: &[i32]) -> Result<Arc<Frame>, i32> {
    if identity != store_identity() || handles.is_empty() || handles.len() > MAX_OWNED_SEGMENTS {
        return Err(ERR_INVALID_ARGUMENT);
    }
    let mut owners = handles
        .iter()
        .map(|&handle| borrow_frozen(handle))
        .collect::<Result<Vec<_>, _>>()?;
    let segments: Vec<_> = owners.iter().map(Frozen::bytes).collect();
    let length = segments
        .iter()
        .try_fold(0usize, |sum, part| sum.checked_add(part.len()))
        .filter(|&length| length > 0)
        .ok_or(ERR_INVALID_ARGUMENT)?;
    let control = owners.remove(0);
    Ok(Arc::new(Frame {
        control,
        _application_owners: owners,
        segments,
        length,
    }))
}

unsafe fn submit_owned_segments(
    identity: *const c_void,
    connection: i32,
    handles: *const i32,
    count: usize,
    tracked: bool,
) -> i32 {
    // Check all scalar arguments before reading the caller's handle array.
    if identity != store_identity()
        || connection <= 0
        || handles.is_null()
        || count == 0
        || count > MAX_OWNED_SEGMENTS
    {
        return ERR_INVALID_ARGUMENT;
    }
    let frame = match compose_owned_segments(identity, unsafe {
        std::slice::from_raw_parts(handles, count)
    }) {
        Ok(frame) => frame,
        Err(error) => return error,
    };
    let connection = ConnectionId(connection as u32);
    if tracked {
        submit_tracked(|| ct_core::send_wamp_segments_tracked(connection, frame.submission()))
    } else {
        ct_core::send_wamp_segments(connection, frame.submission())
            .map(|_| SUCCESS)
            .unwrap_or_else(super::ffi::map_error)
    }
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_segments_abi_version() -> u32 {
    1
}

/// Queues a complete, already encoded WAMP frame from 1–64 frozen native
/// buffers in this store, with at least one nonempty segment. Retains every
/// allocation through write/flush, including empty producer spans. No input
/// handle is consumed on success or error; no byte allocation is adopted or
/// copied. The caller chooses the encoding matching the connection.
///
/// # Safety
/// For a valid identity, connection and count, handles must point to count
/// initialized, aligned, readable i32 values for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn ct_owned_buffer_send_segments(
    identity: *const c_void,
    connection: i32,
    handles: *const i32,
    count: usize,
) -> i32 {
    unsafe { submit_owned_segments(identity, connection, handles, count, false) }
}

/// Like ct_owned_buffer_send_segments, returning a bounded local write receipt.
/// Written means complete write and flush, not peer delivery or release of
/// caller-retained handles/views. Inputs remain valid on every result.
///
/// # Safety
/// Same readable handle-array requirements as ct_owned_buffer_send_segments.
#[no_mangle]
pub unsafe extern "C" fn ct_owned_buffer_send_segments_tracked(
    identity: *const c_void,
    connection: i32,
    handles: *const i32,
    count: usize,
) -> i32 {
    unsafe { submit_owned_segments(identity, connection, handles, count, true) }
}

#[cfg(test)]
mod tests;
