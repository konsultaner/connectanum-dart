use crate::runtime::*;
use crate::tests::test_guard;
use base64::{engine::general_purpose::STANDARD, Engine};
use sha1::{Digest, Sha1};
use std::ffi::{c_void, CString};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc};
use std::thread::{self, JoinHandle, ThreadId};
use std::time::{Duration, Instant};

const LENGTH: usize = 8 * 1024 * 1024;
const PREFIX: &[u8] = b"[48,42,{},\"com.example.proc\",[\"";
const SUFFIX: &[u8] = b"\"]]";

fn valid_payload(data: &[u8]) -> bool {
    data.len() == LENGTH
        && data.starts_with(PREFIX)
        && data.ends_with(SUFFIX)
        && data[PREFIX.len()..LENGTH - SUFFIX.len()]
            .iter()
            .all(|&byte| byte == b'A')
}

#[derive(Default)]
struct Statistics {
    released: AtomicUsize,
    wrong_thread: AtomicBool,
    corrupted: AtomicBool,
    stop: AtomicBool,
}

struct Transaction {
    data: Vec<u8>,
    creator: ThreadId,
    statistics: Arc<Statistics>,
}

unsafe extern "C" fn release_transaction(token: *mut c_void) {
    let transaction = unsafe { Box::from_raw(token.cast::<Transaction>()) };
    let statistics = transaction.statistics.clone();
    statistics.wrong_thread.store(
        transaction.creator != thread::current().id(),
        Ordering::Release,
    );
    statistics
        .corrupted
        .store(!valid_payload(&transaction.data), Ordering::Release);
    drop(transaction);
    statistics.released.fetch_add(1, Ordering::AcqRel);
}

struct Producer {
    handle: i32,
    owner: i32,
    base: usize,
    statistics: Arc<Statistics>,
    thread: Option<JoinHandle<()>>,
}

impl Producer {
    fn new() -> Self {
        let statistics = Arc::new(Statistics::default());
        let worker_statistics = statistics.clone();
        let (ready, result) = mpsc::channel();
        let worker = thread::spawn(move || {
            let owner = ct_external_owner_create(LENGTH, 1);
            assert!(owner > 0);
            let mut data = vec![b'A'; LENGTH];
            data[..PREFIX.len()].copy_from_slice(PREFIX);
            data[LENGTH - SUFFIX.len()..].copy_from_slice(SUFFIX);
            let base = data.as_ptr();
            let token = Box::into_raw(Box::new(Transaction {
                data,
                creator: thread::current().id(),
                statistics: worker_statistics.clone(),
            }))
            .cast();
            let mut buffer = CtExternalBufferToken {
                handle: 0,
                identity: ptr::null(),
            };
            let status = unsafe {
                ct_external_buffer_register(
                    owner,
                    base,
                    LENGTH,
                    0,
                    LENGTH,
                    Some(release_transaction),
                    token,
                    &mut buffer,
                )
            };
            assert_eq!(status, SUCCESS);
            ready.send((owner, buffer.handle, base as usize)).unwrap();
            loop {
                let stop = worker_statistics.stop.load(Ordering::Acquire);
                if stop {
                    assert!(matches!(
                        ct_external_owner_close(owner),
                        SUCCESS | ERR_LEASE_BUSY
                    ));
                }
                assert!(ct_external_owner_dispatch(owner, 16) >= 0);
                if stop && ct_external_owner_destroy(owner) == SUCCESS {
                    break;
                }
                assert!(ct_external_owner_wait(owner, 20) >= 0);
            }
        });
        let (owner, handle, base) = result.recv_timeout(Duration::from_secs(3)).unwrap();
        Self {
            handle,
            owner,
            base,
            statistics,
            thread: Some(worker),
        }
    }

    fn metrics(&self) -> CtExternalOwnerMetrics {
        let mut metrics = std::mem::MaybeUninit::uninit();
        assert_eq!(
            unsafe { ct_external_owner_metrics(self.owner, metrics.as_mut_ptr()) },
            SUCCESS
        );
        unsafe { metrics.assume_init() }
    }

    fn assert_released(&self) {
        until("owner-affine producer release", || {
            self.statistics.released.load(Ordering::Acquire) == 1
        });
        until("external lease release", || {
            self.metrics().outstanding_leases == 0
        });
        assert_eq!(self.metrics().retained_bytes, 0);
        assert!(!self.statistics.wrong_thread.load(Ordering::Acquire));
        assert!(!self.statistics.corrupted.load(Ordering::Acquire));
    }
}

impl Drop for Producer {
    fn drop(&mut self) {
        // Valid stale release is harmless; fixtures retain no hidden loan.
        let _ = ct_owned_buffer_release(self.handle);
        self.statistics.stop.store(true, Ordering::Release);
        if let Some(worker) = self.thread.take() {
            worker.join().unwrap();
        }
    }
}

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

struct View(CtMessageByteView);
impl View {
    fn new(handle: i32) -> Self {
        let mut out = std::mem::MaybeUninit::uninit();
        assert_eq!(ct_owned_buffer_export(handle, out.as_mut_ptr()), SUCCESS);
        Self(unsafe { out.assume_init() })
    }
}
impl Drop for View {
    fn drop(&mut self) {
        ct_owned_buffer_view_finalizer(self.0.owner);
    }
}

struct Receipt(i32);
impl Receipt {
    fn new(connection: i32, buffer: i32) -> Self {
        let receipt = ct_owned_buffer_send_tracked(connection, buffer);
        assert!(receipt > 0);
        Self(receipt)
    }
    fn outcome(&self) -> i32 {
        ct_write_receipt_state(self.0)
    }
}
impl Drop for Receipt {
    fn drop(&mut self) {
        assert_eq!(ct_write_receipt_release(self.0), SUCCESS);
    }
}

fn until(boundary: &str, predicate: impl Fn() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !predicate() {
        assert!(
            Instant::now() < deadline,
            "native terminal boundary did not arrive: {boundary}"
        );
        thread::sleep(Duration::from_millis(1));
    }
}

fn connect(websocket: bool, slow: bool) -> (i32, TcpStream) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let (ready, receiver) = mpsc::channel();
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
            let response = format!("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\nSec-WebSocket-Protocol: wamp.2.json\r\n\r\n");
            stream.write_all(response.as_bytes()).unwrap();
        } else {
            let mut handshake = [0; 4];
            stream.read_exact(&mut handshake).unwrap();
            assert_eq!(handshake[0], 0x7f);
            stream.write_all(&handshake).unwrap();
        }
        ready.send(stream).unwrap();
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
            1,
            ptr::null(),
            0,
            0,
            0,
        )
    } else {
        ct_client_connect_rawsocket(host.as_ptr(), port.into(), 0, 0, 1, 24, 0, 0)
    };
    assert!(connection > 0);
    let stream = receiver.recv_timeout(Duration::from_secs(5)).unwrap();
    peer.join().unwrap();
    (connection, stream)
}

fn read_payload_prefix(stream: &mut TcpStream, websocket: bool) -> (Vec<u8>, Option<[u8; 4]>) {
    let mut mask = None;
    let length = if websocket {
        let mut header = [0; 2];
        stream.read_exact(&mut header).unwrap();
        assert_eq!(header[0], 0x81);
        assert_eq!(header[1], 0xff);
        let mut length = [0; 8];
        stream.read_exact(&mut length).unwrap();
        let mut key = [0; 4];
        stream.read_exact(&mut key).unwrap();
        mask = Some(key);
        u64::from_be_bytes(length) as usize
    } else {
        let mut header = [0; 4];
        stream.read_exact(&mut header).unwrap();
        assert_eq!(header[0], 0);
        u32::from_be_bytes(header) as usize
    };
    assert_eq!(length, LENGTH);
    let mut payload = vec![0; PREFIX.len()];
    stream.read_exact(&mut payload).unwrap();
    if let Some(mask) = mask {
        for (index, byte) in payload.iter_mut().enumerate() {
            *byte ^= mask[index % 4];
        }
    }
    assert_eq!(payload, PREFIX);
    (payload, mask)
}

fn read_payload_rest(
    stream: &mut TcpStream,
    (mut payload, mask): (Vec<u8>, Option<[u8; 4]>),
) -> Vec<u8> {
    let received = payload.len();
    payload.resize(LENGTH, 0);
    stream.read_exact(&mut payload[received..]).unwrap();
    if let Some(mask) = mask {
        for (index, byte) in payload.iter_mut().enumerate().skip(received) {
            *byte ^= mask[index % 4];
        }
    }
    payload
}

fn read_payload(stream: &mut TcpStream, websocket: bool) -> Vec<u8> {
    let prefix = read_payload_prefix(stream, websocket);
    read_payload_rest(stream, prefix)
}

#[test]
fn registered_transaction_fanout_survives_disconnect_and_shutdown() {
    #[derive(Clone, Copy, Debug)]
    enum Termination {
        PeerReset,
        ConnectionClose,
        RuntimeShutdown,
    }
    let _guard = test_guard();
    for websocket in [false, true] {
        for termination in [
            Termination::PeerReset,
            Termination::ConnectionClose,
            Termination::RuntimeShutdown,
        ] {
            let producer = Producer::new();
            let _runtime = Runtime::new();
            let (fast, mut fast_peer) = connect(websocket, false);
            let (slow, mut slow_peer) = connect(websocket, true);
            let mut view = Some(View::new(producer.handle));
            assert_eq!(view.as_ref().unwrap().0.ptr as usize, producer.base);
            assert_eq!(view.as_ref().unwrap().0.len, LENGTH);
            let copy = ct_owned_buffer_slice(producer.handle, 0, LENGTH);
            assert!(copy > 0);
            let mut info = std::mem::MaybeUninit::uninit();
            assert_eq!(ct_owned_buffer_info(copy, info.as_mut_ptr()), SUCCESS);
            let info = unsafe { info.assume_init() };
            assert_eq!(info.base as usize, producer.base);
            assert_eq!(info.writable, 0);
            let reader = thread::spawn(move || {
                let payload = read_payload(&mut fast_peer, websocket);
                // Reading the final byte does not prove the local writer has
                // published its receipt. Keep the peer open until that boundary.
                (fast_peer, payload)
            });
            let fast_receipt = Receipt::new(fast, copy);
            let slow_receipt = Receipt::new(slow, producer.handle);
            // Observe actual payload progress before interrupting this write.
            // The fixed small receive window cannot accept the full 8 MiB body.
            let _partial_payload = read_payload_prefix(&mut slow_peer, websocket);
            until("fast local write", || fast_receipt.outcome() == 1);
            let (_fast_peer, payload) = reader.join().unwrap();
            assert!(valid_payload(&payload));
            // The slow receiver has consumed only the verified payload prefix.
            thread::sleep(Duration::from_millis(30));
            assert_eq!(slow_receipt.outcome(), 0);
            assert_eq!(producer.statistics.released.load(Ordering::Acquire), 0);
            assert_eq!(producer.metrics().retained_bytes, LENGTH);
            assert_eq!(producer.metrics().outstanding_leases, 1);
            if !matches!(termination, Termination::RuntimeShutdown) {
                drop(view.take());
                thread::sleep(Duration::from_millis(30));
                assert_eq!(
                    producer.statistics.released.load(Ordering::Acquire),
                    0,
                    "slow writer must retain the actual loan, not a copied payload"
                );
            }
            match termination {
                Termination::RuntimeShutdown => assert_eq!(ct_shutdown(), SUCCESS),
                Termination::ConnectionClose => assert_eq!(ct_connection_close(slow), SUCCESS),
                Termination::PeerReset => {
                    // FIN does not guarantee an interrupted local write. Reset
                    // the partially read peer to exercise actual abandonment.
                    socket2::SockRef::from(&slow_peer)
                        .set_linger(Some(Duration::ZERO))
                        .unwrap();
                    drop(slow_peer);
                }
            }
            let boundary =
                format!("slow local write abandonment (websocket={websocket}, {termination:?})");
            until(&boundary, || slow_receipt.outcome() != 0);
            assert_eq!(slow_receipt.outcome(), 2, "{boundary}");
            // Runtime/socket termination leaves the independent exported owner.
            if let Some(view) = view.as_ref() {
                assert_eq!(producer.statistics.released.load(Ordering::Acquire), 0);
                let bytes = unsafe { std::slice::from_raw_parts(view.0.ptr, view.0.len) };
                assert!(valid_payload(bytes));
            }
            drop(view.take());
            producer.assert_released();
        }
    }
}

#[test]
fn disposing_receipt_does_not_cancel_borrowed_write_or_release_loan() {
    let _guard = test_guard();
    for websocket in [false, true] {
        let producer = Producer::new();
        let _runtime = Runtime::new();
        let (connection, mut peer) = connect(websocket, true);
        let view = View::new(producer.handle);
        assert_eq!(view.0.ptr as usize, producer.base);
        drop(view);
        let receipt = Receipt::new(connection, producer.handle);
        let prefix = read_payload_prefix(&mut peer, websocket);
        assert_eq!(receipt.outcome(), 0);
        let handle = receipt.0;
        drop(receipt);
        assert_eq!(ct_write_receipt_state(handle), ERR_INVALID_ARGUMENT);
        assert_eq!(producer.statistics.released.load(Ordering::Acquire), 0);
        assert_eq!(producer.metrics().outstanding_leases, 1);
        assert_eq!(producer.metrics().retained_bytes, LENGTH);
        // There are no caller-held views or handles. Only the native writer can
        // keep the foreign memory live after its receipt observer is disposed.
        let barrier = ct_connection_drain_writes(connection);
        assert!(barrier > 0);
        let barrier = Receipt(barrier);
        assert_eq!(barrier.outcome(), 0);
        socket2::SockRef::from(&peer)
            .set_recv_buffer_size(LENGTH)
            .unwrap();
        let payload = read_payload_rest(&mut peer, prefix);
        assert!(valid_payload(&payload));
        until("unobserved write and FIFO flush", || barrier.outcome() == 1);
        producer.assert_released();
    }
}

#[test]
fn full_transport_queue_rejects_foreign_loan_without_releasing_active_send() {
    let _guard = test_guard();
    for websocket in [false, true] {
        let active = Producer::new();
        let rejected = Producer::new();
        let _runtime = Runtime::new();
        let (connection, mut peer) = connect(websocket, true);
        let receipt = Receipt::new(connection, active.handle);
        let _partial_payload = read_payload_prefix(&mut peer, websocket);
        assert_eq!(receipt.outcome(), 0);
        let mut queue_full = false;
        for _ in 0..4096 {
            match ct_core::send_wamp_message(
                ct_core::ConnectionId(connection as u32),
                bytes::Bytes::from_static(b"[]"),
            ) {
                Ok(()) => {}
                Err(ct_core::Error::SendQueueFull(_)) => {
                    queue_full = true;
                    break;
                }
                other => panic!("unexpected queue admission outcome: {other:?}"),
            }
        }
        assert!(queue_full, "stalled native transport queue must be bounded");
        assert_eq!(
            ct_owned_buffer_send_tracked(connection, rejected.handle),
            ERR_SEND_QUEUE_FULL
        );
        assert_eq!(
            ct_owned_buffer_release(rejected.handle),
            ERR_INVALID_ARGUMENT
        );
        rejected.assert_released();
        assert_eq!(receipt.outcome(), 0);
        assert_eq!(active.statistics.released.load(Ordering::Acquire), 0);
        assert_eq!(active.metrics().retained_bytes, LENGTH);
        assert_eq!(ct_connection_close(connection), SUCCESS);
        until("active write cancellation", || receipt.outcome() == 2);
        active.assert_released();
    }
}

#[test]
fn missing_connection_submission_consumes_foreign_handle_and_releases_loan() {
    let _guard = test_guard();
    let producer = Producer::new();
    let _runtime = Runtime::new();
    assert_eq!(
        ct_owned_buffer_send_tracked(i32::MAX, producer.handle),
        ERR_CONNECTION_NOT_FOUND
    );
    assert_eq!(
        ct_owned_buffer_release(producer.handle),
        ERR_INVALID_ARGUMENT
    );
    producer.assert_released();
}
