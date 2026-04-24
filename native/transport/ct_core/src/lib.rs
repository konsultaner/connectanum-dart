//! Tokio based runtime that backs the connectanum native transport.

use std::{
    collections::{HashMap, VecDeque},
    io::{self, Cursor, Write},
    net::{IpAddr, SocketAddr, ToSocketAddrs},
    ops::Deref,
    pin::Pin,
    sync::{
        atomic::{AtomicU32, AtomicU64, Ordering},
        Arc, Mutex, OnceLock, RwLock,
    },
    task::{Context, Poll},
    time::{Duration, Instant},
};

use base64::{engine::general_purpose::STANDARD as Base64Engine, Engine as _};
use bytes::{Buf, Bytes, BytesMut};
use h2::{
    server::{self as h2_server, SendResponse as H2SendResponse},
    RecvStream as H2RecvStream,
};
use h3::{quic::BidiStream as H3BidiStreamTrait, server::RequestStream as H3RequestStream};
use h3_quinn::Connection as H3QuinnConnection;
use http::{
    header::{HeaderName, HeaderValue, CONTENT_LENGTH},
    Request as HttpRequest, Response as HttpResponse, StatusCode,
};
use http02::{
    header::{HeaderName as Http2HeaderName, HeaderValue as Http2HeaderValue},
    Request as Http2Request, Response as Http2Response, StatusCode as Http2StatusCode,
};
use sha1::{Digest, Sha1};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader},
    runtime::Runtime,
    sync::{
        mpsc::{
            self,
            error::{TryRecvError, TrySendError},
            UnboundedReceiver, UnboundedSender,
        },
        oneshot,
    },
    task::{AbortHandle, JoinHandle},
    time,
};
use tokio_rustls::TlsAcceptor;

use crate::http_body::{spawn_http1_streaming_body, Http1BodyReclaim, StreamingError};
use crate::io_stream::{IoReadHalf, IoStream, IoWriteHalf};

mod config;
mod http1_stream;
mod http_body;
mod http_stream;
mod io_stream;
mod ktls;
mod platform;
mod protocol;
mod rawsocket;
mod tls;
mod wamp;

use config::{HttpRouteMatch, TransportProtocol};
use quinn::{
    Connection as QuinnConnection, Endpoint as QuinnEndpoint, ServerConfig as QuinnServerConfig,
    VarInt,
};
use quinn_proto::crypto::rustls::QuicServerConfig as QuinnRustlsServerConfig;
use rand::RngCore;
use rustls::{
    pki_types::{CertificateDer, PrivateKeyDer, ServerName},
    ServerConfig as RustlsServerConfig,
};
use rustls_pemfile::{certs as load_certs, pkcs8_private_keys, rsa_private_keys};

type H3QuicBidiStream = h3_quinn::BidiStream<Bytes>;
type H3ServerStream<S> = H3RequestStream<S, Bytes>;
type H3ServerBidiStream = H3ServerStream<H3QuicBidiStream>;
type H3ServerSendStream =
    H3ServerStream<<H3QuicBidiStream as H3BidiStreamTrait<Bytes>>::SendStream>;
type H3ServerRecvStream =
    H3ServerStream<<H3QuicBidiStream as H3BidiStreamTrait<Bytes>>::RecvStream>;

const HTTP_STREAM_IDLE_FALLBACK: Duration = Duration::from_secs(10);
const HTTP_STREAM_TOTAL_FALLBACK: Duration = Duration::from_secs(40);
const HTTP_STREAM_TOTAL_MULTIPLIER: u32 = 4;
const HTTP2_MAX_CONCURRENT_STREAMS: u32 = 1024;
const HTTP2_INITIAL_STREAM_WINDOW: u32 = 8 * 1024 * 1024;
const HTTP2_INITIAL_CONNECTION_WINDOW: u32 = 64 * 1024 * 1024;
const HTTP2_MAX_FRAME_SIZE: u32 = 1 * 1024 * 1024;
const HTTP2_MAX_HEADER_LIST_SIZE: u32 = 16 * 1024 * 1024;
const HTTP2_MAX_CONCURRENT_RESET_STREAMS: usize = 256;
const HTTP2_MAX_SEND_BUFFER_SIZE: usize = 8 * 1024 * 1024;
const HTTP3_MAX_BIDI_STREAMS: u32 = 1024;
const HTTP3_MAX_UNI_STREAMS: u32 = 256;
const HTTP3_STREAM_RECEIVE_WINDOW: u32 = 8 * 1024 * 1024;
const HTTP3_CONNECTION_RECEIVE_WINDOW: u32 = 64 * 1024 * 1024;
const HTTP3_SEND_WINDOW: u64 = 64 * 1024 * 1024;
const HTTP3_DATAGRAM_BUFFER_BYTES: usize = 8 * 1024 * 1024;
const HTTP3_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(5);
const WEBSOCKET_MASK_CHUNK_SIZE: usize = 4 * 1024;
const RESPONSE_STREAM_SLOW_PATH_1MS_US: u64 = 1_000;
const RESPONSE_STREAM_SLOW_PATH_5MS_US: u64 = 5_000;
const RESPONSE_STREAM_SLOW_PATH_10MS_US: u64 = 10_000;

fn http_stream_timeouts(config: &config::EndpointRuntimeConfig) -> (Duration, Duration) {
    let idle = config.idle_timeout.unwrap_or(HTTP_STREAM_IDLE_FALLBACK);
    let total = idle
        .checked_mul(HTTP_STREAM_TOTAL_MULTIPLIER)
        .unwrap_or(HTTP_STREAM_TOTAL_FALLBACK);
    let total = if total.is_zero() {
        HTTP_STREAM_TOTAL_FALLBACK
    } else {
        total
    };
    (idle, total)
}

pub use config::{EndpointRuntimeConfig, HttpRouteResolution};
pub use http1_stream::HttpBodyPhase;
pub use http_body::StreamingBodyState;
pub use http_stream::{
    response_stream_channel, ResponseStreamError, ResponseStreamFrame, ResponseStreamReader,
    ResponseStreamWriter, RESPONSE_STREAM_BUFFER,
};

/// Reasons describing why an HTTP/2 or HTTP/3 connection closed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HttpConnectionCloseReason {
    Graceful,
    GoAway,
    IdleTimeout,
    BodyTimeout,
    ProtocolError,
    Internal,
}

/// Lifecycle event emitted whenever an HTTP/2 or HTTP/3 connection terminates.
#[derive(Debug, Clone)]
pub struct HttpConnectionEvent {
    pub connection_id: ConnectionId,
    pub protocol: ConnectionProtocol,
    pub reason: HttpConnectionCloseReason,
    pub request_count: u32,
    pub idle_timeouts: u32,
    pub body_timeouts: u32,
    pub backpressure_events: u32,
    pub max_backpressure_depth: u32,
    pub goaway_events: u32,
    pub detail: Option<String>,
}

#[derive(Debug)]
struct HttpConnectionStats {
    protocol: ConnectionProtocol,
    requests: AtomicU32,
    idle_timeouts: AtomicU32,
    body_timeouts: AtomicU32,
    backpressure_events: AtomicU32,
    max_backpressure_depth: AtomicU32,
    goaway_events: AtomicU32,
    close_reason: Mutex<Option<(HttpConnectionCloseReason, Option<String>)>>,
}

impl HttpConnectionStats {
    fn new(protocol: ConnectionProtocol) -> Arc<Self> {
        Arc::new(Self {
            protocol,
            requests: AtomicU32::new(0),
            idle_timeouts: AtomicU32::new(0),
            body_timeouts: AtomicU32::new(0),
            backpressure_events: AtomicU32::new(0),
            max_backpressure_depth: AtomicU32::new(0),
            goaway_events: AtomicU32::new(0),
            close_reason: Mutex::new(None),
        })
    }

    fn record_request(&self) {
        self.requests.fetch_add(1, Ordering::SeqCst);
    }

    fn record_idle_timeout(&self, detail: Option<String>) {
        self.idle_timeouts.fetch_add(1, Ordering::SeqCst);
        self.set_close_reason(HttpConnectionCloseReason::IdleTimeout, detail);
    }

    fn record_body_timeout(&self, detail: Option<String>) {
        self.body_timeouts.fetch_add(1, Ordering::SeqCst);
        self.set_close_reason(HttpConnectionCloseReason::BodyTimeout, detail);
    }

    fn record_backpressure(&self, depth: usize) {
        self.backpressure_events.fetch_add(1, Ordering::SeqCst);
        let depth_u32 = depth.min(u32::MAX as usize) as u32;
        let _ = self.max_backpressure_depth.fetch_update(
            Ordering::SeqCst,
            Ordering::SeqCst,
            |current| {
                if depth_u32 > current {
                    Some(depth_u32)
                } else {
                    None
                }
            },
        );
    }

    fn record_goaway(&self, detail: Option<String>) {
        self.goaway_events.fetch_add(1, Ordering::SeqCst);
        self.set_close_reason(HttpConnectionCloseReason::GoAway, detail);
    }

    fn set_close_reason(&self, reason: HttpConnectionCloseReason, detail: Option<String>) {
        let mut guard = self.close_reason.lock().unwrap();
        if guard.is_none() {
            *guard = Some((reason, detail));
        }
    }

    fn finalize(
        &self,
        connection_id: ConnectionId,
        fallback_reason: HttpConnectionCloseReason,
        fallback_detail: Option<String>,
    ) -> HttpConnectionEvent {
        let stored = self.close_reason.lock().unwrap().take();
        let (reason, detail) = stored.unwrap_or((fallback_reason, fallback_detail));
        HttpConnectionEvent {
            connection_id,
            protocol: self.protocol,
            reason,
            request_count: self.requests.load(Ordering::SeqCst),
            idle_timeouts: self.idle_timeouts.load(Ordering::SeqCst),
            body_timeouts: self.body_timeouts.load(Ordering::SeqCst),
            backpressure_events: self.backpressure_events.load(Ordering::SeqCst),
            max_backpressure_depth: self.max_backpressure_depth.load(Ordering::SeqCst),
            goaway_events: self.goaway_events.load(Ordering::SeqCst),
            detail,
        }
    }
}

#[derive(Default)]
struct HttpMetrics {
    total_events: AtomicU64,
    graceful: AtomicU64,
    goaway: AtomicU64,
    idle_timeouts: AtomicU64,
    body_timeouts: AtomicU64,
    protocol_errors: AtomicU64,
    internal_errors: AtomicU64,
    backpressure_events: AtomicU64,
    max_backpressure_depth: AtomicU32,
}

#[derive(Default)]
struct HttpResponseStreamMetrics {
    streaming_responses_total: AtomicU64,
    stream_open_to_headers_send_samples_total: AtomicU64,
    stream_open_to_headers_send_us_total: AtomicU64,
    headers_send_call_samples_total: AtomicU64,
    headers_send_call_us_total: AtomicU64,
    headers_to_first_connection_write_samples_total: AtomicU64,
    headers_to_first_connection_write_us_total: AtomicU64,
    headers_to_first_connection_write_ge_1ms_total: AtomicU64,
    headers_to_first_connection_write_ge_5ms_total: AtomicU64,
    headers_to_first_connection_write_ge_10ms_total: AtomicU64,
    first_chunk_channel_wait_samples_total: AtomicU64,
    first_chunk_channel_wait_us_total: AtomicU64,
    first_chunk_channel_wait_ge_1ms_total: AtomicU64,
    first_chunk_channel_wait_ge_5ms_total: AtomicU64,
    first_chunk_channel_wait_ge_10ms_total: AtomicU64,
    headers_to_first_chunk_dequeue_samples_total: AtomicU64,
    headers_to_first_chunk_dequeue_us_total: AtomicU64,
    headers_to_first_chunk_dequeue_ge_1ms_total: AtomicU64,
    headers_to_first_chunk_dequeue_ge_5ms_total: AtomicU64,
    headers_to_first_chunk_dequeue_ge_10ms_total: AtomicU64,
    first_chunk_send_call_samples_total: AtomicU64,
    first_chunk_send_call_us_total: AtomicU64,
    first_chunk_send_call_ge_1ms_total: AtomicU64,
    first_chunk_send_call_ge_5ms_total: AtomicU64,
    first_chunk_send_call_ge_10ms_total: AtomicU64,
    headers_to_first_chunk_send_call_samples_total: AtomicU64,
    headers_to_first_chunk_send_call_us_total: AtomicU64,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct HttpMetricsSnapshot {
    pub total_events: u64,
    pub graceful_events: u64,
    pub goaway_events: u64,
    pub idle_timeout_events: u64,
    pub body_timeout_events: u64,
    pub protocol_error_events: u64,
    pub internal_error_events: u64,
    pub backpressure_events: u64,
    pub max_backpressure_depth: u32,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct HttpResponseStreamMetricsSnapshot {
    pub streaming_responses_total: u64,
    pub stream_open_to_headers_send_samples_total: u64,
    pub stream_open_to_headers_send_us_total: u64,
    pub headers_send_call_samples_total: u64,
    pub headers_send_call_us_total: u64,
    pub headers_to_first_connection_write_samples_total: u64,
    pub headers_to_first_connection_write_us_total: u64,
    pub headers_to_first_connection_write_ge_1ms_total: u64,
    pub headers_to_first_connection_write_ge_5ms_total: u64,
    pub headers_to_first_connection_write_ge_10ms_total: u64,
    pub first_chunk_channel_wait_samples_total: u64,
    pub first_chunk_channel_wait_us_total: u64,
    pub first_chunk_channel_wait_ge_1ms_total: u64,
    pub first_chunk_channel_wait_ge_5ms_total: u64,
    pub first_chunk_channel_wait_ge_10ms_total: u64,
    pub headers_to_first_chunk_dequeue_samples_total: u64,
    pub headers_to_first_chunk_dequeue_us_total: u64,
    pub headers_to_first_chunk_dequeue_ge_1ms_total: u64,
    pub headers_to_first_chunk_dequeue_ge_5ms_total: u64,
    pub headers_to_first_chunk_dequeue_ge_10ms_total: u64,
    pub first_chunk_send_call_samples_total: u64,
    pub first_chunk_send_call_us_total: u64,
    pub first_chunk_send_call_ge_1ms_total: u64,
    pub first_chunk_send_call_ge_5ms_total: u64,
    pub first_chunk_send_call_ge_10ms_total: u64,
    pub headers_to_first_chunk_send_call_samples_total: u64,
    pub headers_to_first_chunk_send_call_us_total: u64,
}

#[derive(Debug, Clone)]
pub struct HttpMetricsBreakdownSnapshot {
    pub listener_id: ListenerId,
    pub protocol: ConnectionProtocol,
    pub snapshot: HttpMetricsSnapshot,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
struct HttpMetricsKey {
    listener_id: ListenerId,
    protocol: ConnectionProtocol,
}

#[derive(Default)]
struct HttpMetricsStore {
    totals: HttpMetrics,
    by_key: Mutex<HashMap<HttpMetricsKey, Arc<HttpMetrics>>>,
}

#[derive(Default)]
struct Http2ConnectionWriteTracker {
    pending_headers_sent_at: Mutex<VecDeque<Instant>>,
}

struct InstrumentedHttp2IoStream {
    inner: IoStream,
    write_tracker: Arc<Http2ConnectionWriteTracker>,
}

static HTTP_RESPONSE_STREAM_METRICS: OnceLock<HttpResponseStreamMetrics> = OnceLock::new();

impl HttpMetrics {
    fn record(&self, event: &HttpConnectionEvent) {
        self.total_events.fetch_add(1, Ordering::SeqCst);
        self.backpressure_events
            .fetch_add(event.backpressure_events as u64, Ordering::SeqCst);
        let depth = event.max_backpressure_depth;
        if depth > 0 {
            let _ = self.max_backpressure_depth.fetch_update(
                Ordering::SeqCst,
                Ordering::SeqCst,
                |current| {
                    if depth > current {
                        Some(depth)
                    } else {
                        None
                    }
                },
            );
        }
        match event.reason {
            HttpConnectionCloseReason::Graceful => {
                self.graceful.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::GoAway => {
                self.goaway.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::IdleTimeout => {
                self.idle_timeouts.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::BodyTimeout => {
                self.body_timeouts.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::ProtocolError => {
                self.protocol_errors.fetch_add(1, Ordering::SeqCst);
            }
            HttpConnectionCloseReason::Internal => {
                self.internal_errors.fetch_add(1, Ordering::SeqCst);
            }
        }
    }

    fn snapshot(&self) -> HttpMetricsSnapshot {
        HttpMetricsSnapshot {
            total_events: self.total_events.load(Ordering::SeqCst),
            graceful_events: self.graceful.load(Ordering::SeqCst),
            goaway_events: self.goaway.load(Ordering::SeqCst),
            idle_timeout_events: self.idle_timeouts.load(Ordering::SeqCst),
            body_timeout_events: self.body_timeouts.load(Ordering::SeqCst),
            protocol_error_events: self.protocol_errors.load(Ordering::SeqCst),
            internal_error_events: self.internal_errors.load(Ordering::SeqCst),
            backpressure_events: self.backpressure_events.load(Ordering::SeqCst),
            max_backpressure_depth: self.max_backpressure_depth.load(Ordering::SeqCst),
        }
    }
}

impl HttpMetricsStore {
    fn record(&self, listener_id: ListenerId, event: &HttpConnectionEvent) {
        self.totals.record(event);
        let metrics = {
            let mut guard = self
                .by_key
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            guard
                .entry(HttpMetricsKey {
                    listener_id,
                    protocol: event.protocol,
                })
                .or_insert_with(|| Arc::new(HttpMetrics::default()))
                .clone()
        };
        metrics.record(event);
    }

    fn totals_snapshot(&self) -> HttpMetricsSnapshot {
        self.totals.snapshot()
    }

    fn snapshot_with_breakdown(&self) -> (HttpMetricsSnapshot, Vec<HttpMetricsBreakdownSnapshot>) {
        let totals = self.totals_snapshot();
        let guard = self
            .by_key
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let mut breakdown = Vec::with_capacity(guard.len());
        for (key, metrics) in guard.iter() {
            breakdown.push(HttpMetricsBreakdownSnapshot {
                listener_id: key.listener_id,
                protocol: key.protocol,
                snapshot: metrics.snapshot(),
            });
        }
        breakdown.sort_by(|left, right| {
            (left.listener_id.0, protocol_sort_key(left.protocol))
                .cmp(&(right.listener_id.0, protocol_sort_key(right.protocol)))
        });
        (totals, breakdown)
    }
}

impl HttpResponseStreamMetrics {
    fn record_streaming_response(&self) {
        self.streaming_responses_total
            .fetch_add(1, Ordering::SeqCst);
    }

    fn record_headers_sent(
        &self,
        stream_opened_at: Instant,
        headers_send_call_started_at: Instant,
        headers_send_call_finished_at: Instant,
    ) {
        let stream_open_to_headers_send_us =
            saturating_instant_delta_us(stream_opened_at, headers_send_call_finished_at);
        let headers_send_call_us = saturating_instant_delta_us(
            headers_send_call_started_at,
            headers_send_call_finished_at,
        );

        self.stream_open_to_headers_send_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.stream_open_to_headers_send_us_total
            .fetch_add(stream_open_to_headers_send_us, Ordering::SeqCst);
        self.headers_send_call_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.headers_send_call_us_total
            .fetch_add(headers_send_call_us, Ordering::SeqCst);
    }

    fn record_headers_to_first_connection_write(&self, headers_sent_at: Instant, write_at: Instant) {
        let headers_to_first_connection_write_us =
            saturating_instant_delta_us(headers_sent_at, write_at);
        self.headers_to_first_connection_write_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.headers_to_first_connection_write_us_total
            .fetch_add(headers_to_first_connection_write_us, Ordering::SeqCst);
        record_response_stream_slow_path(
            headers_to_first_connection_write_us,
            &self.headers_to_first_connection_write_ge_1ms_total,
            &self.headers_to_first_connection_write_ge_5ms_total,
            &self.headers_to_first_connection_write_ge_10ms_total,
        );
    }

    fn record_first_chunk(
        &self,
        queued_at: Instant,
        headers_sent_at: Instant,
        dequeue_at: Instant,
        send_call_started_at: Instant,
        send_call_finished_at: Instant,
    ) {
        let channel_wait_us = saturating_instant_delta_us(queued_at, dequeue_at);
        let headers_to_dequeue_us = saturating_instant_delta_us(headers_sent_at, dequeue_at);
        let send_call_us = saturating_instant_delta_us(send_call_started_at, send_call_finished_at);
        let headers_to_send_call_us =
            saturating_instant_delta_us(headers_sent_at, send_call_finished_at);

        self.first_chunk_channel_wait_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.first_chunk_channel_wait_us_total
            .fetch_add(channel_wait_us, Ordering::SeqCst);
        record_response_stream_slow_path(
            channel_wait_us,
            &self.first_chunk_channel_wait_ge_1ms_total,
            &self.first_chunk_channel_wait_ge_5ms_total,
            &self.first_chunk_channel_wait_ge_10ms_total,
        );
        self.headers_to_first_chunk_dequeue_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.headers_to_first_chunk_dequeue_us_total
            .fetch_add(headers_to_dequeue_us, Ordering::SeqCst);
        record_response_stream_slow_path(
            headers_to_dequeue_us,
            &self.headers_to_first_chunk_dequeue_ge_1ms_total,
            &self.headers_to_first_chunk_dequeue_ge_5ms_total,
            &self.headers_to_first_chunk_dequeue_ge_10ms_total,
        );
        self.first_chunk_send_call_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.first_chunk_send_call_us_total
            .fetch_add(send_call_us, Ordering::SeqCst);
        record_response_stream_slow_path(
            send_call_us,
            &self.first_chunk_send_call_ge_1ms_total,
            &self.first_chunk_send_call_ge_5ms_total,
            &self.first_chunk_send_call_ge_10ms_total,
        );
        self.headers_to_first_chunk_send_call_samples_total
            .fetch_add(1, Ordering::SeqCst);
        self.headers_to_first_chunk_send_call_us_total
            .fetch_add(headers_to_send_call_us, Ordering::SeqCst);
    }

    fn snapshot(&self) -> HttpResponseStreamMetricsSnapshot {
        HttpResponseStreamMetricsSnapshot {
            streaming_responses_total: self.streaming_responses_total.load(Ordering::SeqCst),
            stream_open_to_headers_send_samples_total: self
                .stream_open_to_headers_send_samples_total
                .load(Ordering::SeqCst),
            stream_open_to_headers_send_us_total: self
                .stream_open_to_headers_send_us_total
                .load(Ordering::SeqCst),
            headers_send_call_samples_total: self
                .headers_send_call_samples_total
                .load(Ordering::SeqCst),
            headers_send_call_us_total: self
                .headers_send_call_us_total
                .load(Ordering::SeqCst),
            headers_to_first_connection_write_samples_total: self
                .headers_to_first_connection_write_samples_total
                .load(Ordering::SeqCst),
            headers_to_first_connection_write_us_total: self
                .headers_to_first_connection_write_us_total
                .load(Ordering::SeqCst),
            headers_to_first_connection_write_ge_1ms_total: self
                .headers_to_first_connection_write_ge_1ms_total
                .load(Ordering::SeqCst),
            headers_to_first_connection_write_ge_5ms_total: self
                .headers_to_first_connection_write_ge_5ms_total
                .load(Ordering::SeqCst),
            headers_to_first_connection_write_ge_10ms_total: self
                .headers_to_first_connection_write_ge_10ms_total
                .load(Ordering::SeqCst),
            first_chunk_channel_wait_samples_total: self
                .first_chunk_channel_wait_samples_total
                .load(Ordering::SeqCst),
            first_chunk_channel_wait_us_total: self
                .first_chunk_channel_wait_us_total
                .load(Ordering::SeqCst),
            first_chunk_channel_wait_ge_1ms_total: self
                .first_chunk_channel_wait_ge_1ms_total
                .load(Ordering::SeqCst),
            first_chunk_channel_wait_ge_5ms_total: self
                .first_chunk_channel_wait_ge_5ms_total
                .load(Ordering::SeqCst),
            first_chunk_channel_wait_ge_10ms_total: self
                .first_chunk_channel_wait_ge_10ms_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_dequeue_samples_total: self
                .headers_to_first_chunk_dequeue_samples_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_dequeue_us_total: self
                .headers_to_first_chunk_dequeue_us_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_dequeue_ge_1ms_total: self
                .headers_to_first_chunk_dequeue_ge_1ms_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_dequeue_ge_5ms_total: self
                .headers_to_first_chunk_dequeue_ge_5ms_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_dequeue_ge_10ms_total: self
                .headers_to_first_chunk_dequeue_ge_10ms_total
                .load(Ordering::SeqCst),
            first_chunk_send_call_samples_total: self
                .first_chunk_send_call_samples_total
                .load(Ordering::SeqCst),
            first_chunk_send_call_us_total: self
                .first_chunk_send_call_us_total
                .load(Ordering::SeqCst),
            first_chunk_send_call_ge_1ms_total: self
                .first_chunk_send_call_ge_1ms_total
                .load(Ordering::SeqCst),
            first_chunk_send_call_ge_5ms_total: self
                .first_chunk_send_call_ge_5ms_total
                .load(Ordering::SeqCst),
            first_chunk_send_call_ge_10ms_total: self
                .first_chunk_send_call_ge_10ms_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_send_call_samples_total: self
                .headers_to_first_chunk_send_call_samples_total
                .load(Ordering::SeqCst),
            headers_to_first_chunk_send_call_us_total: self
                .headers_to_first_chunk_send_call_us_total
                .load(Ordering::SeqCst),
        }
    }
}

impl Http2ConnectionWriteTracker {
    fn note_headers_sent(&self, headers_sent_at: Instant) {
        let mut guard = self
            .pending_headers_sent_at
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        guard.push_back(headers_sent_at);
    }

    fn record_connection_write(&self, write_at: Instant) {
        let pending_headers_sent_at = {
            let mut guard = self
                .pending_headers_sent_at
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            guard.drain(..).collect::<Vec<_>>()
        };
        if pending_headers_sent_at.is_empty() {
            return;
        }
        let metrics = http_response_stream_metrics();
        for headers_sent_at in pending_headers_sent_at {
            metrics.record_headers_to_first_connection_write(headers_sent_at, write_at);
        }
    }
}

impl tokio::io::AsyncRead for InstrumentedHttp2IoStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let me = self.get_mut();
        Pin::new(&mut me.inner).poll_read(cx, buf)
    }
}

impl tokio::io::AsyncWrite for InstrumentedHttp2IoStream {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize, io::Error>> {
        let me = self.get_mut();
        match Pin::new(&mut me.inner).poll_write(cx, buf) {
            Poll::Ready(Ok(written)) => {
                if written > 0 {
                    me.write_tracker.record_connection_write(Instant::now());
                }
                Poll::Ready(Ok(written))
            }
            other => other,
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let me = self.get_mut();
        Pin::new(&mut me.inner).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let me = self.get_mut();
        Pin::new(&mut me.inner).poll_shutdown(cx)
    }
}

static HTTP_METRICS: OnceLock<HttpMetricsStore> = OnceLock::new();

fn http_metrics() -> &'static HttpMetricsStore {
    HTTP_METRICS.get_or_init(HttpMetricsStore::default)
}

fn http_response_stream_metrics() -> &'static HttpResponseStreamMetrics {
    HTTP_RESPONSE_STREAM_METRICS.get_or_init(HttpResponseStreamMetrics::default)
}

fn saturating_instant_delta_us(start: Instant, end: Instant) -> u64 {
    end.saturating_duration_since(start)
        .as_micros()
        .min(u64::MAX as u128) as u64
}

fn record_response_stream_slow_path(
    value_us: u64,
    ge_1ms_total: &AtomicU64,
    ge_5ms_total: &AtomicU64,
    ge_10ms_total: &AtomicU64,
) {
    if value_us >= RESPONSE_STREAM_SLOW_PATH_1MS_US {
        ge_1ms_total.fetch_add(1, Ordering::SeqCst);
    }
    if value_us >= RESPONSE_STREAM_SLOW_PATH_5MS_US {
        ge_5ms_total.fetch_add(1, Ordering::SeqCst);
    }
    if value_us >= RESPONSE_STREAM_SLOW_PATH_10MS_US {
        ge_10ms_total.fetch_add(1, Ordering::SeqCst);
    }
}

pub fn http_metrics_snapshot() -> HttpMetricsSnapshot {
    http_metrics().totals_snapshot()
}

pub fn http_metrics_snapshot_with_breakdown(
) -> (HttpMetricsSnapshot, Vec<HttpMetricsBreakdownSnapshot>) {
    http_metrics().snapshot_with_breakdown()
}

pub fn http_response_stream_metrics_snapshot() -> HttpResponseStreamMetricsSnapshot {
    http_response_stream_metrics().snapshot()
}

fn protocol_sort_key(protocol: ConnectionProtocol) -> u8 {
    match protocol {
        ConnectionProtocol::RawSocket => 0,
        ConnectionProtocol::WebSocket => 1,
        ConnectionProtocol::Http => 2,
        ConnectionProtocol::Http2 => 3,
        ConnectionProtocol::Http3 => 4,
    }
}

fn record_http_metrics(listener_id: ListenerId, event: &HttpConnectionEvent) {
    http_metrics().record(listener_id, event);
}

pub use platform::{Runtime as PlatformRuntime, UnsupportedPlatform};
pub use protocol::{Http2Handshake, Http3Handshake, HttpHandshake, WebSocketHandshake};
pub use rawsocket::Serializer as RawSocketSerializer;
pub use wamp::{
    parse_message, parse_message_segments, ParseError as WampParseError, ParsedMessage,
    Payload as WampPayload, RawFrame as WampRawFrame, WampMessage,
};

static RUNTIME_MANAGER: OnceLock<RuntimeManager> = OnceLock::new();

const MAX_FRAME_LEN: u64 = 1 << 24;
const HTTP3_DEFAULT_BODY_LIMIT: u64 = 4 * 1024 * 1024;
const WEBSOCKET_GUID: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const MAX_WEBSOCKET_MESSAGE_LEN: usize = 1 << 24;
const HTTP1_INLINE_BODY_LIMIT: usize = 64 * 1024;

/// Unique identifier for a registered listener.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct ListenerId(pub u32);

/// Unique identifier for an accepted connection.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct ConnectionId(pub u32);

/// Transport protocol negotiated for a connection.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub enum ConnectionProtocol {
    RawSocket,
    WebSocket,
    Http,
    Http2,
    Http3,
}

#[derive(Debug, Clone)]
pub struct HttpBodyHandle {
    payload: Arc<HttpBodyPayload>,
}

#[derive(Debug)]
enum HttpBodyPayload {
    Inline(Bytes),
    Streaming(StreamingPayload),
}

#[derive(Debug)]
struct StreamingPayload {
    state: Arc<StreamingBodyState>,
}

#[derive(Debug)]
pub struct HttpBodySlice {
    pub ptr: *const u8,
    pub len: usize,
}

impl HttpBodyHandle {
    pub fn empty() -> Self {
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(Bytes::new())),
        }
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(Bytes::from(bytes))),
        }
    }

    pub fn from_inline(bytes: Bytes) -> Self {
        if bytes.is_empty() {
            return Self::empty();
        }
        Self {
            payload: Arc::new(HttpBodyPayload::Inline(bytes)),
        }
    }

    pub fn streaming(state: Arc<StreamingBodyState>) -> Self {
        Self {
            payload: Arc::new(HttpBodyPayload::Streaming(StreamingPayload { state })),
        }
    }

    pub fn len(&self) -> usize {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => bytes.len(),
            HttpBodyPayload::Streaming(payload) => payload.state.total_len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn inline_bytes(&self) -> Option<&Bytes> {
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => Some(bytes),
            HttpBodyPayload::Streaming(_) => None,
        }
    }

    pub fn slice(&self, offset: usize, length: usize) -> Option<HttpBodySlice> {
        let total = self.len();
        if offset > total {
            return None;
        }
        let end = total.min(offset.saturating_add(length));
        let slice_len = end.saturating_sub(offset);
        match self.payload.as_ref() {
            HttpBodyPayload::Inline(bytes) => {
                let ptr = unsafe { bytes.as_ptr().add(offset) };
                Some(HttpBodySlice {
                    ptr,
                    len: slice_len,
                })
            }
            HttpBodyPayload::Streaming(_) => None,
        }
    }

    pub fn stream_read(&self, len: usize) -> Result<Option<HttpBodySlice>, StreamingError> {
        match self.payload.as_ref() {
            HttpBodyPayload::Streaming(payload) => payload.state.take_slice(len),
            _ => Ok(None),
        }
    }

    pub fn request_finish(&self) {
        if let HttpBodyPayload::Streaming(payload) = self.payload.as_ref() {
            payload.state.request_finish();
        }
    }

    pub fn is_streaming(&self) -> bool {
        matches!(self.payload.as_ref(), HttpBodyPayload::Streaming(_))
    }
}

pub struct HttpRequestSummary {
    pub method: Arc<[u8]>,
    pub target: Arc<[u8]>,
    pub path: Arc<[u8]>,
    pub query: Option<Arc<[u8]>>,
    pub protocol: Arc<[u8]>,
    pub version: u8,
    pub headers: Vec<(Arc<[u8]>, Arc<[u8]>)>,
    pub body: HttpBodyHandle,
    pub realm: Option<Arc<[u8]>>,
    pub procedure: Option<Arc<[u8]>>,
    pub route: Option<HttpRouteResolution>,
}

impl HttpRequestSummary {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        method: String,
        target: String,
        path: String,
        query: Option<String>,
        protocol: String,
        version: u8,
        headers: Vec<(Arc<[u8]>, Arc<[u8]>)>,
        body: HttpBodyHandle,
        realm: Option<String>,
        procedure: Option<String>,
        route: Option<HttpRouteResolution>,
    ) -> Self {
        Self {
            method: http_bytes_from_string(method),
            target: http_bytes_from_string(target),
            path: http_bytes_from_string(path),
            query: query.map(http_bytes_from_string),
            protocol: http_bytes_from_string(protocol),
            version,
            headers,
            body,
            realm: realm.map(http_bytes_from_string),
            procedure: procedure.map(http_bytes_from_string),
            route,
        }
    }
}

fn http_bytes_from_string(value: String) -> Arc<[u8]> {
    Arc::<[u8]>::from(value.into_bytes())
}

fn http_bytes_from_slice(value: &[u8]) -> Arc<[u8]> {
    Arc::<[u8]>::from(value.to_vec())
}

pub struct HttpResponseHandle {
    connection_id: ConnectionId,
    sender: oneshot::Sender<HttpResponseDispatch>,
}

impl HttpResponseHandle {
    fn new(connection_id: ConnectionId, sender: oneshot::Sender<HttpResponseDispatch>) -> Self {
        Self {
            connection_id,
            sender,
        }
    }

    pub fn respond(self, response: HttpResponseDispatch) -> Result<(), Error> {
        self.sender
            .send(response)
            .map_err(|_| Error::Http3ResponseSend(self.connection_id))
    }
}

#[derive(Debug)]
pub struct HttpResponseDispatch {
    pub status: i32,
    pub headers: Vec<(String, String)>,
    pub body: HttpResponseBody,
}

#[derive(Debug)]
pub enum HttpResponseBody {
    Buffered(Vec<u8>),
    Streaming(ResponseStreamReader),
}

/// Handle representing an accepted HTTP/3 bidirectional stream.
pub struct Http3BidiStream {
    id: u64,
    send: quinn::SendStream,
    recv: quinn::RecvStream,
}

impl Http3BidiStream {
    /// Returns the QUIC stream identifier.
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Splits the stream into its send/receive halves.
    pub fn into_parts(self) -> (quinn::SendStream, quinn::RecvStream) {
        (self.send, self.recv)
    }
}

/// Errors that can occur when interacting with the runtime.
#[derive(Debug, Error)]
pub enum Error {
    /// The runtime has not been initialised yet.
    #[error("runtime not started")]
    RuntimeNotStarted,
    /// Attempted to start the runtime twice without shutting it down.
    #[error("runtime already started")]
    RuntimeAlreadyStarted,
    /// Native runtime is not supported on this platform.
    #[error("native runtime unsupported on this platform")]
    UnsupportedPlatform,
    /// Provided backlog value is invalid.
    #[error("backlog must be positive")]
    InvalidBacklog,
    /// No listener with the provided identifier exists.
    #[error("listener {0:?} not found")]
    ListenerNotFound(ListenerId),
    /// The accept channel was already consumed.
    #[error("accept channel already taken for listener {0:?}")]
    AcceptChannelAlreadyTaken(ListenerId),
    /// Socket address resolution failed.
    #[error("failed to resolve address {0}:{1}")]
    AddressResolution(String, u16),
    /// Listener requested for a host/port not present in the applied config.
    #[error("endpoint {0}:{1} is not configured")]
    EndpointNotConfigured(String, u16),
    /// Router configuration could not be parsed or applied.
    #[error("router configuration invalid: {0}")]
    RouterConfigInvalid(String),
    /// Connection for the provided identifier was not registered.
    #[error("connection {0:?} not found")]
    ConnectionNotFound(ConnectionId),
    /// Operation not supported for negotiated protocol.
    #[error("connection {0:?} protocol {1:?} does not support this operation")]
    UnsupportedProtocol(ConnectionId, ConnectionProtocol),
    /// Connection handshake already consumed.
    #[error("connection {0:?} handshake already consumed")]
    HandshakeAlreadyTaken(ConnectionId),
    /// HTTP/3 connection handle is unavailable.
    #[error("connection {0:?} handle unavailable")]
    ConnectionHandleUnavailable(ConnectionId),
    /// HTTP/3 response channel closed or failed.
    #[error("failed to send http/3 response for connection {0:?}")]
    Http3ResponseSend(ConnectionId),
    /// Wrapper around I/O errors.
    #[error(transparent)]
    Io(#[from] std::io::Error),
    /// Send buffer is full; the caller should retry or close the connection.
    #[error("connection {0:?} send queue full")]
    SendQueueFull(ConnectionId),
    /// Native runtime thread count env var is invalid.
    #[error("native runtime thread count invalid: {0}")]
    InvalidRuntimeThreadCount(String),
}

const NATIVE_RUNTIME_THREADS_ENV: &str = "CONNECTANUM_NATIVE_RUNTIME_THREADS";

struct RuntimeManager {
    state: Mutex<Option<RuntimeState>>,
}

struct RuntimeState {
    runtime: Runtime,
    handle: tokio::runtime::Handle,
    registry: Arc<ListenerRegistry>,
}

struct RuntimeView {
    handle: tokio::runtime::Handle,
    registry: Arc<ListenerRegistry>,
}

struct ListenerRegistry {
    listeners: Mutex<HashMap<ListenerId, ListenerEntry>>,
    connections: Mutex<HashMap<ConnectionId, ConnectionEntry>>,
    connection_events: Mutex<VecDeque<HttpConnectionEvent>>,
    next_listener_id: AtomicU32,
    next_connection_id: AtomicU32,
}

impl Default for ListenerRegistry {
    fn default() -> Self {
        Self {
            listeners: Mutex::new(HashMap::new()),
            connections: Mutex::new(HashMap::new()),
            connection_events: Mutex::new(VecDeque::new()),
            next_listener_id: AtomicU32::new(0),
            next_connection_id: AtomicU32::new(0),
        }
    }
}

struct ListenerEntry {
    addr: SocketAddr,
    receiver: Mutex<Option<mpsc::Receiver<ConnectionId>>>,
    _sender: mpsc::Sender<ConnectionId>,
    tasks: Vec<JoinHandle<()>>,
    #[allow(dead_code)]
    http3_addr: Option<SocketAddr>,
    http3_endpoint: Option<QuinnEndpoint>,
    #[allow(dead_code)]
    config_state: Arc<ListenerConfigState>,
}

struct ListenerConfigState {
    endpoint_config: RwLock<Arc<config::EndpointRuntimeConfig>>,
    tls_acceptor: RwLock<Option<TlsAcceptor>>,
}

impl ListenerConfigState {
    fn new(
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        tls_acceptor: Option<TlsAcceptor>,
    ) -> Self {
        Self {
            endpoint_config: RwLock::new(endpoint_config),
            tls_acceptor: RwLock::new(tls_acceptor),
        }
    }

    fn endpoint_config(&self) -> Arc<config::EndpointRuntimeConfig> {
        self.endpoint_config
            .read()
            .unwrap_or_else(|poison| poison.into_inner())
            .clone()
    }

    fn tls_acceptor(&self) -> Option<TlsAcceptor> {
        self.tls_acceptor
            .read()
            .unwrap_or_else(|poison| poison.into_inner())
            .clone()
    }

    fn update(
        &self,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        tls_acceptor: Option<TlsAcceptor>,
    ) {
        {
            let mut guard = self
                .endpoint_config
                .write()
                .unwrap_or_else(|poison| poison.into_inner());
            *guard = endpoint_config;
        }
        {
            let mut guard = self
                .tls_acceptor
                .write()
                .unwrap_or_else(|poison| poison.into_inner());
            *guard = tls_acceptor;
        }
    }
}

struct ConnectionEntry {
    #[allow(dead_code)]
    listener_id: ListenerId,
    #[allow(dead_code)]
    peer_addr: SocketAddr,
    protocol: ConnectionProtocol,
    websocket_protocol: Option<String>,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    stats: Option<Arc<HttpConnectionStats>>,
    record: ConnectionRecord,
}

enum ConnectionRecord {
    RawSocket {
        _serializer: rawsocket::Serializer,
        max_exponent: u32,
        frames: Arc<Mutex<mpsc::Receiver<wamp::ParsedMessage>>>,
        reader_abort: AbortHandle,
        writer_abort: AbortHandle,
        heartbeat_abort: Option<AbortHandle>,
        send_tx: mpsc::Sender<OutboundFrame>,
    },
    WebSocketPending {
        handshake: Mutex<Option<protocol::WebSocketHandshake>>,
    },
    WebSocket {
        _serializer: rawsocket::Serializer,
        frames: Arc<Mutex<mpsc::Receiver<wamp::ParsedMessage>>>,
        reader_abort: AbortHandle,
        writer_abort: AbortHandle,
        heartbeat_abort: Option<AbortHandle>,
        send_tx: mpsc::Sender<OutboundFrame>,
    },
    HttpPending {
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
    },
    Http2Pending {
        handshake: Mutex<Option<protocol::Http2Handshake>>,
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
    },
    Http3Pending {
        handshake: Mutex<Option<protocol::Http3Handshake>>,
        connection: Mutex<Option<Arc<quinn::Connection>>>,
        streams: Arc<Http3StreamChannels>,
        pending_requests: Mutex<VecDeque<QueuedHttpRequest>>,
    },
}

struct Http3StreamChannels {
    streams: Mutex<VecDeque<Http3BidiStream>>,
}

impl Http3StreamChannels {
    fn new() -> Self {
        Self {
            streams: Mutex::new(VecDeque::new()),
        }
    }

    fn try_recv(&self) -> Option<Http3BidiStream> {
        self.streams.lock().unwrap().pop_front()
    }
}

struct QueuedHttpRequest {
    summary: HttpRequestSummary,
    response: HttpResponseHandle,
}

impl RuntimeManager {
    fn global() -> &'static Self {
        RUNTIME_MANAGER.get_or_init(|| RuntimeManager {
            state: Mutex::new(None),
        })
    }

    fn with_state<F, T>(&self, f: F) -> Result<T, Error>
    where
        F: FnOnce(&RuntimeView) -> Result<T, Error>,
    {
        let view = {
            let guard = self
                .state
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            let state = guard.as_ref().ok_or(Error::RuntimeNotStarted)?;
            state.view()
        };
        f(&view)
    }
}

impl RuntimeState {
    fn view(&self) -> RuntimeView {
        RuntimeView {
            handle: self.handle.clone(),
            registry: Arc::clone(&self.registry),
        }
    }

    fn shutdown(self) {
        self.registry.shutdown();
        let runtime = self.runtime;
        let _ = std::thread::spawn(move || {
            runtime.shutdown_timeout(Duration::from_secs(1));
        })
        .join();
    }
}

impl ListenerRegistry {
    fn next_listener_id(&self) -> ListenerId {
        let id = self.next_listener_id.fetch_add(1, Ordering::SeqCst);
        ListenerId(id + 1)
    }

    fn next_connection_id(&self) -> ConnectionId {
        let id = self
            .next_connection_id
            .fetch_add(1, Ordering::SeqCst)
            .wrapping_add(1);
        ConnectionId(id)
    }

    fn insert(&self, id: ListenerId, entry: ListenerEntry) {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(id, entry);
    }

    fn local_addr(&self, id: ListenerId) -> Result<SocketAddr, Error> {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&id)
            .map(|entry| entry.addr)
            .ok_or(Error::ListenerNotFound(id))
    }

    fn http3_addr(&self, id: ListenerId) -> Result<Option<SocketAddr>, Error> {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&id)
            .map(|entry| entry.http3_addr)
            .ok_or(Error::ListenerNotFound(id))
    }

    fn take_receiver(&self, id: ListenerId) -> Result<mpsc::Receiver<ConnectionId>, Error> {
        let listeners = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = listeners.get(&id).ok_or(Error::ListenerNotFound(id))?;
        let mut guard = entry.receiver.lock().unwrap();
        guard.take().ok_or(Error::AcceptChannelAlreadyTaken(id))
    }

    fn reload_tls(&self) -> Result<u32, Error> {
        let listeners = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let mut updated = 0u32;
        for (listener_id, entry) in listeners.iter() {
            let current = entry.config_state.endpoint_config();
            let endpoint_cfg = config::find_endpoint(&current.host, current.port)
                .ok_or_else(|| Error::EndpointNotConfigured(current.host.clone(), current.port))?;
            let next = Arc::new(config::EndpointRuntimeConfig::try_from_endpoint(
                &endpoint_cfg,
            )?);
            if next.tls_mode != current.tls_mode {
                return Err(Error::RouterConfigInvalid(format!(
                    "listener {:?} tls_mode changed ({:?} -> {:?}); restart required",
                    listener_id, current.tls_mode, next.tls_mode
                )));
            }
            let current_http3 = current.supports_protocol(TransportProtocol::Http3);
            let next_http3 = next.supports_protocol(TransportProtocol::Http3);
            if current_http3 != next_http3 {
                return Err(Error::RouterConfigInvalid(format!(
                    "listener {:?} http3 enablement changed; restart required",
                    listener_id
                )));
            }

            let tls_acceptor = tls::build_tls_acceptor(&next)?;
            entry.config_state.update(Arc::clone(&next), tls_acceptor);
            if current_http3 {
                let endpoint = entry.http3_endpoint.as_ref().ok_or_else(|| {
                    Error::RouterConfigInvalid(format!(
                        "listener {:?} missing http3 endpoint during reload",
                        listener_id
                    ))
                })?;
                let server_config = build_http3_server_config(&next)?;
                endpoint.set_server_config(Some(server_config));
            }
            updated += 1;
        }
        Ok(updated)
    }

    fn close_listener(&self, listener_id: ListenerId) -> Result<(), Error> {
        let mut entry = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .remove(&listener_id)
            .ok_or(Error::ListenerNotFound(listener_id))?;

        for task in entry.tasks {
            task.abort();
        }
        if let Some(endpoint) = entry.http3_endpoint.take() {
            endpoint.close(VarInt::from_u32(0), b"listener closed");
        }
        Ok(())
    }

    fn shutdown(&self) {
        let listener_entries: Vec<ListenerEntry> = self
            .listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .drain()
            .map(|(_, entry)| entry)
            .collect();
        for mut entry in listener_entries {
            for task in entry.tasks {
                task.abort();
            }
            if let Some(endpoint) = entry.http3_endpoint.take() {
                endpoint.close(VarInt::from_u32(0), b"shutdown");
            }
        }

        let connection_entries: Vec<ConnectionEntry> = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .drain()
            .map(|(_, entry)| entry)
            .collect();
        for entry in connection_entries {
            match entry.record {
                ConnectionRecord::RawSocket {
                    reader_abort,
                    writer_abort,
                    heartbeat_abort,
                    ..
                } => {
                    reader_abort.abort();
                    writer_abort.abort();
                    if let Some(abort) = heartbeat_abort {
                        abort.abort();
                    }
                }
                ConnectionRecord::WebSocket {
                    reader_abort,
                    writer_abort,
                    heartbeat_abort,
                    ..
                } => {
                    reader_abort.abort();
                    writer_abort.abort();
                    if let Some(abort) = heartbeat_abort {
                        abort.abort();
                    }
                }
                ConnectionRecord::WebSocketPending { .. }
                | ConnectionRecord::HttpPending { .. }
                | ConnectionRecord::Http2Pending { .. }
                | ConnectionRecord::Http3Pending { .. } => {}
            }
        }
    }

    fn close_connection(&self, connection_id: ConnectionId) -> Result<(), Error> {
        let entry = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .remove(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match entry.record {
            ConnectionRecord::RawSocket {
                reader_abort,
                writer_abort,
                heartbeat_abort,
                ..
            } => {
                reader_abort.abort();
                writer_abort.abort();
                if let Some(abort) = heartbeat_abort {
                    abort.abort();
                }
            }
            ConnectionRecord::WebSocket {
                reader_abort,
                writer_abort,
                heartbeat_abort,
                send_tx,
                ..
            } => {
                reader_abort.abort();
                if let Some(abort) = heartbeat_abort {
                    abort.abort();
                }
                drop(send_tx);
                drop(writer_abort);
            }
            ConnectionRecord::WebSocketPending { .. }
            | ConnectionRecord::HttpPending { .. }
            | ConnectionRecord::Http2Pending { .. }
            | ConnectionRecord::Http3Pending { .. } => {}
        }
        Ok(())
    }

    fn register_rawsocket_connection(
        self: Arc<Self>,
        handle: tokio::runtime::Handle,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        negotiated: rawsocket::NegotiatedSession,
        peer_addr: SocketAddr,
    ) {
        let (frame_tx, frame_rx) = mpsc::channel(1024);
        let (send_tx, send_rx) = mpsc::channel(endpoint_config.outbound_send_queue_capacity);
        let (close_tx, mut close_rx) = mpsc::unbounded_channel::<ConnectionTaskSignal>();
        let serializer = negotiated.serializer;
        let max_exponent = negotiated.max_message_size_exponent;
        let (pong_tx, pong_rx) = mpsc::unbounded_channel::<Bytes>();
        let heartbeat_abort = endpoint_config.heartbeat_interval.map(|interval| {
            let timeout = endpoint_config
                .heartbeat_timeout
                .unwrap_or_else(|| interval.checked_mul(2).unwrap_or(Duration::from_secs(30)));
            spawn_connection_heartbeat(
                handle.clone(),
                Arc::clone(&self),
                connection_id,
                interval,
                timeout,
                send_tx.clone(),
                pong_rx,
            )
        });
        let pong_tx = heartbeat_abort.as_ref().map(|_| pong_tx);

        let reader_abort = spawn_connection_reader(
            handle.clone(),
            connection_id,
            Arc::clone(&endpoint_config),
            negotiated.reader,
            serializer,
            max_exponent,
            frame_tx,
            send_tx.clone(),
            pong_tx,
            close_tx.clone(),
        );
        let close_watch_handle = handle.clone();
        let writer_abort = spawn_connection_writer(
            handle,
            connection_id,
            negotiated.writer,
            max_exponent,
            send_rx,
            close_tx,
        );

        let registry = Arc::clone(&self);
        close_watch_handle.spawn(async move {
            let _ = close_rx.recv().await;
            let _ = registry.close_connection(connection_id);
        });

        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::RawSocket,
                    websocket_protocol: None,
                    endpoint_config,
                    stats: None,
                    record: ConnectionRecord::RawSocket {
                        _serializer: serializer,
                        max_exponent,
                        frames: Arc::new(Mutex::new(frame_rx)),
                        reader_abort,
                        writer_abort,
                        heartbeat_abort,
                        send_tx,
                    },
                },
            );
    }

    fn register_websocket_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        handshake: protocol::WebSocketHandshake,
        peer_addr: SocketAddr,
    ) {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::WebSocket,
                    websocket_protocol: None,
                    endpoint_config,
                    stats: None,
                    record: ConnectionRecord::WebSocketPending {
                        handshake: Mutex::new(Some(handshake)),
                    },
                },
            );
    }

    fn accept_websocket_connection(
        self: Arc<Self>,
        handle: tokio::runtime::Handle,
        connection_id: ConnectionId,
        handshake: protocol::WebSocketHandshake,
        serializer: rawsocket::Serializer,
        protocol: Option<&str>,
    ) -> Result<(), Error> {
        let accept_value = websocket_accept_value(&handshake.sec_websocket_key);
        let mut stream = handshake.into_stream();
        runtime_block_on(
            &handle,
            write_websocket_handshake_response(&mut stream, &accept_value, protocol),
        )
        .map_err(Error::Io)?;
        let _ = stream.set_nodelay(true);
        let (reader, writer) = tokio::io::split(stream);
        let (listener_id, peer_addr, endpoint_config) = {
            let connections = self
                .connections
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            let entry = connections
                .get(&connection_id)
                .ok_or(Error::ConnectionNotFound(connection_id))?;
            (
                entry.listener_id,
                entry.peer_addr,
                Arc::clone(&entry.endpoint_config),
            )
        };
        self.register_established_websocket_connection(
            handle,
            listener_id,
            connection_id,
            endpoint_config,
            peer_addr,
            serializer,
            protocol.map(|value| value.to_string()),
            reader,
            writer,
            true,
            false,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn register_established_websocket_connection(
        self: Arc<Self>,
        handle: tokio::runtime::Handle,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        peer_addr: SocketAddr,
        serializer: rawsocket::Serializer,
        selected_protocol: Option<String>,
        reader: IoReadHalf,
        writer: IoWriteHalf,
        expect_masked_frames: bool,
        mask_outbound_frames: bool,
    ) -> Result<(), Error> {
        let (frame_tx, frame_rx) = mpsc::channel(1024);
        let (send_tx, send_rx) = mpsc::channel(endpoint_config.outbound_send_queue_capacity);
        let (close_tx, mut close_rx) = mpsc::unbounded_channel::<ConnectionTaskSignal>();
        let (pong_tx, pong_rx) = mpsc::unbounded_channel::<Bytes>();
        let heartbeat_abort = endpoint_config.heartbeat_interval.map(|interval| {
            let timeout = endpoint_config
                .heartbeat_timeout
                .unwrap_or_else(|| interval.checked_mul(2).unwrap_or(Duration::from_secs(30)));
            spawn_connection_heartbeat(
                handle.clone(),
                Arc::clone(&self),
                connection_id,
                interval,
                timeout,
                send_tx.clone(),
                pong_rx,
            )
        });
        let pong_tx = heartbeat_abort.as_ref().map(|_| pong_tx);

        let reader_abort = spawn_websocket_reader(
            handle.clone(),
            connection_id,
            serializer,
            endpoint_config.clone(),
            reader,
            frame_tx,
            send_tx.clone(),
            pong_tx,
            close_tx.clone(),
            expect_masked_frames,
        );
        let writer_abort = spawn_websocket_writer(
            handle.clone(),
            connection_id,
            serializer,
            writer,
            send_rx,
            close_tx,
            mask_outbound_frames,
        );

        let registry = Arc::clone(&self);
        handle.spawn(async move {
            if matches!(
                close_rx.recv().await,
                Some(ConnectionTaskSignal::ReaderGracefulClose)
            ) {
                let grace = time::sleep(Duration::from_millis(100));
                tokio::pin!(grace);
                loop {
                    tokio::select! {
                        signal = close_rx.recv() => match signal {
                            Some(ConnectionTaskSignal::WriterClosed) | None => break,
                            Some(ConnectionTaskSignal::ReaderClosed | ConnectionTaskSignal::ReaderGracefulClose) => {}
                        },
                        _ = &mut grace => break,
                    }
                }
            }
            let _ = registry.close_connection(connection_id);
        });

        let mut connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        connections.insert(
            connection_id,
            ConnectionEntry {
                listener_id,
                peer_addr,
                protocol: ConnectionProtocol::WebSocket,
                websocket_protocol: selected_protocol,
                endpoint_config,
                stats: None,
                record: ConnectionRecord::WebSocket {
                    _serializer: serializer,
                    frames: Arc::new(Mutex::new(frame_rx)),
                    reader_abort,
                    writer_abort,
                    heartbeat_abort,
                    send_tx,
                },
            },
        );
        Ok(())
    }

    fn reject_websocket_connection(
        &self,
        handle: tokio::runtime::Handle,
        connection_id: ConnectionId,
        handshake: protocol::WebSocketHandshake,
        status: StatusCode,
        reason: Option<&str>,
    ) -> Result<(), Error> {
        let mut stream = handshake.into_stream();
        let body = reason.unwrap_or("websocket upgrade rejected");
        let response = format!(
            "HTTP/1.1 {} {}\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{}",
            status.as_u16(),
            status.canonical_reason().unwrap_or(""),
            body.len(),
            body
        );
        runtime_block_on(&handle, async {
            stream.write_all(response.as_bytes()).await?;
            stream.flush().await?;
            let _ = stream.shutdown().await;
            Ok::<(), io::Error>(())
        })
        .map_err(Error::Io)?;
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .remove(&connection_id);
        Ok(())
    }

    fn finish_http_connection(
        &self,
        connection_id: ConnectionId,
        reason: HttpConnectionCloseReason,
        detail: Option<String>,
    ) {
        #[cfg(feature = "ffi-test")]
        eprintln!(
            "registry: finish_http_connection {:?} reason {:?} detail {:?}",
            connection_id, reason, detail
        );
        let entry = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .remove(&connection_id);
        if let Some(entry) = entry {
            if let Some(stats) = entry.stats {
                let event = stats.finalize(connection_id, reason, detail);
                self.push_connection_event(entry.listener_id, event);
            }
        }
    }

    fn push_connection_event(&self, listener_id: ListenerId, event: HttpConnectionEvent) {
        record_http_metrics(listener_id, &event);
        self.connection_events
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .push_back(event);
    }

    fn poll_http_connection_event(&self) -> Option<HttpConnectionEvent> {
        self.connection_events
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .pop_front()
    }

    fn register_http_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        peer_addr: SocketAddr,
    ) {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::Http,
                    websocket_protocol: None,
                    endpoint_config,
                    stats: None,
                    record: ConnectionRecord::HttpPending {
                        pending_requests: Mutex::new(VecDeque::new()),
                    },
                },
            );
    }

    fn register_http2_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        handshake: protocol::Http2Handshake,
        peer_addr: SocketAddr,
    ) {
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http2);
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::Http2,
                    websocket_protocol: None,
                    endpoint_config,
                    stats: Some(Arc::clone(&stats)),
                    record: ConnectionRecord::Http2Pending {
                        handshake: Mutex::new(Some(handshake)),
                        pending_requests: Mutex::new(VecDeque::new()),
                    },
                },
            );
    }

    fn register_http3_connection(
        &self,
        listener_id: ListenerId,
        connection_id: ConnectionId,
        endpoint_config: Arc<config::EndpointRuntimeConfig>,
        handshake: protocol::Http3Handshake,
        connection: Option<Arc<QuinnConnection>>,
        peer_addr: SocketAddr,
    ) -> Arc<Http3StreamChannels> {
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http3);
        let streams = Arc::new(Http3StreamChannels::new());
        {
            let mut guard = self
                .connections
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            guard.insert(
                connection_id,
                ConnectionEntry {
                    listener_id,
                    peer_addr,
                    protocol: ConnectionProtocol::Http3,
                    websocket_protocol: None,
                    endpoint_config,
                    stats: Some(Arc::clone(&stats)),
                    record: ConnectionRecord::Http3Pending {
                        handshake: Mutex::new(Some(handshake)),
                        connection: Mutex::new(connection),
                        streams: Arc::clone(&streams),
                        pending_requests: Mutex::new(VecDeque::new()),
                    },
                },
            );
            #[cfg(feature = "ffi-test")]
            {
                let snapshot: Vec<String> = guard
                    .iter()
                    .map(|(id, entry)| format!("{:?}:{:?}", id, entry.protocol))
                    .collect();
                eprintln!(
                    "registry: registered http3 connection {:?} for listener {:?}, peers {:?}, connections={:?}",
                    connection_id, listener_id, peer_addr, snapshot
                );
            }
        }
        streams
    }

    fn connection_config(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Arc<config::EndpointRuntimeConfig>, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| Arc::clone(&entry.endpoint_config))
            .ok_or(Error::ConnectionNotFound(connection_id))
    }

    fn connection_stats(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<Arc<HttpConnectionStats>>, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| entry.stats.clone())
            .ok_or(Error::ConnectionNotFound(connection_id))
    }

    fn listener_config(
        &self,
        listener_id: ListenerId,
    ) -> Result<Arc<config::EndpointRuntimeConfig>, Error> {
        self.listeners
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&listener_id)
            .map(|entry| entry.config_state.endpoint_config())
            .ok_or(Error::ListenerNotFound(listener_id))
    }

    fn connection_exponent(&self, connection_id: ConnectionId) -> Result<u32, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::RawSocket { max_exponent, .. } => Ok(*max_exponent),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn connection_protocol(
        &self,
        connection_id: ConnectionId,
    ) -> Result<ConnectionProtocol, Error> {
        self.connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .get(&connection_id)
            .map(|entry| entry.protocol)
            .ok_or(Error::ConnectionNotFound(connection_id))
    }

    fn connection_websocket_protocol(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<String>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match entry.protocol {
            ConnectionProtocol::WebSocket => Ok(entry.websocket_protocol.clone()),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn poll_message(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<wamp::ParsedMessage>, Error> {
        let frames = self.message_frames(connection_id)?;
        let mut receiver = frames.lock().unwrap();
        match receiver.try_recv() {
            Ok(message) => Ok(Some(message)),
            Err(TryRecvError::Empty) => Ok(None),
            Err(TryRecvError::Disconnected) => Ok(None),
        }
    }

    fn message_frames(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Arc<Mutex<mpsc::Receiver<wamp::ParsedMessage>>>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::RawSocket { frames, .. }
            | ConnectionRecord::WebSocket { frames, .. } => Ok(Arc::clone(frames)),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn enqueue_frame(
        &self,
        connection_id: ConnectionId,
        frame: OutboundFrame,
    ) -> Result<(), Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::RawSocket { send_tx, .. }
            | ConnectionRecord::WebSocket { send_tx, .. } => match send_tx.try_send(frame) {
                Ok(()) => Ok(()),
                Err(TrySendError::Full(_)) => Err(Error::SendQueueFull(connection_id)),
                Err(TrySendError::Closed(_)) => Err(Error::ConnectionNotFound(connection_id)),
            },
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn take_websocket_handshake(
        &self,
        connection_id: ConnectionId,
    ) -> Result<protocol::WebSocketHandshake, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::WebSocketPending { handshake } => {
                let mut guard = handshake.lock().unwrap();
                guard
                    .take()
                    .ok_or(Error::HandshakeAlreadyTaken(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn take_http2_handshake(
        &self,
        connection_id: ConnectionId,
    ) -> Result<protocol::Http2Handshake, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http2Pending { handshake, .. } => {
                let mut guard = handshake.lock().unwrap();
                guard
                    .take()
                    .ok_or(Error::HandshakeAlreadyTaken(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn take_http3_handshake(
        &self,
        connection_id: ConnectionId,
    ) -> Result<protocol::Http3Handshake, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        #[cfg(feature = "ffi-test")]
        {
            let snapshot: Vec<String> = connections
                .iter()
                .map(|(id, entry)| format!("{:?}:{:?}", id, entry.protocol))
                .collect();
            eprintln!(
                "registry: take_http3_handshake {:?}, connections={:?}",
                connection_id, snapshot
            );
        }
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http3Pending { handshake, .. } => {
                let mut guard = handshake.lock().unwrap();
                guard
                    .take()
                    .ok_or(Error::HandshakeAlreadyTaken(connection_id))
            }
            _ => {
                #[cfg(feature = "ffi-test")]
                eprintln!(
                    "registry: take_http3_handshake {:?} unsupported protocol {:?}",
                    connection_id, entry.protocol
                );
                Err(Error::UnsupportedProtocol(connection_id, entry.protocol))
            }
        }
    }

    fn http3_connection(&self, connection_id: ConnectionId) -> Result<Arc<QuinnConnection>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http3Pending { connection, .. } => {
                let guard = connection.lock().unwrap();
                guard
                    .as_ref()
                    .cloned()
                    .ok_or(Error::ConnectionHandleUnavailable(connection_id))
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn poll_http3_stream(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<Http3BidiStream>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::Http3Pending { streams, .. } => Ok(streams.try_recv()),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn enqueue_http_request(
        &self,
        connection_id: ConnectionId,
        request: QueuedHttpRequest,
    ) -> Result<(), Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::HttpPending { pending_requests }
            | ConnectionRecord::Http2Pending {
                pending_requests, ..
            }
            | ConnectionRecord::Http3Pending {
                pending_requests, ..
            } => {
                let stats = entry.stats.clone();
                let mut guard = pending_requests.lock().unwrap();
                let depth_before = guard.len();
                guard.push_back(request);
                if depth_before > 0 {
                    if let Some(stats) = stats.as_ref() {
                        stats.record_backpressure(depth_before + 1);
                    }
                }
                Ok(())
            }
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }

    fn poll_http_request(
        &self,
        connection_id: ConnectionId,
    ) -> Result<Option<(HttpRequestSummary, HttpResponseHandle)>, Error> {
        let connections = self
            .connections
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let entry = connections
            .get(&connection_id)
            .ok_or(Error::ConnectionNotFound(connection_id))?;
        match &entry.record {
            ConnectionRecord::HttpPending { pending_requests }
            | ConnectionRecord::Http2Pending {
                pending_requests, ..
            }
            | ConnectionRecord::Http3Pending {
                pending_requests, ..
            } => Ok(pending_requests
                .lock()
                .unwrap()
                .pop_front()
                .map(|entry| (entry.summary, entry.response))),
            _ => Err(Error::UnsupportedProtocol(connection_id, entry.protocol)),
        }
    }
}

fn start_http3_listener(
    listener_id: ListenerId,
    addr: SocketAddr,
    config_state: Arc<ListenerConfigState>,
    registry: Arc<ListenerRegistry>,
    sender: mpsc::Sender<ConnectionId>,
    handle: tokio::runtime::Handle,
) -> Result<(QuinnEndpoint, JoinHandle<()>, SocketAddr), Error> {
    let runtime_config = config_state.endpoint_config();
    let server_config = build_http3_server_config(&runtime_config)?;
    let endpoint = handle
        .block_on(async move { QuinnEndpoint::server(server_config, addr) })
        .map_err(Error::Io)?;
    let local_addr = endpoint.local_addr().map_err(Error::Io)?;

    let registry_for_task = Arc::clone(&registry);
    let config_for_task = Arc::clone(&config_state);
    let sender_for_task = sender.clone();
    let endpoint_for_task = endpoint.clone();
    let listener = handle.spawn(async move {
        loop {
            match endpoint_for_task.accept().await {
                Some(connecting) => match connecting.await {
                    Ok(connection) => {
                        let peer_addr = connection.remote_address();
                        let runtime_for_task = config_for_task.endpoint_config();
                        let handshake = Http3Handshake::from_endpoint(&runtime_for_task);
                        let connection_id = registry_for_task.next_connection_id();
                        #[cfg(feature = "ffi-test")]
                        eprintln!(
                            "http3 connection accepted on {:?} from {} (id {:?})",
                            listener_id, peer_addr, connection_id
                        );
                        let connection = Arc::new(connection);
                        let streams = registry_for_task.register_http3_connection(
                            listener_id,
                            connection_id,
                            Arc::clone(&runtime_for_task),
                            handshake,
                            Some(Arc::clone(&connection)),
                            peer_addr,
                        );
                        #[cfg(feature = "ffi-test")]
                        eprintln!(
                            "http3 registry stored {:?} with protocol {:?}",
                            connection_id,
                            registry_for_task.connection_protocol(connection_id)
                        );
                        let registry_for_connection = Arc::clone(&registry_for_task);
                        let endpoint_for_connection = Arc::clone(&runtime_for_task);
                        tokio::spawn(async move {
                            serve_http3_requests(
                                listener_id,
                                connection_id,
                                endpoint_for_connection,
                                registry_for_connection,
                                connection,
                                streams,
                            )
                            .await;
                        });
                        if sender_for_task.send(connection_id).await.is_err() {
                            break;
                        }
                    }
                    Err(err) => {
                        eprintln!(
                            "http3 connection failed for listener {:?}: {}",
                            listener_id, err
                        );
                    }
                },
                None => break,
            }
        }
    });

    Ok((endpoint, listener, local_addr))
}

fn build_http3_server_config(
    endpoint: &config::EndpointRuntimeConfig,
) -> Result<QuinnServerConfig, Error> {
    let (certs, key) = load_http3_identity(endpoint)?;
    let provider = rustls::crypto::ring::default_provider();
    let client_auth_verifier = tls::build_client_cert_verifier(endpoint, &provider)?;
    let builder = match client_auth_verifier {
        Some(verifier) => RustlsServerConfig::builder().with_client_cert_verifier(verifier),
        None => RustlsServerConfig::builder().with_no_client_auth(),
    };
    let mut crypto = builder.with_single_cert(certs, key).map_err(|err| {
        Error::RouterConfigInvalid(format!(
            "endpoint {}:{} http3 certificate invalid: {}",
            endpoint.host, endpoint.port, err
        ))
    })?;
    let mut alpn = endpoint
        .http_settings()
        .map(|settings| {
            settings
                .alpn
                .iter()
                .filter(|token| token.eq_ignore_ascii_case("h3") || token.starts_with("h3-"))
                .map(|token| token.as_bytes().to_vec())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if alpn.is_empty() {
        alpn.push(b"h3".to_vec());
    }
    crypto.alpn_protocols = alpn;
    let mut server = QuinnServerConfig::with_crypto(Arc::new(
        QuinnRustlsServerConfig::try_from(crypto).map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} http3 rustls config invalid: {}",
                endpoint.host, endpoint.port, err
            ))
        })?,
    ));
    let transport = Arc::get_mut(&mut server.transport).expect("fresh http3 transport config");
    apply_http3_transport_tuning(transport);
    Ok(server)
}

fn http2_server_builder() -> h2_server::Builder {
    let mut builder = h2_server::Builder::new();
    apply_http2_transport_tuning(&mut builder);
    builder
}

fn apply_http2_transport_tuning(builder: &mut h2_server::Builder) {
    builder
        .max_concurrent_streams(HTTP2_MAX_CONCURRENT_STREAMS)
        .initial_window_size(HTTP2_INITIAL_STREAM_WINDOW)
        .initial_connection_window_size(HTTP2_INITIAL_CONNECTION_WINDOW)
        .max_frame_size(HTTP2_MAX_FRAME_SIZE)
        .max_header_list_size(HTTP2_MAX_HEADER_LIST_SIZE)
        .max_concurrent_reset_streams(HTTP2_MAX_CONCURRENT_RESET_STREAMS)
        .max_send_buffer_size(HTTP2_MAX_SEND_BUFFER_SIZE);
}

fn apply_http3_transport_tuning(transport: &mut quinn::TransportConfig) {
    transport
        .max_concurrent_bidi_streams(VarInt::from_u32(HTTP3_MAX_BIDI_STREAMS))
        .max_concurrent_uni_streams(VarInt::from_u32(HTTP3_MAX_UNI_STREAMS))
        .stream_receive_window(VarInt::from_u32(HTTP3_STREAM_RECEIVE_WINDOW))
        .receive_window(VarInt::from_u32(HTTP3_CONNECTION_RECEIVE_WINDOW))
        .send_window(HTTP3_SEND_WINDOW)
        .datagram_receive_buffer_size(Some(HTTP3_DATAGRAM_BUFFER_BYTES))
        .datagram_send_buffer_size(HTTP3_DATAGRAM_BUFFER_BYTES)
        .keep_alive_interval(Some(HTTP3_KEEP_ALIVE_INTERVAL));
}

fn load_http3_identity(
    endpoint: &config::EndpointRuntimeConfig,
) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>), Error> {
    let cert_entry = endpoint.sni_certificates.first().ok_or_else(|| {
        Error::RouterConfigInvalid(format!(
            "endpoint {}:{} requires SNI certificate for http3",
            endpoint.host, endpoint.port
        ))
    })?;
    let mut cert_reader = Cursor::new(cert_entry.certificate_chain_pem.as_bytes());
    let certs = load_certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} failed to parse http3 certificate: {}",
                endpoint.host, endpoint.port, err
            ))
        })?;
    if certs.is_empty() {
        return Err(Error::RouterConfigInvalid(format!(
            "endpoint {}:{} http3 certificate chain empty",
            endpoint.host, endpoint.port
        )));
    }

    let private_key = {
        let mut key_reader = Cursor::new(cert_entry.private_key_pem.as_bytes());
        let mut keys = pkcs8_private_keys(&mut key_reader)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} failed to parse pkcs8 key for http3: {}",
                    endpoint.host, endpoint.port, err
                ))
            })?
            .into_iter()
            .map(|der| der.into())
            .collect::<Vec<_>>();
        if keys.is_empty() {
            let mut rsa_reader = Cursor::new(cert_entry.private_key_pem.as_bytes());
            keys = rsa_private_keys(&mut rsa_reader)
                .collect::<Result<Vec<_>, _>>()
                .map_err(|err| {
                    Error::RouterConfigInvalid(format!(
                        "endpoint {}:{} failed to parse rsa key for http3: {}",
                        endpoint.host, endpoint.port, err
                    ))
                })?
                .into_iter()
                .map(|der| der.into())
                .collect();
        }
        keys.into_iter().next().ok_or_else(|| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} http3 private key missing",
                endpoint.host, endpoint.port
            ))
        })?
    };

    Ok((certs, private_key))
}

#[derive(Debug)]
enum FrameReadError {
    Io(io::Error),
    Protocol(String),
}

impl From<io::Error> for FrameReadError {
    fn from(value: io::Error) -> Self {
        FrameReadError::Io(value)
    }
}

impl std::fmt::Display for FrameReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FrameReadError::Io(err) => write!(f, "io error: {}", err),
            FrameReadError::Protocol(msg) => write!(f, "protocol error: {}", msg),
        }
    }
}

impl std::error::Error for FrameReadError {}

enum InboundFrame {
    Message(Bytes),
    Ping(Bytes),
    Pong(Bytes),
}

#[derive(Debug, Clone)]
struct OutboundFrame {
    frame_type: u8,
    payload_len: usize,
    segments: Vec<Bytes>,
}

impl OutboundFrame {
    fn message(payload: Bytes) -> Self {
        let len = payload.len();
        Self {
            frame_type: 0,
            payload_len: len,
            segments: vec![payload],
        }
    }

    fn message_segments(segments: Vec<Bytes>) -> Self {
        let payload_len = segments.iter().map(|segment| segment.len()).sum();
        Self {
            frame_type: 0,
            payload_len,
            segments,
        }
    }

    fn control(frame_type: u8, payload: Bytes) -> Self {
        let len = payload.len();
        Self {
            frame_type,
            payload_len: len,
            segments: vec![payload],
        }
    }

    fn close(code: Option<u16>, reason: &str) -> Self {
        Self::control(0x03, encode_websocket_close_payload(code, reason))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ConnectionTaskSignal {
    ReaderClosed,
    ReaderGracefulClose,
    WriterClosed,
}

fn spawn_connection_reader(
    handle: tokio::runtime::Handle,
    connection_id: ConnectionId,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    mut reader: IoReadHalf,
    serializer: rawsocket::Serializer,
    max_message_size_exponent: u32,
    frame_tx: mpsc::Sender<wamp::ParsedMessage>,
    send_tx: mpsc::Sender<OutboundFrame>,
    pong_tx: Option<UnboundedSender<Bytes>>,
    close_tx: UnboundedSender<ConnectionTaskSignal>,
) -> AbortHandle {
    let task = handle.spawn(async move {
        let max_payload = 1u64 << max_message_size_exponent;
        let upgraded_protocol = max_message_size_exponent > 24;
        let idle_timeout = endpoint_config.idle_timeout;

        loop {
            let read_future = read_inbound_frame(&mut reader, max_payload, upgraded_protocol);
            let frame = if let Some(timeout) = idle_timeout {
                match time::timeout(timeout, read_future).await {
                    Ok(result) => result,
                    Err(_) => {
                        eprintln!(
                            "connection {:?} idle for {:?}, closing",
                            connection_id, timeout
                        );
                        break;
                    }
                }
            } else {
                read_future.await
            };

            let frame = match frame {
                Ok(frame) => frame,
                Err(FrameReadError::Io(err)) => {
                    if err.kind() != io::ErrorKind::UnexpectedEof {
                        eprintln!("connection {:?} io error: {}", connection_id, err);
                    }
                    break;
                }
                Err(FrameReadError::Protocol(reason)) => {
                    eprintln!(
                        "connection {:?} protocol violation: {}",
                        connection_id, reason
                    );
                    break;
                }
            };

            match frame {
                InboundFrame::Message(payload) => match wamp::parse_message(serializer, payload) {
                    Ok(parsed) => {
                        if frame_tx.send(parsed).await.is_err() {
                            break;
                        }
                    }
                    Err(err) => {
                        eprintln!(
                            "connection {:?} failed to parse WAMP message: {:?}",
                            connection_id, err
                        );
                        break;
                    }
                },
                InboundFrame::Ping(payload) => {
                    if send_tx
                        .send(OutboundFrame::control(0x02, payload))
                        .await
                        .is_err()
                    {
                        break;
                    }
                }
                InboundFrame::Pong(payload) => {
                    if let Some(tx) = &pong_tx {
                        let _ = tx.send(payload);
                    }
                }
            }
        }
        let _ = close_tx.send(ConnectionTaskSignal::ReaderClosed);
    });
    task.abort_handle()
}

fn spawn_connection_writer(
    handle: tokio::runtime::Handle,
    connection_id: ConnectionId,
    mut writer: IoWriteHalf,
    max_message_size_exponent: u32,
    mut rx: mpsc::Receiver<OutboundFrame>,
    close_tx: UnboundedSender<ConnectionTaskSignal>,
) -> AbortHandle {
    let task = handle.spawn(async move {
        let upgraded_protocol = max_message_size_exponent > 24;
        while let Some(frame) = rx.recv().await {
            if frame.frame_type > 2 {
                continue;
            }
            let header =
                match encode_frame_header(frame.frame_type, frame.payload_len, upgraded_protocol) {
                    Ok(header) => header,
                    Err(err) => {
                        eprintln!(
                            "connection {:?} failed to encode outbound frame header: {}",
                            connection_id, err
                        );
                        continue;
                    }
                };

            if let Err(err) = writer.write_all(header.as_bytes()).await {
                if err.kind() != io::ErrorKind::BrokenPipe {
                    eprintln!(
                        "connection {:?} failed to write frame header: {}",
                        connection_id, err
                    );
                }
                break;
            }

            for segment in frame.segments {
                if segment.is_empty() {
                    continue;
                }
                if let Err(err) = writer.write_all(&segment).await {
                    if err.kind() != io::ErrorKind::BrokenPipe {
                        eprintln!(
                            "connection {:?} failed to write frame payload: {}",
                            connection_id, err
                        );
                    }
                    break;
                }
            }
        }
        let _ = close_tx.send(ConnectionTaskSignal::WriterClosed);
    });
    task.abort_handle()
}

fn spawn_connection_heartbeat(
    handle: tokio::runtime::Handle,
    registry: Arc<ListenerRegistry>,
    connection_id: ConnectionId,
    interval: Duration,
    timeout: Duration,
    send_tx: mpsc::Sender<OutboundFrame>,
    mut pong_rx: UnboundedReceiver<Bytes>,
) -> AbortHandle {
    let task = handle.spawn(async move {
        let mut ticker = time::interval(interval);
        ticker.set_missed_tick_behavior(time::MissedTickBehavior::Delay);

        let mut next_nonce: u64 = 1;
        let mut awaiting = false;
        let mut last_ping_at = Instant::now();
        let mut last_payload = Bytes::new();

        loop {
            tokio::select! {
                _ = ticker.tick() => {
                    if awaiting {
                        if last_ping_at.elapsed() >= timeout {
                            eprintln!(
                                "connection {:?} heartbeat timeout after {:?}, closing",
                                connection_id, timeout
                            );
                            let _ = registry.close_connection(connection_id);
                            break;
                        }
                        continue;
                    }

                    let payload = Bytes::copy_from_slice(&next_nonce.to_be_bytes());
                    next_nonce = next_nonce.wrapping_add(1);
                    last_payload = payload.clone();
                    last_ping_at = Instant::now();
                    awaiting = true;
                    if send_tx
                        .send(OutboundFrame::control(0x01, payload))
                        .await
                        .is_err()
                    {
                        let _ = registry.close_connection(connection_id);
                        break;
                    }
                }
                received = pong_rx.recv() => {
                    let Some(payload) = received else {
                        break;
                    };
                    if awaiting && payload == last_payload {
                        awaiting = false;
                    } else {
                        // Treat any pong as liveness; payload mismatch might come from
                        // other intermediaries. We'll resync on the next ping.
                        awaiting = false;
                    }
                }
            }
        }
    });
    task.abort_handle()
}

fn spawn_websocket_reader(
    handle: tokio::runtime::Handle,
    connection_id: ConnectionId,
    serializer: rawsocket::Serializer,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    mut reader: IoReadHalf,
    frame_tx: mpsc::Sender<wamp::ParsedMessage>,
    send_tx: mpsc::Sender<OutboundFrame>,
    pong_tx: Option<UnboundedSender<Bytes>>,
    close_tx: UnboundedSender<ConnectionTaskSignal>,
    expect_masked_frames: bool,
) -> AbortHandle {
    let task = handle.spawn(async move {
        let idle_timeout = endpoint_config.idle_timeout;
        let buffer_pool = Arc::new(WebSocketBufferPool::default());
        let mut accumulator = WebSocketMessageAccumulator::new(Arc::clone(&buffer_pool));
        let mut graceful_close_requested = false;
        loop {
            let read_future =
                read_websocket_frame_mode(&mut reader, &buffer_pool, expect_masked_frames);
            let frame = if let Some(timeout) = idle_timeout {
                match time::timeout(timeout, read_future).await {
                    Ok(result) => result,
                    Err(_) => {
                        eprintln!(
                            "connection {:?} idle for {:?}, closing",
                            connection_id, timeout
                        );
                        break;
                    }
                }
            } else {
                read_future.await
            };

            let frame = match frame {
                Ok(frame) => frame,
                Err(err) => {
                    if err.is_peer_disconnect() {
                        break;
                    }
                    eprintln!("connection {:?} websocket error: {}", connection_id, err);
                    if let Some(code) = err.close_code() {
                        graceful_close_requested = send_tx
                            .send(OutboundFrame::close(Some(code), ""))
                            .await
                            .is_ok();
                    }
                    break;
                }
            };

            match frame {
                WebSocketFrame::Data {
                    opcode,
                    fin,
                    payload,
                } => {
                    if let Err(err) = accumulator.push(opcode, fin, payload) {
                        eprintln!(
                            "connection {:?} websocket framing error: {}",
                            connection_id, err
                        );
                        if let Some(code) = err.close_code() {
                            graceful_close_requested = send_tx
                                .send(OutboundFrame::close(Some(code), ""))
                                .await
                                .is_ok();
                        }
                        break;
                    }
                    if let Some(message) = accumulator.take_complete() {
                        if let Err(err) =
                            handle_websocket_message(serializer, message, &buffer_pool, &frame_tx)
                                .await
                        {
                            eprintln!(
                                "connection {:?} failed to parse WAMP message: {}",
                                connection_id, err
                            );
                            break;
                        }
                    }
                }
                WebSocketFrame::Ping(payload) => {
                    let _ = send_tx.send(OutboundFrame::control(0x02, payload)).await;
                }
                WebSocketFrame::Pong(payload) => {
                    if let Some(tx) = &pong_tx {
                        let _ = tx.send(payload);
                    }
                }
                WebSocketFrame::Close(code, reason) => {
                    graceful_close_requested = send_tx
                        .send(OutboundFrame::close(code, &reason))
                        .await
                        .is_ok();
                    break;
                }
            }
        }
        let signal = if graceful_close_requested {
            ConnectionTaskSignal::ReaderGracefulClose
        } else {
            ConnectionTaskSignal::ReaderClosed
        };
        let _ = close_tx.send(signal);
    });
    task.abort_handle()
}

fn spawn_websocket_writer(
    handle: tokio::runtime::Handle,
    connection_id: ConnectionId,
    serializer: rawsocket::Serializer,
    mut writer: IoWriteHalf,
    mut rx: mpsc::Receiver<OutboundFrame>,
    close_tx: UnboundedSender<ConnectionTaskSignal>,
    mask_outbound_frames: bool,
) -> AbortHandle {
    let task = handle.spawn(async move {
        let mut close_sent = false;
        let mut write_failed = false;
        let mut mask_scratch = Vec::with_capacity(WEBSOCKET_MASK_CHUNK_SIZE);
        while let Some(frame) = rx.recv().await {
            let is_close_frame = frame.frame_type == 3;
            let opcode = match frame.frame_type {
                0 => match serializer {
                    rawsocket::Serializer::Json => 0x1,
                    _ => 0x2,
                },
                1 => 0x9,
                2 => 0xA,
                3 => 0x8,
                _ => continue,
            };
            if let Err(err) = write_websocket_frame_mode(
                &mut writer,
                opcode,
                frame.payload_len,
                &frame.segments,
                mask_outbound_frames,
                &mut mask_scratch,
            )
            .await
            {
                if !is_benign_socket_shutdown(err.kind()) {
                    eprintln!(
                        "connection {:?} failed to write websocket frame: {}",
                        connection_id, err
                    );
                }
                write_failed = true;
                break;
            }
            if is_close_frame {
                close_sent = true;
                break;
            }
        }
        if !close_sent && !write_failed {
            let close_frame = OutboundFrame::close(Some(1000), "");
            if let Err(err) = write_websocket_frame_mode(
                &mut writer,
                0x8,
                close_frame.payload_len,
                &close_frame.segments,
                mask_outbound_frames,
                &mut mask_scratch,
            )
            .await
            {
                if !is_benign_socket_shutdown(err.kind()) {
                    eprintln!(
                        "connection {:?} failed to write websocket close frame: {}",
                        connection_id, err
                    );
                }
            }
        }
        let _ = close_tx.send(ConnectionTaskSignal::WriterClosed);
    });
    task.abort_handle()
}

async fn read_inbound_frame(
    stream: &mut IoReadHalf,
    max_payload: u64,
    upgraded_protocol: bool,
) -> Result<InboundFrame, FrameReadError> {
    let (frame_type, length_u64) = if upgraded_protocol {
        let mut header = [0u8; 5];
        stream.read_exact(&mut header).await?;
        if header[0] & !0x07 != 0 {
            return Err(FrameReadError::Protocol(
                "reserved bits must be zero".into(),
            ));
        }
        let frame_type = header[0] & 0x07;
        let length = u32::from_be_bytes([header[1], header[2], header[3], header[4]]) as u64;
        (frame_type, length)
    } else {
        let mut header = [0u8; 4];
        stream.read_exact(&mut header).await?;

        let reserved = header[0] >> 4;
        if reserved != 0 {
            return Err(FrameReadError::Protocol(
                "reserved bits must be zero".into(),
            ));
        }

        let length_hi = (header[0] >> 3) & 0x01;
        let frame_type = header[0] & 0x07;

        let mut length = ((header[1] as u32) << 16) | ((header[2] as u32) << 8) | header[3] as u32;
        if length_hi == 1 {
            if length != 0 {
                return Err(FrameReadError::Protocol(
                    "extended length bit set with non-zero length bytes".into(),
                ));
            }
            length = 1 << 24;
        }

        (frame_type, length as u64)
    };

    if length_u64 > max_payload {
        return Err(FrameReadError::Protocol(format!(
            "frame length {} exceeds negotiated maximum {}",
            length_u64, max_payload
        )));
    }
    if !upgraded_protocol && length_u64 > MAX_FRAME_LEN {
        return Err(FrameReadError::Protocol(format!(
            "frame length {} exceeds supported maximum {}",
            length_u64, MAX_FRAME_LEN
        )));
    }

    let payload = if length_u64 == 0 {
        Bytes::new()
    } else {
        let mut buf = BytesMut::with_capacity(length_u64 as usize);
        buf.resize(length_u64 as usize, 0);
        stream.read_exact(&mut buf).await?;
        buf.freeze()
    };

    match frame_type {
        0 => Ok(InboundFrame::Message(payload)),
        1 => Ok(InboundFrame::Ping(payload)),
        2 => Ok(InboundFrame::Pong(payload)),
        _ => Err(FrameReadError::Protocol(format!(
            "unsupported frame type {}",
            frame_type
        ))),
    }
}

#[derive(Debug)]
enum WebSocketFrame {
    Data {
        opcode: u8,
        fin: bool,
        payload: Bytes,
    },
    Ping(Bytes),
    Pong(Bytes),
    Close(Option<u16>, String),
}

#[derive(Debug)]
struct WebSocketFrameError {
    message: String,
    close_code: Option<u16>,
    io_kind: Option<io::ErrorKind>,
}

impl WebSocketFrameError {
    fn io(err: io::Error) -> Self {
        Self {
            message: err.to_string(),
            close_code: None,
            io_kind: Some(err.kind()),
        }
    }

    fn protocol(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            close_code: Some(1002),
            io_kind: None,
        }
    }

    fn invalid_payload(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            close_code: Some(1007),
            io_kind: None,
        }
    }

    fn message_too_big(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            close_code: Some(1009),
            io_kind: None,
        }
    }

    fn close_code(&self) -> Option<u16> {
        self.close_code
    }

    fn is_peer_disconnect(&self) -> bool {
        matches!(
            self.io_kind,
            Some(
                io::ErrorKind::UnexpectedEof
                    | io::ErrorKind::BrokenPipe
                    | io::ErrorKind::ConnectionReset
                    | io::ErrorKind::ConnectionAborted
            )
        )
    }
}

impl std::fmt::Display for WebSocketFrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for WebSocketFrameError {}

const MAX_POOLED_WEBSOCKET_BUFFERS: usize = 32;

#[derive(Debug, Default)]
struct WebSocketBufferPool {
    buffers: Mutex<Vec<Vec<u8>>>,
}

impl WebSocketBufferPool {
    fn acquire(self: &Arc<Self>, len: usize) -> PooledWebSocketBuffer {
        let mut buffer = self.take_buffer(len);
        buffer.resize(len, 0);
        PooledWebSocketBuffer {
            pool: Arc::clone(self),
            buffer,
        }
    }

    fn acquire_capacity(self: &Arc<Self>, capacity: usize) -> PooledWebSocketBuffer {
        let buffer = self.take_buffer(capacity);
        PooledWebSocketBuffer {
            pool: Arc::clone(self),
            buffer,
        }
    }

    fn take_buffer(&self, min_capacity: usize) -> Vec<u8> {
        let mut buffers = self
            .buffers
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if let Some(index) = buffers
            .iter()
            .position(|buffer| buffer.capacity() >= min_capacity)
        {
            return buffers.swap_remove(index);
        }
        Vec::with_capacity(min_capacity)
    }

    fn recycle(&self, mut buffer: Vec<u8>) {
        buffer.clear();
        let mut buffers = self
            .buffers
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if buffers.len() < MAX_POOLED_WEBSOCKET_BUFFERS {
            buffers.push(buffer);
        }
    }

    #[cfg(test)]
    fn available_buffers(&self) -> usize {
        self.buffers
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .len()
    }
}

#[derive(Debug)]
struct PooledWebSocketBuffer {
    pool: Arc<WebSocketBufferPool>,
    buffer: Vec<u8>,
}

impl PooledWebSocketBuffer {
    fn as_mut_slice(&mut self) -> &mut [u8] {
        self.buffer.as_mut_slice()
    }

    fn extend_from_bytes(&mut self, bytes: &Bytes) {
        self.buffer.extend_from_slice(bytes.as_ref());
    }

    fn into_bytes(self) -> Bytes {
        Bytes::from_owner(self)
    }
}

impl AsRef<[u8]> for PooledWebSocketBuffer {
    fn as_ref(&self) -> &[u8] {
        self.buffer.as_ref()
    }
}

impl Drop for PooledWebSocketBuffer {
    fn drop(&mut self) {
        let buffer = std::mem::take(&mut self.buffer);
        if buffer.capacity() > 0 {
            self.pool.recycle(buffer);
        }
    }
}

#[derive(Debug)]
enum WebSocketMessageStorage {
    Single(Bytes),
    Segmented { segments: Vec<Bytes>, len: usize },
}

#[derive(Debug)]
enum CompletedWebSocketMessage {
    Single(Bytes),
    Segmented { segments: Vec<Bytes>, len: usize },
}

impl CompletedWebSocketMessage {
    fn into_bytes(self, pool: &Arc<WebSocketBufferPool>) -> Bytes {
        match self {
            CompletedWebSocketMessage::Single(bytes) => bytes,
            CompletedWebSocketMessage::Segmented { segments, len } => {
                let mut pooled = pool.acquire_capacity(len);
                for segment in segments {
                    if segment.is_empty() {
                        continue;
                    }
                    pooled.extend_from_bytes(&segment);
                }
                pooled.into_bytes()
            }
        }
    }
}

struct WebSocketMessageAccumulator {
    opcode: Option<u8>,
    storage: Option<WebSocketMessageStorage>,
    complete: bool,
}

impl WebSocketMessageAccumulator {
    fn new(_pool: Arc<WebSocketBufferPool>) -> Self {
        Self {
            opcode: None,
            storage: None,
            complete: false,
        }
    }

    fn push(&mut self, opcode: u8, fin: bool, payload: Bytes) -> Result<(), WebSocketFrameError> {
        if opcode == 0x0 {
            if self.opcode.is_none() {
                return Err(WebSocketFrameError::protocol(
                    "received continuation frame without initial opcode",
                ));
            }
        } else if opcode == 0x1 || opcode == 0x2 {
            if self.opcode.is_some() {
                return Err(WebSocketFrameError::protocol(
                    "received new data frame before finishing continuation",
                ));
            }
            self.opcode = Some(opcode);
        } else {
            return Err(WebSocketFrameError::protocol("unsupported data opcode"));
        }

        if self.len() + payload.len() > MAX_WEBSOCKET_MESSAGE_LEN {
            return Err(WebSocketFrameError::message_too_big(
                "websocket message exceeds supported length",
            ));
        }

        match self.storage.take() {
            None => {
                self.storage = Some(WebSocketMessageStorage::Single(payload));
            }
            Some(WebSocketMessageStorage::Single(existing)) => {
                let len = existing.len() + payload.len();
                self.storage = Some(WebSocketMessageStorage::Segmented {
                    segments: vec![existing, payload],
                    len,
                });
            }
            Some(WebSocketMessageStorage::Segmented {
                mut segments,
                mut len,
            }) => {
                len += payload.len();
                segments.push(payload);
                self.storage = Some(WebSocketMessageStorage::Segmented { segments, len });
            }
        }
        if fin {
            self.complete = true;
        }
        Ok(())
    }

    fn take_complete(&mut self) -> Option<CompletedWebSocketMessage> {
        if self.complete {
            self.opcode = None;
            self.complete = false;
            self.storage.take().map(|storage| match storage {
                WebSocketMessageStorage::Single(bytes) => CompletedWebSocketMessage::Single(bytes),
                WebSocketMessageStorage::Segmented { segments, len } => {
                    CompletedWebSocketMessage::Segmented { segments, len }
                }
            })
        } else {
            None
        }
    }

    fn len(&self) -> usize {
        match &self.storage {
            Some(WebSocketMessageStorage::Single(bytes)) => bytes.len(),
            Some(WebSocketMessageStorage::Segmented { len, .. }) => *len,
            None => 0,
        }
    }
}

#[cfg(test)]
async fn read_websocket_frame(
    reader: &mut IoReadHalf,
    buffer_pool: &Arc<WebSocketBufferPool>,
) -> Result<WebSocketFrame, WebSocketFrameError> {
    read_websocket_frame_mode(reader, buffer_pool, true).await
}

async fn read_websocket_frame_mode(
    reader: &mut IoReadHalf,
    buffer_pool: &Arc<WebSocketBufferPool>,
    expect_masked: bool,
) -> Result<WebSocketFrame, WebSocketFrameError> {
    let mut header = [0u8; 2];
    reader
        .read_exact(&mut header)
        .await
        .map_err(WebSocketFrameError::io)?;
    if header[0] & 0x70 != 0 {
        return Err(WebSocketFrameError::protocol(
            "websocket reserved bits must be zero",
        ));
    }
    let fin = header[0] & 0x80 != 0;
    let opcode = header[0] & 0x0F;
    let masked = header[1] & 0x80 != 0;
    if masked != expect_masked {
        return Err(WebSocketFrameError::protocol(if expect_masked {
            "client websocket frames must be masked"
        } else {
            "server websocket frames must not be masked"
        }));
    }
    let is_control_frame = opcode & 0x08 != 0;
    if is_control_frame && !fin {
        return Err(WebSocketFrameError::protocol(
            "websocket control frames must not be fragmented",
        ));
    }
    let mut len = (header[1] & 0x7F) as u64;
    if len == 126 {
        let mut extended = [0u8; 2];
        reader
            .read_exact(&mut extended)
            .await
            .map_err(WebSocketFrameError::io)?;
        len = u16::from_be_bytes(extended) as u64;
    } else if len == 127 {
        let mut extended = [0u8; 8];
        reader
            .read_exact(&mut extended)
            .await
            .map_err(WebSocketFrameError::io)?;
        len = u64::from_be_bytes(extended);
    }
    if is_control_frame && len > 125 {
        return Err(WebSocketFrameError::protocol(
            "websocket control frames must not exceed 125 bytes",
        ));
    }
    if len as usize > MAX_WEBSOCKET_MESSAGE_LEN {
        return Err(WebSocketFrameError::message_too_big(
            "websocket frame exceeds supported length",
        ));
    }
    let mut mask = [0u8; 4];
    if masked {
        reader
            .read_exact(&mut mask)
            .await
            .map_err(WebSocketFrameError::io)?;
    }
    let mut payload = if len == 0 {
        None
    } else {
        Some(buffer_pool.acquire(len as usize))
    };
    if len > 0 {
        reader
            .read_exact(
                payload
                    .as_mut()
                    .expect("payload buffer exists for non-empty websocket frame")
                    .as_mut_slice(),
            )
            .await
            .map_err(WebSocketFrameError::io)?;
        if let Some(payload) = payload.as_mut() {
            for (index, byte) in payload.as_mut_slice().iter_mut().enumerate() {
                *byte ^= mask[index % 4];
            }
        }
    }
    let payload = payload
        .map(PooledWebSocketBuffer::into_bytes)
        .unwrap_or_else(Bytes::new);
    match opcode {
        0x0 | 0x1 | 0x2 => Ok(WebSocketFrame::Data {
            opcode,
            fin,
            payload,
        }),
        0x8 => parse_websocket_close_frame_payload(&payload)
            .map(|(code, reason)| WebSocketFrame::Close(code, reason)),
        0x9 => Ok(WebSocketFrame::Ping(payload)),
        0xA => Ok(WebSocketFrame::Pong(payload)),
        _ => Err(WebSocketFrameError::protocol(
            "unsupported websocket opcode",
        )),
    }
}

fn parse_websocket_close_frame_payload(
    payload: &[u8],
) -> Result<(Option<u16>, String), WebSocketFrameError> {
    if payload.is_empty() {
        return Ok((None, String::new()));
    }
    if payload.len() == 1 {
        return Err(WebSocketFrameError::protocol(
            "websocket close frame payload must be empty or include a 2-byte status code",
        ));
    }
    let code = u16::from_be_bytes([payload[0], payload[1]]);
    let reason = std::str::from_utf8(&payload[2..])
        .map_err(|_| {
            WebSocketFrameError::invalid_payload("websocket close reason must be valid UTF-8")
        })?
        .to_string();
    Ok((Some(code), reason))
}

fn encode_websocket_close_payload(code: Option<u16>, reason: &str) -> Bytes {
    let Some(code) = code else {
        return Bytes::new();
    };
    let mut payload = Vec::with_capacity(125.min(reason.len() + 2));
    payload.extend_from_slice(&code.to_be_bytes());
    let reason_bytes = reason.as_bytes();
    let remaining = 125usize.saturating_sub(payload.len());
    payload.extend_from_slice(&reason_bytes[..reason_bytes.len().min(remaining)]);
    Bytes::from(payload)
}

#[cfg(test)]
async fn write_websocket_frame(
    writer: &mut IoWriteHalf,
    opcode: u8,
    payload_len: usize,
    segments: &[Bytes],
) -> io::Result<()> {
    let mut mask_scratch = Vec::new();
    write_websocket_frame_mode(
        writer,
        opcode,
        payload_len,
        segments,
        false,
        &mut mask_scratch,
    )
    .await
}

#[cfg(test)]
async fn write_websocket_frame_client(
    writer: &mut IoWriteHalf,
    opcode: u8,
    payload_len: usize,
    segments: &[Bytes],
) -> io::Result<()> {
    let mut mask_scratch = Vec::with_capacity(WEBSOCKET_MASK_CHUNK_SIZE);
    write_websocket_frame_mode(
        writer,
        opcode,
        payload_len,
        segments,
        true,
        &mut mask_scratch,
    )
    .await
}

async fn write_websocket_frame_mode(
    writer: &mut IoWriteHalf,
    opcode: u8,
    payload_len: usize,
    segments: &[Bytes],
    mask_payload: bool,
    mask_scratch: &mut Vec<u8>,
) -> io::Result<()> {
    let is_data_frame = matches!(opcode, 0x1 | 0x2);
    if is_data_frame
        && segments
            .iter()
            .filter(|segment| !segment.is_empty())
            .count()
            > 1
    {
        return write_websocket_continuation_frames(
            writer,
            opcode,
            segments,
            mask_payload,
            mask_scratch,
        )
        .await;
    }

    let payload = segments
        .iter()
        .find(|segment| !segment.is_empty())
        .map(Bytes::as_ref)
        .unwrap_or(&[]);
    write_websocket_frame_fragment_mode(
        writer,
        opcode,
        true,
        payload_len.min(payload.len()),
        payload,
        mask_payload,
        mask_scratch,
    )
    .await
}

async fn write_websocket_continuation_frames(
    writer: &mut IoWriteHalf,
    opcode: u8,
    segments: &[Bytes],
    mask_payload: bool,
    mask_scratch: &mut Vec<u8>,
) -> io::Result<()> {
    let non_empty_count = segments
        .iter()
        .filter(|segment| !segment.is_empty())
        .count();
    if non_empty_count <= 1 {
        let payload = segments
            .iter()
            .find(|segment| !segment.is_empty())
            .map(Bytes::as_ref)
            .unwrap_or(&[]);
        return write_websocket_frame_fragment_mode(
            writer,
            opcode,
            true,
            payload.len(),
            payload,
            mask_payload,
            mask_scratch,
        )
        .await;
    }

    let last_index = segments
        .iter()
        .enumerate()
        .rev()
        .find_map(|(index, segment)| (!segment.is_empty()).then_some(index))
        .expect("non-empty segment exists when continuation frames are requested");
    let mut sent_first = false;
    for (index, segment) in segments.iter().enumerate() {
        if segment.is_empty() {
            continue;
        }
        let frame_opcode = if sent_first { 0x0 } else { opcode };
        sent_first = true;
        write_websocket_frame_fragment_mode(
            writer,
            frame_opcode,
            index == last_index,
            segment.len(),
            segment.as_ref(),
            mask_payload,
            mask_scratch,
        )
        .await?;
    }
    Ok(())
}

async fn write_websocket_frame_fragment_mode(
    writer: &mut IoWriteHalf,
    opcode: u8,
    fin: bool,
    payload_len: usize,
    payload: &[u8],
    mask_payload: bool,
    mask_scratch: &mut Vec<u8>,
) -> io::Result<()> {
    let mut header = Vec::with_capacity(2);
    header.push((if fin { 0x80 } else { 0x00 }) | (opcode & 0x0F));
    if payload_len < 126 {
        header.push(payload_len as u8);
    } else if payload_len <= 0xFFFF {
        header.push(126);
        header.extend_from_slice(&(payload_len as u16).to_be_bytes());
    } else {
        header.push(127);
        header.extend_from_slice(&(payload_len as u64).to_be_bytes());
    }
    let mut mask = [0u8; 4];
    if mask_payload {
        header[1] |= 0x80;
        rand::thread_rng().fill_bytes(&mut mask);
        header.extend_from_slice(&mask);
    }
    writer.write_all(&header).await?;
    if !mask_payload {
        if !payload.is_empty() {
            writer.write_all(payload).await?;
        }
        return Ok(());
    }
    let mut remaining = payload;
    let mut payload_offset = 0usize;
    while !remaining.is_empty() {
        let chunk_len = remaining.len().min(WEBSOCKET_MASK_CHUNK_SIZE);
        if mask_scratch.len() < chunk_len {
            mask_scratch.resize(chunk_len, 0);
        }
        mask_scratch[..chunk_len].copy_from_slice(&remaining[..chunk_len]);
        for (index, byte) in mask_scratch[..chunk_len].iter_mut().enumerate() {
            *byte ^= mask[(payload_offset + index) % mask.len()];
        }
        writer.write_all(&mask_scratch[..chunk_len]).await?;
        payload_offset += chunk_len;
        remaining = &remaining[chunk_len..];
    }
    Ok(())
}

async fn handle_websocket_message(
    serializer: rawsocket::Serializer,
    data: CompletedWebSocketMessage,
    buffer_pool: &Arc<WebSocketBufferPool>,
    frame_tx: &mpsc::Sender<wamp::ParsedMessage>,
) -> Result<(), String> {
    let parsed = match data {
        CompletedWebSocketMessage::Single(data) => {
            let payload = match serializer {
                rawsocket::Serializer::Json => {
                    if std::str::from_utf8(data.as_ref()).is_err() {
                        return Err("websocket text frame payload is not valid UTF-8".into());
                    }
                    data
                }
                _ => data,
            };
            wamp::parse_message(serializer, payload)
        }
        CompletedWebSocketMessage::Segmented { segments, len } => match serializer {
            rawsocket::Serializer::Json => {
                let payload =
                    CompletedWebSocketMessage::Segmented { segments, len }.into_bytes(buffer_pool);
                if std::str::from_utf8(payload.as_ref()).is_err() {
                    return Err("websocket text frame payload is not valid UTF-8".into());
                }
                wamp::parse_message(serializer, payload)
            }
            _ => wamp::parse_message_segments(serializer, segments),
        },
    };
    match parsed {
        Ok(parsed) => frame_tx
            .send(parsed)
            .await
            .map_err(|_| "failed to enqueue websocket message".into()),
        Err(err) => Err(format!("failed to parse WAMP message: {:?}", err)),
    }
}

struct EncodedFrameHeader {
    bytes: [u8; 5],
    len: usize,
}

impl EncodedFrameHeader {
    fn as_bytes(&self) -> &[u8] {
        &self.bytes[..self.len]
    }
}

fn encode_frame_header(
    frame_type: u8,
    payload_len: usize,
    upgraded_protocol: bool,
) -> Result<EncodedFrameHeader, FrameReadError> {
    if frame_type > 0x07 {
        return Err(FrameReadError::Protocol(format!(
            "invalid frame type {}",
            frame_type
        )));
    }
    if upgraded_protocol {
        let length = u32::try_from(payload_len).map_err(|_| {
            FrameReadError::Protocol(format!(
                "payload length {} exceeds supported maximum {}",
                payload_len,
                u32::MAX
            ))
        })?;
        let mut header = [0u8; 5];
        header[0] = frame_type & 0x07;
        header[1..5].copy_from_slice(&length.to_be_bytes());
        return Ok(EncodedFrameHeader {
            bytes: header,
            len: 5,
        });
    }
    if payload_len > MAX_FRAME_LEN as usize {
        return Err(FrameReadError::Protocol(format!(
            "payload length {} exceeds supported maximum {}",
            payload_len, MAX_FRAME_LEN as usize
        )));
    }

    let mut header = [0u8; 5];
    let mut first = frame_type & 0x07;
    if payload_len == (MAX_FRAME_LEN as usize) {
        first |= 0x08;
    } else {
        header[1] = ((payload_len >> 16) & 0xFF) as u8;
        header[2] = ((payload_len >> 8) & 0xFF) as u8;
        header[3] = (payload_len & 0xFF) as u8;
    }
    header[0] = first;
    Ok(EncodedFrameHeader {
        bytes: header,
        len: 4,
    })
}

/// Initialises the multi-threaded tokio runtime if it has not been started yet.
pub fn start_runtime() -> Result<(), Error> {
    let manager = RuntimeManager::global();
    let mut guard = manager
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if guard.is_some() {
        return Err(Error::RuntimeAlreadyStarted);
    }

    // Ensure the platform allows native runtime creation.
    PlatformRuntime::new().map_err(|_| Error::UnsupportedPlatform)?;

    let worker_threads = runtime_worker_threads_from_env()?;
    let mut builder = tokio::runtime::Builder::new_multi_thread();
    builder.thread_name("connectanum-rt").enable_all();
    if let Some(worker_threads) = worker_threads {
        builder.worker_threads(worker_threads);
    }
    let runtime = builder.build()?;

    let handle = runtime.handle().clone();
    let state = RuntimeState {
        runtime,
        handle,
        registry: Arc::new(ListenerRegistry::default()),
    };
    *guard = Some(state);
    Ok(())
}

fn runtime_worker_threads_from_env() -> Result<Option<usize>, Error> {
    parse_runtime_worker_threads(std::env::var(NATIVE_RUNTIME_THREADS_ENV).ok().as_deref())
}

fn parse_runtime_worker_threads(raw: Option<&str>) -> Result<Option<usize>, Error> {
    let Some(raw) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let parsed = raw
        .parse::<usize>()
        .map_err(|_| Error::InvalidRuntimeThreadCount(raw.to_string()))?;
    if parsed == 0 {
        return Err(Error::InvalidRuntimeThreadCount(raw.to_string()));
    }
    Ok(Some(parsed))
}

/// Applies the router configuration JSON produced on the Dart side.
pub fn apply_router_config(bytes: &[u8]) -> Result<(), Error> {
    config::apply_router_config_bytes(bytes)
}

/// Rebuilds TLS configuration for all running listeners using the currently
/// applied router configuration.
pub fn reload_tls() -> Result<u32, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.reload_tls())
}

/// Gracefully shuts down the runtime and aborts all listener tasks.
pub fn shutdown() -> Result<(), Error> {
    let manager = RuntimeManager::global();
    let mut guard = manager
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if let Some(state) = guard.take() {
        state.shutdown();
    }
    Ok(())
}

/// Starts listening on the provided address and returns the allocated listener id.
pub fn listen(addr: &str, port: u16, backlog: i32) -> Result<ListenerId, Error> {
    if backlog <= 0 {
        return Err(Error::InvalidBacklog);
    }
    let manager = RuntimeManager::global();
    manager
        .with_state(|view| {
            let socket_addr = resolve_socket_addr(addr, port)?;
            let endpoint_config = config::find_endpoint(addr, port)
                .ok_or_else(|| Error::EndpointNotConfigured(addr.to_string(), port))?;
            let runtime_config = Arc::new(config::EndpointRuntimeConfig::try_from_endpoint(
                &endpoint_config,
            )?);
            let tls_acceptor = tls::build_tls_acceptor(&runtime_config)?;
            let config_state = Arc::new(ListenerConfigState::new(
                Arc::clone(&runtime_config),
                tls_acceptor,
            ));
            let std_listener = create_listener(socket_addr, backlog as u32)?;
            let local_addr = std_listener.local_addr()?;

            let (sender, receiver) = mpsc::channel(1024);
            let listener_id = view.registry.next_listener_id();
            let accept_registry = Arc::clone(&view.registry);
            let async_sender = sender.clone();
            let config_state_for_task = Arc::clone(&config_state);
            let runtime_handle = view.handle.clone();
            let task = runtime_handle.clone().spawn(async move {
                let listener = tokio::net::TcpListener::from_std(std_listener)
                    .expect("failed to convert listener to tokio");
                let tx = async_sender;
                loop {
                    match listener.accept().await {
                        Ok((stream, addr)) => {
                            let _ = stream.set_nodelay(true);
                            let runtime_config_for_task = config_state_for_task.endpoint_config();
                            let tls_acceptor_for_task = config_state_for_task.tls_acceptor();
                            let io_stream = match tls_acceptor_for_task.as_ref() {
                                Some(acceptor) => {
                                    let ktls_requested =
                                        ktls::server_runtime_requested(runtime_config_for_task.as_ref());
                                    if ktls_requested {
                                        match time::timeout(
                                            runtime_config_for_task.handshake_timeout,
                                            ktls::accept_server_stream(
                                                acceptor.config().clone(),
                                                stream,
                                            ),
                                        )
                                        .await
                                        {
                                            Ok(Ok(io_stream)) => io_stream,
                                            Ok(Err(err)) => {
                                                eprintln!(
                                                    "kTLS handoff failed for connection from {}: {}",
                                                    addr, err
                                                );
                                                continue;
                                            }
                                            Err(_) => {
                                                eprintln!(
                                                    "kTLS handshake timed out for connection from {}",
                                                    addr
                                                );
                                                continue;
                                            }
                                        }
                                    } else {
                                        let handshake = acceptor.accept(stream);
                                        match time::timeout(
                                            runtime_config_for_task.handshake_timeout,
                                            handshake,
                                        )
                                        .await
                                        {
                                            Ok(Ok(tls_stream)) => IoStream::tls(tls_stream),
                                            Ok(Err(err)) => {
                                                eprintln!(
                                                    "tls handshake failed for connection from {}: {}",
                                                    addr, err
                                                );
                                                continue;
                                            }
                                            Err(_) => {
                                                eprintln!(
                                                    "tls handshake timed out for connection from {}",
                                                    addr
                                                );
                                                continue;
                                            }
                                        }
                                    }
                                }
                                None => IoStream::plain(stream),
                            };

                            match protocol::negotiate_connection(
                                io_stream,
                                runtime_config_for_task.as_ref(),
                            )
                            .await
                            {
                                Ok(protocol::NegotiatedConnection::RawSocket(negotiated)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    Arc::clone(&accept_registry).register_rawsocket_connection(
                                        runtime_handle.clone(),
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        negotiated,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::WebSocket(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_websocket_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        handshake,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::Http2(handshake)) => {
                                    let (stream, metadata) = handshake.split();
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http2_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        metadata,
                                        addr,
                                    );
                                    let registry_for_connection = Arc::clone(&accept_registry);
                                    let endpoint_for_connection =
                                        Arc::clone(&runtime_config_for_task);
                                    let http_handle = runtime_handle.clone();
                                    http_handle.spawn(async move {
                                        serve_http2_connection(
                                            listener_id,
                                            connection_id,
                                            stream,
                                            endpoint_for_connection,
                                            registry_for_connection,
                                        )
                                        .await;
                                    });
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::Http3(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http3_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        handshake,
                                        None,
                                        addr,
                                    );
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Ok(protocol::NegotiatedConnection::Http(handshake)) => {
                                    let connection_id = accept_registry.next_connection_id();
                                    accept_registry.register_http_connection(
                                        listener_id,
                                        connection_id,
                                        Arc::clone(&runtime_config_for_task),
                                        addr,
                                    );
                                    let registry_for_connection = Arc::clone(&accept_registry);
                                    let endpoint_for_connection =
                                        Arc::clone(&runtime_config_for_task);
                                    let http_handle = runtime_handle.clone();
                                    http_handle.spawn(async move {
                                        serve_http_connection(
                                            listener_id,
                                            connection_id,
                                            handshake,
                                            endpoint_for_connection,
                                            registry_for_connection,
                                        )
                                        .await;
                                    });
                                    if tx.send(connection_id).await.is_err() {
                                        break;
                                    }
                                }
                                Err(protocol::NegotiationError::Timeout) => {
                                    eprintln!(
                                        "protocol negotiation timed out for connection from {}",
                                        addr
                                    );
                                }
                                Err(protocol::NegotiationError::Protocol(msg)) => {
                                    eprintln!(
                                        "protocol negotiation failed for connection from {}: {}",
                                        addr, msg
                                    );
                                }
                                Err(protocol::NegotiationError::Io(err)) => {
                                    eprintln!(
                                        "protocol negotiation IO error for connection from {}: {}",
                                        addr, err
                                    );
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }
            });

            let mut listener_tasks = vec![task];
            let mut http3_addr = None;
            let mut http3_endpoint = None;
            if runtime_config.supports_protocol(TransportProtocol::Http3) {
                let mut desired_addr = local_addr;
                if let Some(http_settings) = runtime_config.http_settings() {
                    if let Some(http3_settings) = &http_settings.http3 {
                        if let Some(port) = http3_settings.port {
                            desired_addr.set_port(port);
                        }
                    }
                }
                match start_http3_listener(
                    listener_id,
                    desired_addr,
                    Arc::clone(&config_state),
                    Arc::clone(&view.registry),
                    sender.clone(),
                    view.handle.clone(),
                ) {
                    Ok((endpoint, task, bound_addr)) => {
                        http3_addr = Some(bound_addr);
                        http3_endpoint = Some(endpoint);
                        listener_tasks.push(task);
                    }
                    Err(err) => {
                        eprintln!(
                            "failed to start http3 listener on {}: {}",
                            desired_addr, err
                        );
                    }
                }
            }

            let entry = ListenerEntry {
                addr: local_addr,
                receiver: Mutex::new(Some(receiver)),
                _sender: sender,
                tasks: listener_tasks,
                http3_addr,
                http3_endpoint,
                config_state,
            };
            view.registry.insert(listener_id, entry);

            Ok(listener_id)
        })
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the bound socket address for the given listener.
pub fn local_addr(listener_id: ListenerId) -> Result<SocketAddr, Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.local_addr(listener_id))
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the bound HTTP/3 port for the given listener, if available.
pub fn listener_http3_port(listener_id: ListenerId) -> Result<Option<u16>, Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.http3_addr(listener_id))
        .map(|addr| addr.map(|socket| socket.port()))
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Stops accepting new connections on the provided listener and releases any
/// listener-specific accept tasks. Existing connections remain active.
pub fn close_listener(listener_id: ListenerId) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.close_listener(listener_id))
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the channel that streams accepted connection identifiers.
pub fn accept_channel(listener_id: ListenerId) -> Result<mpsc::Receiver<ConnectionId>, Error> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| state.registry.take_receiver(listener_id))
        .map_err(|err| match err {
            Error::RuntimeNotStarted => err,
            other => other,
        })
}

/// Returns the runtime-ready endpoint configuration associated with a connection.
pub fn connection_runtime_config(
    connection_id: ConnectionId,
) -> Result<Arc<config::EndpointRuntimeConfig>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_config(connection_id))
}

/// Convenience helper exposing the RawSocket max message size exponent for a connection.
pub fn connection_rawsocket_max_exponent(connection_id: ConnectionId) -> Result<u32, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_exponent(connection_id))
}

/// Returns the negotiated transport protocol for a connection.
pub fn connection_protocol(connection_id: ConnectionId) -> Result<ConnectionProtocol, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_protocol(connection_id))
}

/// Returns the negotiated WebSocket subprotocol for a connection, if available.
pub fn connection_websocket_protocol(connection_id: ConnectionId) -> Result<Option<String>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.connection_websocket_protocol(connection_id))
}

/// Retrieves and consumes a pending WebSocket handshake for a connection.
pub fn connection_take_websocket_handshake(
    connection_id: ConnectionId,
) -> Result<protocol::WebSocketHandshake, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_websocket_handshake(connection_id))
}

pub fn connection_accept_websocket(
    connection_id: ConnectionId,
    handshake: protocol::WebSocketHandshake,
    serializer: rawsocket::Serializer,
    protocol: Option<&str>,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        Arc::clone(&state.registry).accept_websocket_connection(
            state.handle.clone(),
            connection_id,
            handshake,
            serializer,
            protocol,
        )
    })
}

pub fn connection_reject_websocket(
    connection_id: ConnectionId,
    handshake: protocol::WebSocketHandshake,
    status: StatusCode,
    reason: Option<&str>,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        state.registry.reject_websocket_connection(
            state.handle.clone(),
            connection_id,
            handshake,
            status,
            reason,
        )
    })
}

/// Retrieves and consumes a pending HTTP/2 handshake for a connection.
pub fn connection_take_http2_handshake(
    connection_id: ConnectionId,
) -> Result<protocol::Http2Handshake, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_http2_handshake(connection_id))
}

/// Retrieves and consumes a pending HTTP/3 handshake for a connection.
pub fn connection_take_http3_handshake(
    connection_id: ConnectionId,
) -> Result<protocol::Http3Handshake, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.take_http3_handshake(connection_id))
}

/// Registers a pending HTTP/3 handshake for testing and diagnostics.
pub fn register_http3_pending(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    handshake: protocol::Http3Handshake,
    peer_addr: SocketAddr,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let endpoint_config = state.registry.listener_config(listener_id)?;
        state.registry.register_http3_connection(
            listener_id,
            connection_id,
            endpoint_config,
            handshake,
            None,
            peer_addr,
        );
        Ok(())
    })
}

/// Provides a shared handle to the HTTP/3 connection for a given connection id.
pub fn connection_http3_connection(
    connection_id: ConnectionId,
) -> Result<Arc<QuinnConnection>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.http3_connection(connection_id))
}

/// Attempts to retrieve the next pending HTTP/3 bidirectional stream.
pub fn connection_http3_poll_stream(
    connection_id: ConnectionId,
) -> Result<Option<Http3BidiStream>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.poll_http3_stream(connection_id))
}

/// Attempts to retrieve the next pending HTTP request metadata.
pub fn connection_http_poll_request(
    connection_id: ConnectionId,
) -> Result<Option<(HttpRequestSummary, HttpResponseHandle)>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.poll_http_request(connection_id))
}

/// Attempts to retrieve the next pending HTTP/3 request metadata.
pub fn connection_http3_poll_request(
    connection_id: ConnectionId,
) -> Result<Option<(HttpRequestSummary, HttpResponseHandle)>, Error> {
    connection_http_poll_request(connection_id)
}

/// Attempts to retrieve connection lifecycle events for HTTP/2 and HTTP/3.
pub fn connection_poll_http_event() -> Option<HttpConnectionEvent> {
    let manager = RuntimeManager::global();
    manager
        .with_state(|state| Ok(state.registry.poll_http_connection_event()))
        .ok()
        .flatten()
}

#[cfg(feature = "ffi-test")]
pub fn register_http_request(
    connection_id: ConnectionId,
    request: HttpRequestSummary,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
        let handle = state.handle.clone();
        handle.spawn(async move {
            let _ = rx.await;
        });
        let queued = QueuedHttpRequest {
            summary: request,
            response: HttpResponseHandle::new(connection_id, tx),
        };
        state.registry.enqueue_http_request(connection_id, queued)
    })
}

#[cfg(feature = "ffi-test")]
pub fn push_http_connection_event(listener_id: ListenerId, event: HttpConnectionEvent) {
    let manager = RuntimeManager::global();
    let _ = manager.with_state(|state| {
        state.registry.push_connection_event(listener_id, event);
        Ok(())
    });
}

/// Attempts to retrieve the next parsed WAMP message for a connection.
pub fn poll_connection_message(
    connection_id: ConnectionId,
) -> Result<Option<wamp::ParsedMessage>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.poll_message(connection_id))
}

/// Waits for the next parsed WAMP message for a connection.
pub fn wait_connection_message(
    connection_id: ConnectionId,
    timeout: Option<Duration>,
) -> Result<Option<wamp::ParsedMessage>, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let frames = state.registry.message_frames(connection_id)?;
        let mut receiver = frames.lock().unwrap();
        let receive = receiver.recv();
        let message = match timeout {
            Some(deadline) => runtime_block_on(&state.handle, async move {
                match time::timeout(deadline, receive).await {
                    Ok(result) => result,
                    Err(_) => None,
                }
            }),
            None => runtime_block_on(&state.handle, receive),
        };
        Ok(message)
    })
}

/// Forces a connection to close and releases associated resources.
pub fn close_connection(connection_id: ConnectionId) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| state.registry.close_connection(connection_id))
}

/// Opens an outbound RawSocket client connection and registers it in the runtime.
pub fn connect_rawsocket(
    host: &str,
    port: u16,
    use_tls: bool,
    allow_insecure: bool,
    serializer: rawsocket::Serializer,
    desired_exponent: u32,
    heartbeat_interval: Option<Duration>,
    heartbeat_timeout: Option<Duration>,
) -> Result<ConnectionId, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let connection_id = state.registry.next_connection_id();
        let endpoint_config = Arc::new(build_client_endpoint_config(
            host,
            port,
            use_tls,
            TransportProtocol::Rawsocket,
            desired_exponent,
            heartbeat_interval,
            heartbeat_timeout,
        ));
        let (stream, peer_addr) = runtime_block_on(
            &state.handle,
            connect_io_stream(host, port, use_tls, allow_insecure, &[]),
        )?;
        let negotiated = runtime_block_on(
            &state.handle,
            rawsocket::connect(
                stream,
                serializer,
                endpoint_config.max_rawsocket_size_exponent,
                endpoint_config.handshake_timeout,
            ),
        )
        .map_err(handshake_error_to_io)?;
        Arc::clone(&state.registry).register_rawsocket_connection(
            state.handle.clone(),
            ListenerId(0),
            connection_id,
            endpoint_config,
            negotiated,
            peer_addr,
        );
        Ok(connection_id)
    })
}

/// Opens an outbound WebSocket client connection and registers it in the runtime.
pub fn connect_websocket(
    host: &str,
    port: u16,
    target: &str,
    use_tls: bool,
    allow_insecure: bool,
    serializer: rawsocket::Serializer,
    headers: &[(String, String)],
    heartbeat_interval: Option<Duration>,
    heartbeat_timeout: Option<Duration>,
) -> Result<ConnectionId, Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        let subprotocol = websocket_subprotocol(serializer)?;
        let connection_id = state.registry.next_connection_id();
        let endpoint_config = Arc::new(build_client_endpoint_config(
            host,
            port,
            use_tls,
            TransportProtocol::Websocket,
            config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
            heartbeat_interval,
            heartbeat_timeout,
        ));
        let alpn_protocols = if use_tls {
            vec![b"http/1.1".to_vec()]
        } else {
            Vec::new()
        };
        let (mut stream, peer_addr) = runtime_block_on(
            &state.handle,
            connect_io_stream(host, port, use_tls, allow_insecure, &alpn_protocols),
        )?;
        runtime_block_on(
            &state.handle,
            perform_websocket_client_handshake(
                &mut stream,
                host,
                port,
                use_tls,
                target,
                subprotocol,
                headers,
                endpoint_config.handshake_timeout,
            ),
        )?;
        let _ = stream.set_nodelay(true);
        let (reader, writer) = tokio::io::split(stream);
        Arc::clone(&state.registry).register_established_websocket_connection(
            state.handle.clone(),
            ListenerId(0),
            connection_id,
            endpoint_config,
            peer_addr,
            serializer,
            Some(subprotocol.to_string()),
            reader,
            writer,
            false,
            true,
        )?;
        Ok(connection_id)
    })
}

/// Enqueues a WAMP message to be sent to the connection.
pub fn send_wamp_message(connection_id: ConnectionId, payload: Bytes) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        state
            .registry
            .enqueue_frame(connection_id, OutboundFrame::message(payload))
    })
}

/// Sends an HTTP response to the client. Currently unsupported.
pub fn send_http_response(
    connection_id: ConnectionId,
    status: i32,
    headers: &[(String, String)],
    body: &[u8],
) -> Result<(), Error> {
    let _ = (status, headers, body);
    Err(Error::UnsupportedProtocol(
        connection_id,
        ConnectionProtocol::Http,
    ))
}

/// Enqueues a WAMP message composed of multiple payload segments.
pub fn send_wamp_segments(connection_id: ConnectionId, segments: Vec<Bytes>) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    manager.with_state(|state| {
        state
            .registry
            .enqueue_frame(connection_id, OutboundFrame::message_segments(segments))
    })
}

pub fn spawn_http_response(
    handshake: protocol::HttpHandshake,
    status: i32,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
) -> Result<(), Error> {
    let manager = RuntimeManager::global();
    let version = handshake.version();
    manager.with_state(|state| {
        let handle = state.handle.clone();
        handle.spawn(async move {
            let stream = handshake.into_stream();
            if let Err(err) =
                protocol::write_http_response(stream, version, status, headers, body).await
            {
                eprintln!("failed to send http response: {}", err);
            }
        });
        Ok(())
    })
}

#[derive(Clone, Copy)]
enum HttpTransportAuthFailure {
    BearerRequired,
    TlsRequired,
    MutualTlsRequired,
}

fn evaluate_http_transport_auth_string_headers(
    requirements: &config::HttpRouteTransportAuthRuntime,
    endpoint_config: &config::EndpointRuntimeConfig,
    headers: &[(String, String)],
) -> Option<HttpTransportAuthFailure> {
    if requirements.require_mtls
        && endpoint_config
            .client_auth
            .as_ref()
            .map(|client_auth| client_auth.mode == config::ClientAuthMode::Required)
            != Some(true)
    {
        return Some(HttpTransportAuthFailure::MutualTlsRequired);
    }
    if requirements.require_tls && endpoint_config.tls_mode == config::TlsMode::Disabled {
        return Some(HttpTransportAuthFailure::TlsRequired);
    }
    if requirements.require_bearer && !has_bearer_header_string(headers) {
        return Some(HttpTransportAuthFailure::BearerRequired);
    }
    None
}

fn evaluate_http_transport_auth_bytes_headers(
    requirements: &config::HttpRouteTransportAuthRuntime,
    endpoint_config: &config::EndpointRuntimeConfig,
    headers: &[(Arc<[u8]>, Arc<[u8]>)],
) -> Option<HttpTransportAuthFailure> {
    if requirements.require_mtls
        && endpoint_config
            .client_auth
            .as_ref()
            .map(|client_auth| client_auth.mode == config::ClientAuthMode::Required)
            != Some(true)
    {
        return Some(HttpTransportAuthFailure::MutualTlsRequired);
    }
    if requirements.require_tls && endpoint_config.tls_mode == config::TlsMode::Disabled {
        return Some(HttpTransportAuthFailure::TlsRequired);
    }
    if requirements.require_bearer && !has_bearer_header_bytes(headers) {
        return Some(HttpTransportAuthFailure::BearerRequired);
    }
    None
}

fn has_bearer_header_string(headers: &[(String, String)]) -> bool {
    headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("authorization")
            && value.len() > 7
            && value
                .get(..7)
                .map(|prefix| prefix.eq_ignore_ascii_case("bearer "))
                .unwrap_or(false)
            && !value[7..].trim().is_empty()
    })
}

fn has_bearer_header_bytes(headers: &[(Arc<[u8]>, Arc<[u8]>)]) -> bool {
    headers.iter().any(|(name, value)| {
        std::str::from_utf8(name.as_ref())
            .map(|header_name| header_name.eq_ignore_ascii_case("authorization"))
            .unwrap_or(false)
            && std::str::from_utf8(value.as_ref())
                .map(|header_value| {
                    header_value.len() > 7
                        && header_value
                            .get(..7)
                            .map(|prefix| prefix.eq_ignore_ascii_case("bearer "))
                            .unwrap_or(false)
                        && !header_value[7..].trim().is_empty()
                })
                .unwrap_or(false)
    })
}

#[cfg(test)]
mod stats_tests {
    use super::*;

    #[test]
    fn http_connection_stats_capture_idle_timeout() {
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http2);
        stats.record_request();
        stats.record_idle_timeout(Some("idle timeout".into()));
        let event = stats.finalize(ConnectionId(42), HttpConnectionCloseReason::Graceful, None);
        assert_eq!(event.connection_id, ConnectionId(42));
        assert_eq!(event.protocol, ConnectionProtocol::Http2);
        assert_eq!(event.request_count, 1);
        assert_eq!(event.idle_timeouts, 1);
        assert_eq!(event.reason, HttpConnectionCloseReason::IdleTimeout);
        assert_eq!(event.backpressure_events, 0);
        assert_eq!(event.max_backpressure_depth, 0);
        assert_eq!(event.goaway_events, 0);
        assert_eq!(event.detail.as_deref(), Some("idle timeout"));
    }

    #[test]
    fn http_connection_stats_capture_backpressure_and_goaway() {
        let stats = HttpConnectionStats::new(ConnectionProtocol::Http2);
        stats.record_request();
        stats.record_backpressure(3);
        stats.record_backpressure(7);
        stats.record_goaway(Some("remote goaway".into()));
        let event = stats.finalize(ConnectionId(7), HttpConnectionCloseReason::Graceful, None);
        assert_eq!(event.connection_id, ConnectionId(7));
        assert_eq!(event.protocol, ConnectionProtocol::Http2);
        assert_eq!(event.request_count, 1);
        assert_eq!(event.backpressure_events, 2);
        assert_eq!(event.max_backpressure_depth, 7);
        assert_eq!(event.goaway_events, 1);
        assert_eq!(event.reason, HttpConnectionCloseReason::GoAway);
        assert_eq!(event.detail.as_deref(), Some("remote goaway"));
    }
}

async fn serve_http_connection(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    handshake: protocol::HttpHandshake,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) {
    let (mut stream, request, body_phase, prefetched) = handshake.into_parts();
    if !prefetched.is_empty() {
        // Preserve parser-prefetched bytes on the underlying stream so the
        // body reader or the next pipelined request can drain them directly.
        stream.buffer_front(prefetched.as_ref());
    }
    let _ = stream.set_nodelay(true);
    let (read_half, mut write_half) = tokio::io::split(stream);
    let mut reader = Some(BufReader::new(read_half));
    let mut pending = Some((request, body_phase));
    let mut pending_reclaim: Option<Http1BodyReclaim> = None;
    let read_timeout = endpoint_config
        .idle_timeout
        .unwrap_or(endpoint_config.handshake_timeout);

    loop {
        let (request, body_phase) = match pending.take() {
            Some(value) => value,
            None => {
                if reader.is_none() {
                    if let Some(reclaim) = pending_reclaim.take() {
                        match reclaim.wait().await {
                            Ok(read_half) => {
                                reader = Some(BufReader::new(read_half));
                            }
                            Err(_) => break,
                        }
                    } else {
                        break;
                    }
                }
                match protocol::read_http_request(reader.as_mut().unwrap(), &endpoint_config).await
                {
                    Ok(Some(value)) => value,
                    Ok(None) => break,
                    Err(err) => {
                        eprintln!(
                            "http/1 connection read error for listener {:?}: {:?}",
                            listener_id, err
                        );
                        break;
                    }
                }
            }
        };

        let (body_handle, new_reclaim) = match body_phase {
            HttpBodyPhase::Buffered(bytes) => (HttpBodyHandle::from_inline(bytes), None),
            HttpBodyPhase::Finished => (HttpBodyHandle::empty(), None),
            HttpBodyPhase::NeedsStreaming {
                prefix,
                remaining_len,
            } => {
                let reader_half = match reader.take() {
                    Some(buf) => buf.into_inner(),
                    None => {
                        eprintln!(
                            "http/1 streaming requested without active reader for listener {:?}",
                            listener_id
                        );
                        break;
                    }
                };
                let (state, reclaim) =
                    spawn_http1_streaming_body(prefix, reader_half, remaining_len, read_timeout);
                (HttpBodyHandle::streaming(state), Some(reclaim))
            }
        };
        if let Some(reclaim) = new_reclaim {
            pending_reclaim = Some(reclaim);
        }

        let protocol::HttpRequest {
            method,
            target,
            version,
            headers,
        } = request;
        let normalized_method = method.to_uppercase();
        let (path, query) = protocol::split_http_target(&target);
        let normalized_path = if path.is_empty() { "/" } else { path };
        let normalized_path_string = normalized_path.to_string();
        let query_owned = query.map(|value| value.to_string());
        let keep_alive = should_keep_alive(version, &headers);
        let protocol_label = format!("http/1.{}", version);

        match endpoint_config.match_http_route(
            &normalized_path_string,
            query,
            &normalized_method,
            &protocol_label,
        ) {
            HttpRouteMatch::Resolved(resolution) => {
                if let Some(failure) = evaluate_http_transport_auth_string_headers(
                    &resolution.transport_auth,
                    &endpoint_config,
                    &headers,
                ) {
                    let response = match failure {
                        HttpTransportAuthFailure::BearerRequired => {
                            send_http_simple_response(
                                &mut write_half,
                                version,
                                StatusCode::UNAUTHORIZED,
                                keep_alive,
                                b"bearer token required",
                                &[("WWW-Authenticate", "Bearer")],
                            )
                            .await
                        }
                        HttpTransportAuthFailure::TlsRequired => {
                            send_http_simple_response(
                                &mut write_half,
                                version,
                                StatusCode::FORBIDDEN,
                                keep_alive,
                                b"tls required",
                                &[],
                            )
                            .await
                        }
                        HttpTransportAuthFailure::MutualTlsRequired => {
                            send_http_simple_response(
                                &mut write_half,
                                version,
                                StatusCode::FORBIDDEN,
                                keep_alive,
                                b"mutual tls required",
                                &[],
                            )
                            .await
                        }
                    };
                    if let Err(err) = response {
                        eprintln!(
                            "failed to send transport-auth rejection for listener {:?}: {}",
                            listener_id, err
                        );
                        break;
                    }
                    continue;
                }
                let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
                let summary_headers = headers
                    .iter()
                    .map(|(name, value)| {
                        (
                            http_bytes_from_slice(name.as_bytes()),
                            http_bytes_from_slice(value.as_bytes()),
                        )
                    })
                    .collect();
                let summary = HttpRequestSummary::new(
                    method,
                    target,
                    normalized_path_string.clone(),
                    query_owned,
                    protocol_label.clone(),
                    version,
                    summary_headers,
                    body_handle,
                    Some(resolution.realm.clone()),
                    Some(resolution.procedure.clone()),
                    Some(resolution),
                );
                let queued = QueuedHttpRequest {
                    summary,
                    response: HttpResponseHandle::new(connection_id, tx),
                };
                if let Err(err) = registry.enqueue_http_request(connection_id, queued) {
                    eprintln!(
                        "failed to enqueue http request for listener {:?}: {}",
                        listener_id, err
                    );
                    break;
                }
                match rx.await {
                    Ok(mut dispatch) => {
                        if let Err(err) =
                            send_http_dispatch(&mut write_half, version, keep_alive, &mut dispatch)
                                .await
                        {
                            eprintln!(
                                "failed to send http response for listener {:?}: {}",
                                listener_id, err
                            );
                            break;
                        }
                    }
                    Err(_) => {
                        let _ = send_http_simple_response(
                            &mut write_half,
                            version,
                            StatusCode::INTERNAL_SERVER_ERROR,
                            keep_alive,
                            b"http request cancelled",
                            &[],
                        )
                        .await;
                        break;
                    }
                }
            }
            HttpRouteMatch::MethodNotAllowed { allowed_methods } => {
                let allow_value = allowed_methods.join(", ");
                if let Err(err) = send_http_simple_response(
                    &mut write_half,
                    version,
                    StatusCode::METHOD_NOT_ALLOWED,
                    keep_alive,
                    b"method not allowed",
                    &[("Allow", allow_value.as_str())],
                )
                .await
                {
                    eprintln!(
                        "failed to send 405 response for listener {:?}: {}",
                        listener_id, err
                    );
                    break;
                }
            }
            HttpRouteMatch::NotFound => {
                if let Err(err) = send_http_simple_response(
                    &mut write_half,
                    version,
                    StatusCode::NOT_FOUND,
                    keep_alive,
                    b"route not found",
                    &[],
                )
                .await
                {
                    eprintln!(
                        "failed to send 404 response for listener {:?}: {}",
                        listener_id, err
                    );
                    break;
                }
            }
        }

        if reader.is_none() {
            if let Some(reclaim) = pending_reclaim.take() {
                match reclaim.wait().await {
                    Ok(read_half) => {
                        reader = Some(BufReader::new(read_half));
                    }
                    Err(_) => break,
                }
            } else {
                break;
            }
        }

        if !keep_alive {
            break;
        }
    }
}

async fn send_http_dispatch(
    writer: &mut IoWriteHalf,
    version: u8,
    keep_alive: bool,
    dispatch: &mut HttpResponseDispatch,
) -> Result<(), String> {
    ensure_connection_header(&mut dispatch.headers, keep_alive, version);
    match &mut dispatch.body {
        HttpResponseBody::Buffered(body) => protocol::write_http_response_shared(
            writer,
            version,
            dispatch.status,
            &dispatch.headers,
            body,
        )
        .await
        .map_err(|err| err.to_string()),
        HttpResponseBody::Streaming(reader) => {
            strip_content_length(&mut dispatch.headers);
            ensure_chunked_transfer_encoding(&mut dispatch.headers);
            write_http1_chunked_response(
                writer,
                version,
                dispatch.status,
                &dispatch.headers,
                reader,
            )
            .await
        }
    }
}

async fn send_http_simple_response(
    writer: &mut IoWriteHalf,
    version: u8,
    status: StatusCode,
    keep_alive: bool,
    body: &[u8],
    extra_headers: &[(&str, &str)],
) -> Result<(), String> {
    let mut headers: Vec<(String, String)> = extra_headers
        .iter()
        .map(|(name, value)| (name.to_string(), value.to_string()))
        .collect();
    ensure_connection_header(&mut headers, keep_alive, version);
    protocol::write_http_response_shared(writer, version, status.as_u16() as i32, &headers, body)
        .await
        .map_err(|err| err.to_string())
}

fn ensure_connection_header(headers: &mut Vec<(String, String)>, keep_alive: bool, version: u8) {
    if headers
        .iter()
        .any(|(name, _)| name.eq_ignore_ascii_case("connection"))
    {
        return;
    }
    if keep_alive && version >= 1 {
        headers.push(("Connection".into(), "keep-alive".into()));
    } else {
        headers.push(("Connection".into(), "close".into()));
    }
}

fn ensure_chunked_transfer_encoding(headers: &mut Vec<(String, String)>) {
    headers.retain(|(name, _)| !name.eq_ignore_ascii_case("transfer-encoding"));
    headers.push(("Transfer-Encoding".into(), "chunked".into()));
}

fn strip_content_length(headers: &mut Vec<(String, String)>) {
    headers.retain(|(name, _)| !name.eq_ignore_ascii_case("content-length"));
}

async fn write_http1_chunked_response(
    writer: &mut IoWriteHalf,
    version: u8,
    status: i32,
    headers: &[(String, String)],
    reader: &mut ResponseStreamReader,
) -> Result<(), String> {
    let clamped = status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let reason = status_code.canonical_reason().unwrap_or("");
    let mut response = Vec::with_capacity(128 + headers.len() * 32);
    write!(
        &mut response,
        "HTTP/1.{} {} {}\r\n",
        version,
        status_code.as_u16(),
        reason
    )
    .map_err(|err| err.to_string())?;
    for (name, value) in headers {
        write!(&mut response, "{}: {}\r\n", name, value).map_err(|err| err.to_string())?;
    }
    response.extend_from_slice(b"\r\n");
    if let Err(err) = writer.write_all(&response).await {
        reader.close();
        return Err(err.to_string());
    }

    loop {
        match reader.next().await {
            Ok(ResponseStreamFrame::Chunk { bytes, .. }) => {
                if bytes.is_empty() {
                    continue;
                }
                let header = format!("{:X}\r\n", bytes.len());
                if let Err(err) = writer.write_all(header.as_bytes()).await {
                    reader.close();
                    return Err(err.to_string());
                }
                if let Err(err) = writer.write_all(&bytes).await {
                    reader.close();
                    return Err(err.to_string());
                }
                if let Err(err) = writer.write_all(b"\r\n").await {
                    reader.close();
                    return Err(err.to_string());
                }
            }
            Ok(ResponseStreamFrame::Finished { .. }) => {
                if let Err(err) = writer.write_all(b"0\r\n\r\n").await {
                    reader.close();
                    return Err(err.to_string());
                }
                return Ok(());
            }
            Err(err) => {
                reader.close();
                return Err(format!("http/1.x streaming response failed: {}", err));
            }
        }
    }
}

fn runtime_block_on<F>(handle: &tokio::runtime::Handle, future: F) -> F::Output
where
    F: std::future::Future,
{
    if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(|| handle.block_on(future))
    } else {
        handle.block_on(future)
    }
}

fn build_client_endpoint_config(
    host: &str,
    port: u16,
    use_tls: bool,
    protocol: TransportProtocol,
    max_rawsocket_size_exponent: u32,
    heartbeat_interval: Option<Duration>,
    heartbeat_timeout: Option<Duration>,
) -> config::EndpointRuntimeConfig {
    let exponent = max_rawsocket_size_exponent.clamp(
        config::MIN_RAWSOCKET_SIZE_EXPONENT,
        config::CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT,
    );
    config::EndpointRuntimeConfig {
        host: host.to_string(),
        port,
        tls_mode: if use_tls {
            config::TlsMode::Native
        } else {
            config::TlsMode::Disabled
        },
        client_auth: None,
        protocols: vec![protocol],
        idle_timeout: None,
        heartbeat_interval,
        heartbeat_timeout: heartbeat_timeout
            .or_else(|| heartbeat_interval.and_then(|interval| interval.checked_mul(2))),
        handshake_timeout: config::DEFAULT_HANDSHAKE_TIMEOUT,
        max_http_content_length: None,
        max_rawsocket_size_exponent: exponent,
        max_rawsocket_size: 1u64 << exponent,
        max_upgrade_exponent: (exponent > 24).then_some(exponent),
        outbound_send_queue_capacity: config::DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY,
        websocket_path: None,
        sni_certificates: Vec::new(),
        http_routes: Vec::new(),
        http: None,
    }
}

fn handshake_error_to_io(err: rawsocket::HandshakeError) -> Error {
    match err {
        rawsocket::HandshakeError::Protocol(reason) => {
            Error::Io(io::Error::new(io::ErrorKind::InvalidData, reason))
        }
        rawsocket::HandshakeError::Io(err) => Error::Io(err),
    }
}

async fn connect_io_stream(
    host: &str,
    port: u16,
    use_tls: bool,
    allow_insecure: bool,
    alpn_protocols: &[Vec<u8>],
) -> Result<(IoStream, SocketAddr), Error> {
    let stream = tokio::net::TcpStream::connect((host, port)).await?;
    let peer_addr = stream.peer_addr()?;
    let io_stream = if use_tls {
        let connector = tls::build_client_connector(allow_insecure, alpn_protocols)?;
        let server_name = server_name_from_host(host)?;
        let tls_stream = connector
            .connect(server_name, stream)
            .await
            .map_err(|err| io::Error::new(io::ErrorKind::ConnectionAborted, err.to_string()))?;
        IoStream::tls_client(tls_stream)
    } else {
        IoStream::plain(stream)
    };
    let _ = io_stream.set_nodelay(true);
    Ok((io_stream, peer_addr))
}

fn server_name_from_host(host: &str) -> Result<ServerName<'static>, Error> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(ServerName::IpAddress(ip.into()));
    }
    ServerName::try_from(host.to_string()).map_err(|err| {
        Error::Io(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("invalid tls server name {host}: {err}"),
        ))
    })
}

fn websocket_subprotocol(serializer: rawsocket::Serializer) -> Result<&'static str, Error> {
    match serializer {
        rawsocket::Serializer::Json => Ok("wamp.2.json"),
        rawsocket::Serializer::MessagePack => Ok("wamp.2.msgpack"),
        rawsocket::Serializer::Cbor => Ok("wamp.2.cbor"),
        _ => Err(Error::Io(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("websocket serializer {serializer:?} is unsupported"),
        ))),
    }
}

fn websocket_host_header(host: &str, port: u16, use_tls: bool) -> String {
    let default_port = if use_tls { 443 } else { 80 };
    let base = if host.contains(':') && !host.starts_with('[') {
        format!("[{host}]")
    } else {
        host.to_string()
    };
    if port == default_port {
        base
    } else {
        format!("{base}:{port}")
    }
}

async fn perform_websocket_client_handshake(
    stream: &mut IoStream,
    host: &str,
    port: u16,
    use_tls: bool,
    target: &str,
    subprotocol: &str,
    headers: &[(String, String)],
    timeout: Duration,
) -> Result<(), Error> {
    let mut nonce_bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Base64Engine.encode(nonce_bytes);
    let mut request = format!(
        "GET {} HTTP/1.1\r\nHost: {}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {}\r\nSec-WebSocket-Protocol: {}\r\n",
        if target.is_empty() { "/" } else { target },
        websocket_host_header(host, port, use_tls),
        nonce,
        subprotocol,
    );
    for (name, value) in headers {
        if name.eq_ignore_ascii_case("host")
            || name.eq_ignore_ascii_case("upgrade")
            || name.eq_ignore_ascii_case("connection")
            || name.eq_ignore_ascii_case("sec-websocket-version")
            || name.eq_ignore_ascii_case("sec-websocket-key")
            || name.eq_ignore_ascii_case("sec-websocket-protocol")
        {
            continue;
        }
        request.push_str(name);
        request.push_str(": ");
        request.push_str(value);
        request.push_str("\r\n");
    }
    request.push_str("\r\n");
    time::timeout(timeout, async {
        stream.write_all(request.as_bytes()).await?;
        stream.flush().await
    })
    .await
    .map_err(|_| {
        Error::Io(io::Error::new(
            io::ErrorKind::TimedOut,
            "websocket client handshake timed out",
        ))
    })??;

    let header_block = read_http_header_block(stream, timeout).await?;
    let header_text = std::str::from_utf8(&header_block).map_err(|err| {
        Error::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("websocket handshake response is not valid utf-8: {err}"),
        ))
    })?;
    let mut lines = header_text.split("\r\n");
    let status_line = lines.next().ok_or_else(|| {
        Error::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            "websocket handshake response missing status line",
        ))
    })?;
    if !status_line.starts_with("HTTP/1.1 101") && !status_line.starts_with("HTTP/1.0 101") {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::ConnectionRefused,
            format!("websocket upgrade failed: {status_line}"),
        )));
    }

    let mut response_headers = Vec::<(String, String)>::new();
    for line in lines {
        if line.is_empty() {
            break;
        }
        let Some((name, value)) = line.split_once(':') else {
            return Err(Error::Io(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("invalid websocket handshake header: {line}"),
            )));
        };
        response_headers.push((name.trim().to_string(), value.trim().to_string()));
    }

    let upgrade = response_headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("upgrade"))
        .map(|(_, value)| value.as_str())
        .unwrap_or_default();
    if !upgrade.eq_ignore_ascii_case("websocket") {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            "websocket handshake missing Upgrade: websocket",
        )));
    }
    let connection = response_headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("connection"))
        .map(|(_, value)| value.as_str())
        .unwrap_or_default();
    if !header_has_token(connection, "upgrade") {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            "websocket handshake missing Connection: Upgrade",
        )));
    }
    let accept = response_headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("sec-websocket-accept"))
        .map(|(_, value)| value.as_str())
        .ok_or_else(|| {
            Error::Io(io::Error::new(
                io::ErrorKind::InvalidData,
                "websocket handshake missing Sec-WebSocket-Accept",
            ))
        })?;
    if accept != websocket_accept_value(&nonce) {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            "websocket handshake accept value mismatch",
        )));
    }
    let negotiated_protocol = response_headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("sec-websocket-protocol"))
        .map(|(_, value)| value.as_str());
    if negotiated_protocol != Some(subprotocol) {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "websocket handshake negotiated unexpected protocol {:?}",
                negotiated_protocol
            ),
        )));
    }
    Ok(())
}

async fn read_http_header_block(
    stream: &mut IoStream,
    timeout: Duration,
) -> Result<Vec<u8>, Error> {
    const HEADER_LIMIT: usize = 64 * 1024;
    let mut buffer = Vec::with_capacity(1024);
    loop {
        if let Some(end) = buffer.windows(4).position(|window| window == b"\r\n\r\n") {
            let header_end = end + 4;
            if buffer.len() > header_end {
                stream.buffer_front(&buffer[header_end..]);
            }
            buffer.truncate(header_end);
            return Ok(buffer);
        }
        if buffer.len() >= HEADER_LIMIT {
            return Err(Error::Io(io::Error::new(
                io::ErrorKind::InvalidData,
                "http header block exceeded limit",
            )));
        }
        let mut chunk = [0u8; 1024];
        let read = time::timeout(timeout, stream.read(&mut chunk))
            .await
            .map_err(|_| {
                Error::Io(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "http header read timed out",
                ))
            })??;
        if read == 0 {
            return Err(Error::Io(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "connection closed before http headers completed",
            )));
        }
        buffer.extend_from_slice(&chunk[..read]);
    }
}

fn websocket_accept_value(key: &str) -> String {
    let mut sha1 = Sha1::new();
    sha1.update(key.as_bytes());
    sha1.update(WEBSOCKET_GUID.as_bytes());
    Base64Engine.encode(sha1.finalize())
}

async fn write_websocket_handshake_response<W>(
    stream: &mut W,
    accept_value: &str,
    protocol: Option<&str>,
) -> io::Result<()>
where
    W: AsyncWrite + Unpin,
{
    let mut response = format!(
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {}\r\n",
        accept_value
    );
    if let Some(protocol) = protocol {
        response.push_str(&format!("Sec-WebSocket-Protocol: {}\r\n", protocol));
    }
    response.push_str("\r\n");
    stream.write_all(response.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

fn should_keep_alive(version: u8, headers: &[(String, String)]) -> bool {
    let directive = headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("connection"))
        .map(|(_, value)| value.as_str());
    match version {
        0 => directive
            .map(|value| header_has_token(value, "keep-alive"))
            .unwrap_or(false),
        _ => directive
            .map(|value| !header_has_token(value, "close"))
            .unwrap_or(true),
    }
}

fn is_benign_socket_shutdown(kind: io::ErrorKind) -> bool {
    matches!(
        kind,
        io::ErrorKind::UnexpectedEof
            | io::ErrorKind::BrokenPipe
            | io::ErrorKind::ConnectionReset
            | io::ErrorKind::ConnectionAborted
    )
}

fn header_has_token(value: &str, needle: &str) -> bool {
    value
        .split(',')
        .map(|token| token.trim())
        .any(|token| token.eq_ignore_ascii_case(needle))
}

async fn serve_http3_requests(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
    connection: Arc<QuinnConnection>,
    streams: Arc<Http3StreamChannels>,
) {
    let mut h3_conn = match h3::server::builder()
        .build(H3QuinnConnection::new(connection.deref().clone()))
        .await
    {
        Ok(conn) => conn,
        Err(err) => {
            eprintln!(
                "http3 handshake failed for listener {:?}: {}",
                listener_id, err
            );
            registry.finish_http_connection(
                connection_id,
                HttpConnectionCloseReason::ProtocolError,
                Some(err.to_string()),
            );
            return;
        }
    };

    let connection_stats = registry
        .connection_stats(connection_id)
        .ok()
        .and_then(|stats| stats);
    let mut closed = false;

    loop {
        match h3_conn.accept().await {
            Ok(Some(resolver)) => match resolver.resolve_request().await {
                Ok((request, stream)) => {
                    #[cfg(feature = "ffi-test")]
                    eprintln!(
                        "http3 request accepted on connection {:?}: {} {}",
                        connection_id,
                        request.method(),
                        request.uri()
                    );
                    if let Err(err) = process_http3_request(
                        connection_id,
                        Arc::clone(&connection),
                        request,
                        stream,
                        Arc::clone(&endpoint_config),
                        Arc::clone(&registry),
                    )
                    .await
                    {
                        eprintln!(
                            "http3 request error for listener {:?}: {}",
                            listener_id, err
                        );
                    }
                }
                Err(err) => {
                    eprintln!(
                        "http3 request resolve error for listener {:?}: {}",
                        listener_id, err
                    );
                }
            },
            Ok(None) => break,
            Err(err) => {
                let h3_no_error = err.is_h3_no_error();
                let err_description = err.to_string();
                let mut graceful_close = h3_no_error;
                if !graceful_close {
                    if let Some(code_segment) = err_description.rsplit(':').next() {
                        if code_segment.trim().eq_ignore_ascii_case("0x0") {
                            graceful_close = true;
                        }
                    }
                }
                let error_message = if graceful_close {
                    None
                } else {
                    Some(err_description)
                };
                if !graceful_close {
                    if let Some(message) = error_message.as_ref() {
                        eprintln!(
                            "http3 accept loop stopped for listener {:?}: {}",
                            listener_id, message
                        );
                    }
                }
                let reason = if graceful_close {
                    HttpConnectionCloseReason::Graceful
                } else {
                    HttpConnectionCloseReason::ProtocolError
                };
                if let Some(stats) = connection_stats.as_ref() {
                    stats.set_close_reason(reason, error_message.clone());
                }
                registry.finish_http_connection(connection_id, reason, error_message);
                closed = true;
                break;
            }
        }
    }

    drop(streams);
    if !closed {
        registry.finish_http_connection(connection_id, HttpConnectionCloseReason::Graceful, None);
    }
}

async fn serve_http2_connection(
    listener_id: ListenerId,
    connection_id: ConnectionId,
    stream: IoStream,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) {
    let builder = http2_server_builder();
    let write_tracker = Arc::new(Http2ConnectionWriteTracker::default());
    let mut connection = match builder
        .handshake(InstrumentedHttp2IoStream {
            inner: stream,
            write_tracker: Arc::clone(&write_tracker),
        })
        .await
    {
        Ok(connection) => connection,
        Err(err) => {
            eprintln!(
                "http/2 handshake failed for listener {:?}: {}",
                listener_id, err
            );
            registry.finish_http_connection(
                connection_id,
                HttpConnectionCloseReason::ProtocolError,
                Some(err.to_string()),
            );
            return;
        }
    };

    let connection_stats = registry
        .connection_stats(connection_id)
        .ok()
        .and_then(|stats| stats);
    let mut closed = false;

    while let Some(result) = connection.accept().await {
        match result {
            Ok((request, respond)) => {
                if let Err(err) = handle_http2_request(
                    connection_id,
                    request,
                    respond,
                    Arc::clone(&endpoint_config),
                    Arc::clone(&registry),
                    Arc::clone(&write_tracker),
                )
                .await
                {
                    eprintln!(
                        "http/2 request error for listener {:?}: {}",
                        listener_id, err
                    );
                }
            }
            Err(err) => {
                eprintln!(
                    "http/2 accept error for listener {:?}: {}",
                    listener_id, err
                );
                if let Some(stats) = connection_stats.as_ref() {
                    if err.is_go_away() {
                        stats.record_goaway(Some(err.to_string()));
                    } else {
                        stats.set_close_reason(
                            HttpConnectionCloseReason::ProtocolError,
                            Some(err.to_string()),
                        );
                    }
                }
                registry.finish_http_connection(
                    connection_id,
                    if err.is_go_away() {
                        HttpConnectionCloseReason::GoAway
                    } else {
                        HttpConnectionCloseReason::ProtocolError
                    },
                    Some(err.to_string()),
                );
                closed = true;
                break;
            }
        }
    }

    if !closed {
        registry.finish_http_connection(connection_id, HttpConnectionCloseReason::Graceful, None);
    }
}

async fn handle_http2_request(
    connection_id: ConnectionId,
    request: Http2Request<H2RecvStream>,
    respond: H2SendResponse<Bytes>,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
    write_tracker: Arc<Http2ConnectionWriteTracker>,
) -> Result<(), String> {
    let (parts, body_stream) = request.into_parts();
    let method = parts.method.as_str().to_string();
    let normalized_method = method.to_uppercase();
    let target = parts
        .uri
        .path_and_query()
        .map(|pq| pq.as_str().to_string())
        .unwrap_or_else(|| parts.uri.path().to_string());
    let (path, query) = split_target_components(&target);
    let headers = flatten_http2_headers(&parts.headers);
    let content_length = parse_content_length(&headers);
    let max_body = endpoint_config
        .max_http_content_length
        .unwrap_or(HTTP3_DEFAULT_BODY_LIMIT);

    let stats = registry
        .connection_stats(connection_id)
        .map_err(|err| err.to_string())?;
    if let Some(ref stats_arc) = stats {
        stats_arc.record_request();
    }
    let state = StreamingBodyState::new(content_length.map(|len| len as usize).unwrap_or(0));
    let (idle_timeout, total_timeout) = http_stream_timeouts(&endpoint_config);
    // Apply a generous floor for endpoints that use the default idle timeout so multi-MB tests
    // don't flake; explicit config keeps full control over the timeout values.
    let (idle_timeout, total_timeout) = if endpoint_config.idle_timeout.is_none() {
        (
            idle_timeout.max(Duration::from_secs(30)),
            total_timeout.max(Duration::from_secs(60)),
        )
    } else {
        (idle_timeout, total_timeout)
    };
    spawn_http2_stream_reader(
        stats.clone(),
        Arc::clone(&state),
        body_stream,
        max_body,
        content_length,
        idle_timeout,
        total_timeout,
    );
    let body_handle = HttpBodyHandle::streaming(state);
    let query_owned = query.clone();

    match endpoint_config.match_http_route(&path, query.as_deref(), &normalized_method, "http2") {
        HttpRouteMatch::Resolved(resolution) => {
            if let Some(failure) = evaluate_http_transport_auth_bytes_headers(
                &resolution.transport_auth,
                &endpoint_config,
                &headers,
            ) {
                return match failure {
                    HttpTransportAuthFailure::BearerRequired => {
                        send_http2_plain_response(
                            respond,
                            StatusCode::UNAUTHORIZED,
                            b"bearer token required",
                            &[("www-authenticate", "Bearer")],
                        )
                        .await
                    }
                    HttpTransportAuthFailure::TlsRequired => {
                        send_http2_plain_response(
                            respond,
                            StatusCode::FORBIDDEN,
                            b"tls required",
                            &[],
                        )
                        .await
                    }
                    HttpTransportAuthFailure::MutualTlsRequired => {
                        send_http2_plain_response(
                            respond,
                            StatusCode::FORBIDDEN,
                            b"mutual tls required",
                            &[],
                        )
                        .await
                    }
                };
            }
            let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
            let summary = HttpRequestSummary::new(
                normalized_method,
                target,
                path,
                query_owned,
                "http/2".to_string(),
                2,
                headers,
                body_handle,
                Some(resolution.realm.clone()),
                Some(resolution.procedure.clone()),
                Some(resolution),
            );
            let queued = QueuedHttpRequest {
                summary,
                response: HttpResponseHandle::new(connection_id, tx),
            };
            registry
                .enqueue_http_request(connection_id, queued)
                .map_err(|err| err.to_string())?;
            tokio::spawn(async move {
                match rx.await {
                    Ok(dispatch) => {
                        if let Err(err) = send_http2_response_from_dispatch(
                            respond,
                            dispatch,
                            write_tracker,
                        )
                        .await
                        {
                            eprintln!(
                                "failed to send http/2 response for connection {:?}: {}",
                                connection_id, err
                            );
                        }
                    }
                    Err(_) => {
                        let _ = send_http2_plain_response(
                            respond,
                            StatusCode::INTERNAL_SERVER_ERROR,
                            b"http/2 request cancelled",
                            &[],
                        )
                        .await;
                    }
                }
            });
            Ok(())
        }
        HttpRouteMatch::MethodNotAllowed { allowed_methods } => {
            let allow_value = allowed_methods.join(", ");
            send_http2_plain_response(
                respond,
                StatusCode::METHOD_NOT_ALLOWED,
                b"method not allowed",
                &[("allow", allow_value.as_str())],
            )
            .await
        }
        HttpRouteMatch::NotFound => {
            send_http2_plain_response(respond, StatusCode::NOT_FOUND, b"route not found", &[]).await
        }
    }
}

fn spawn_http2_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    stream: H2RecvStream,
    max_body: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) {
    tokio::spawn(async move {
        if let Err(err) = run_http2_stream_reader(
            stats,
            state,
            stream,
            max_body,
            content_length,
            idle_timeout,
            total_timeout,
        )
        .await
        {
            eprintln!("http/2 body reader error: {}", err);
        }
    });
}

async fn run_http2_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    mut stream: H2RecvStream,
    max_body: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) -> Result<(), String> {
    let mut bytes_read: u64 = 0;
    let total_deadline = Instant::now() + total_timeout;
    loop {
        if state.finish_requested() {
            state.mark_finished();
            return Ok(());
        }

        if Instant::now() >= total_deadline {
            if let Some(stats_ref) = stats.as_ref() {
                stats_ref.record_body_timeout(Some("http/2 body total timeout".into()));
                stats_ref.record_goaway(Some("http/2 body total timeout".into()));
            }
            state.mark_error("http/2 body total timeout exceeded".into());
            return Err("http/2 body total timeout".into());
        }

        let data_future = stream.data();
        let chunk = match time::timeout(idle_timeout, data_future).await {
            Ok(value) => value,
            Err(_) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.record_idle_timeout(Some("http/2 body idle timeout".into()));
                    stats_ref.record_goaway(Some("http/2 body idle timeout".into()));
                }
                let message = format!("http/2 body idle timeout after {} bytes", bytes_read);
                state.mark_error(message.clone());
                return Err(message);
            }
        };

        match chunk {
            Some(Ok(bytes)) => {
                let len = bytes.len();
                bytes_read += len as u64;
                if bytes_read > max_body
                    || content_length
                        .map(|limit| bytes_read > limit)
                        .unwrap_or(false)
                {
                    state.mark_error("http/2 body exceeded configured limit".into());
                    return Ok(());
                }
                if content_length.is_none() {
                    state.extend_total_len(len);
                }
                if !state.finish_requested() {
                    state.enqueue_bytes(bytes);
                }
                if let Err(err) = stream.flow_control().release_capacity(len) {
                    state.mark_error(format!("http/2 flow control error: {}", err));
                    return Err(err.to_string());
                }
            }
            Some(Err(err)) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.set_close_reason(
                        HttpConnectionCloseReason::ProtocolError,
                        Some(format!("http/2 body read failed: {}", err)),
                    );
                }
                state.mark_error(format!("http/2 body read failed: {}", err));
                return Err(err.to_string());
            }
            None => {
                if let Some(expected) = content_length {
                    if bytes_read != expected {
                        state.mark_error("http/2 body ended before declared Content-Length".into());
                        return Ok(());
                    }
                }
                state.mark_finished();
                return Ok(());
            }
        }
    }
}

async fn send_http2_plain_response(
    mut respond: H2SendResponse<Bytes>,
    status: StatusCode,
    body: &[u8],
    extra_headers: &[(&str, &str)],
) -> Result<(), String> {
    let http2_status = Http2StatusCode::from_u16(status.as_u16())
        .unwrap_or(Http2StatusCode::INTERNAL_SERVER_ERROR);
    let mut builder = Http2Response::builder().status(http2_status);
    {
        let header_map = builder.headers_mut().expect("headers available");
        if let Ok(value) = Http2HeaderValue::from_str(&body.len().to_string()) {
            header_map.insert(Http2HeaderName::from_static("content-length"), value);
        }
        for (name, value) in extra_headers {
            if let (Ok(name), Ok(val)) = (
                Http2HeaderName::from_bytes(name.as_bytes()),
                Http2HeaderValue::from_str(value),
            ) {
                header_map.insert(name, val);
            }
        }
    }
    let response = builder.body(()).map_err(|err| err.to_string())?;
    let end_of_stream = body.is_empty();
    let mut send_stream = respond
        .send_response(response, end_of_stream)
        .map_err(|err| err.to_string())?;
    if !body.is_empty() {
        send_stream
            .send_data(Bytes::copy_from_slice(body), true)
            .map_err(|err| err.to_string())?;
    }
    Ok(())
}

async fn send_http2_response_from_dispatch(
    mut respond: H2SendResponse<Bytes>,
    dispatch: HttpResponseDispatch,
    write_tracker: Arc<Http2ConnectionWriteTracker>,
) -> Result<(), String> {
    let HttpResponseDispatch {
        status,
        mut headers,
        body,
    } = dispatch;
    let clamped = status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let http2_status = Http2StatusCode::from_u16(status_code.as_u16())
        .unwrap_or(Http2StatusCode::INTERNAL_SERVER_ERROR);
    let mut builder = Http2Response::builder().status(http2_status);
    match body {
        HttpResponseBody::Buffered(body_bytes) => {
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        Http2HeaderName::from_bytes(name.as_bytes()),
                        Http2HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
                if let Ok(len_value) = Http2HeaderValue::from_str(&body_bytes.len().to_string()) {
                    header_map.insert(Http2HeaderName::from_static("content-length"), len_value);
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            let end_of_stream = body_bytes.is_empty();
            let mut send_stream = respond
                .send_response(response, end_of_stream)
                .map_err(|err| err.to_string())?;
            if !body_bytes.is_empty() {
                send_stream
                    .send_data(Bytes::from(body_bytes), true)
                    .map_err(|err| err.to_string())?;
            }
            Ok(())
        }
        HttpResponseBody::Streaming(mut reader) => {
            http_response_stream_metrics().record_streaming_response();
            strip_content_length(&mut headers);
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        Http2HeaderName::from_bytes(name.as_bytes()),
                        Http2HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            let stream_opened_at = reader.opened_at();
            let headers_send_call_started_at = Instant::now();
            let mut send_stream = respond
                .send_response(response, false)
                .map_err(|err| err.to_string())?;
            let headers_sent_at = Instant::now();
            write_tracker.note_headers_sent(headers_sent_at);
            http_response_stream_metrics().record_headers_sent(
                stream_opened_at,
                headers_send_call_started_at,
                headers_sent_at,
            );
            // The h2 connection driver and per-response streaming tasks share the
            // same Tokio runtime workers. Yield once after queuing headers so the
            // connection can flush them before this task drains ready body chunks.
            tokio::task::yield_now().await;
            let mut first_chunk_recorded = false;
            loop {
                match reader.next().await {
                    Ok(ResponseStreamFrame::Chunk { bytes, queued_at }) => {
                        let send_call_started_at = Instant::now();
                        if let Err(err) = send_stream.send_data(bytes, false) {
                            reader.close();
                            return Err(err.to_string());
                        }
                        if !first_chunk_recorded {
                            let send_call_finished_at = Instant::now();
                            http_response_stream_metrics().record_first_chunk(
                                queued_at,
                                headers_sent_at,
                                send_call_started_at,
                                send_call_started_at,
                                send_call_finished_at,
                            );
                            first_chunk_recorded = true;
                            // The first body chunk determines the client-side
                            // first-byte gap. Yield once after queueing it so
                            // the connection driver can make progress before we
                            // enqueue the rest of a buffered stream.
                            tokio::task::yield_now().await;
                        }
                    }
                    Ok(ResponseStreamFrame::Finished { .. }) => {
                        if let Err(err) = send_stream.send_data(Bytes::new(), true) {
                            return Err(err.to_string());
                        }
                        return Ok(());
                    }
                    Err(err) => {
                        reader.close();
                        return Err(format!("http/2 streaming response failed: {}", err));
                    }
                }
            }
        }
    }
}

async fn process_http3_request(
    connection_id: ConnectionId,
    connection: Arc<QuinnConnection>,
    request: HttpRequest<()>,
    stream: H3ServerBidiStream,
    endpoint_config: Arc<config::EndpointRuntimeConfig>,
    registry: Arc<ListenerRegistry>,
) -> Result<(), String> {
    #[cfg(feature = "ffi-test")]
    eprintln!(
        "http3 processing request {:?}: {} {}",
        connection_id,
        request.method(),
        request.uri()
    );
    let method = request.method().as_str().to_string();
    let normalized_method = method.to_uppercase();
    let target = request
        .uri()
        .path_and_query()
        .map(|pq| pq.as_str().to_string())
        .unwrap_or_else(|| request.uri().path().to_string());
    let (path, query) = split_target_components(&target);
    let headers = flatten_headers(request.headers());

    let max_body = endpoint_config
        .max_http_content_length
        .unwrap_or(HTTP3_DEFAULT_BODY_LIMIT);
    let content_length = parse_content_length(&headers);
    let stats = registry
        .connection_stats(connection_id)
        .map_err(|err| err.to_string())?;
    if let Some(ref stats_arc) = stats {
        stats_arc.record_request();
    }
    let (mut send_stream, recv_stream) = stream.split();
    let body_state = StreamingBodyState::new(content_length.map(|len| len as usize).unwrap_or(0));
    let (idle_timeout, total_timeout) = http_stream_timeouts(&endpoint_config);
    // Apply a generous floor for endpoints that use the default idle timeout so multi-MB tests
    // don't flake; explicit config keeps full control over the timeout values.
    let (idle_timeout, total_timeout) = if endpoint_config.idle_timeout.is_none() {
        (
            idle_timeout.max(Duration::from_secs(30)),
            total_timeout.max(Duration::from_secs(60)),
        )
    } else {
        (idle_timeout, total_timeout)
    };
    spawn_http3_stream_reader(
        stats.clone(),
        Arc::clone(&body_state),
        connection,
        recv_stream,
        max_body,
        0,
        content_length,
        idle_timeout,
        total_timeout,
    );
    let body_handle = HttpBodyHandle::streaming(body_state);

    match endpoint_config.match_http_route(&path, query.as_deref(), &normalized_method, "http3") {
        HttpRouteMatch::Resolved(resolution) => {
            if let Some(failure) = evaluate_http_transport_auth_bytes_headers(
                &resolution.transport_auth,
                &endpoint_config,
                &headers,
            ) {
                return match failure {
                    HttpTransportAuthFailure::BearerRequired => {
                        send_http3_plain_response(
                            &mut send_stream,
                            StatusCode::UNAUTHORIZED,
                            b"bearer token required",
                            &[("www-authenticate", "Bearer")],
                        )
                        .await
                    }
                    HttpTransportAuthFailure::TlsRequired => {
                        send_http3_plain_response(
                            &mut send_stream,
                            StatusCode::FORBIDDEN,
                            b"tls required",
                            &[],
                        )
                        .await
                    }
                    HttpTransportAuthFailure::MutualTlsRequired => {
                        send_http3_plain_response(
                            &mut send_stream,
                            StatusCode::FORBIDDEN,
                            b"mutual tls required",
                            &[],
                        )
                        .await
                    }
                };
            }
            let (tx, rx) = oneshot::channel::<HttpResponseDispatch>();
            let summary = HttpRequestSummary::new(
                normalized_method,
                target,
                path,
                query,
                "http/3".to_string(),
                3,
                headers,
                body_handle,
                Some(resolution.realm.clone()),
                Some(resolution.procedure.clone()),
                Some(resolution),
            );
            let queued = QueuedHttpRequest {
                summary,
                response: HttpResponseHandle::new(connection_id, tx),
            };
            registry
                .enqueue_http_request(connection_id, queued)
                .map_err(|err| err.to_string())?;
            tokio::spawn(async move {
                match rx.await {
                    Ok(dispatch) => {
                        if let Err(err) =
                            send_http3_response_from_dispatch(&mut send_stream, dispatch).await
                        {
                            eprintln!(
                                "failed to send http3 response for connection {:?}: {}",
                                connection_id, err
                            );
                        }
                    }
                    Err(_) => {
                        let _ = send_http3_plain_response(
                            &mut send_stream,
                            StatusCode::INTERNAL_SERVER_ERROR,
                            b"http/3 request cancelled",
                            &[],
                        )
                        .await;
                    }
                }
            });
            Ok(())
        }
        HttpRouteMatch::MethodNotAllowed { allowed_methods } => {
            let allow_value = allowed_methods.join(", ");
            send_http3_plain_response(
                &mut send_stream,
                StatusCode::METHOD_NOT_ALLOWED,
                b"method not allowed",
                &[("allow", allow_value.as_str())],
            )
            .await
        }
        HttpRouteMatch::NotFound => {
            send_http3_plain_response(
                &mut send_stream,
                StatusCode::NOT_FOUND,
                b"route not found",
                &[],
            )
            .await
        }
    }
}

fn flatten_headers(headers: &http::HeaderMap) -> Vec<(Arc<[u8]>, Arc<[u8]>)> {
    headers
        .iter()
        .map(|(name, value)| {
            (
                http_bytes_from_slice(name.as_str().as_bytes()),
                http_bytes_from_slice(value.as_bytes()),
            )
        })
        .collect()
}

fn flatten_http2_headers(headers: &http02::HeaderMap) -> Vec<(Arc<[u8]>, Arc<[u8]>)> {
    headers
        .iter()
        .map(|(name, value)| {
            (
                http_bytes_from_slice(name.as_str().as_bytes()),
                http_bytes_from_slice(value.as_bytes()),
            )
        })
        .collect()
}

fn split_target_components(target: &str) -> (String, Option<String>) {
    match target.split_once('?') {
        Some((path, query)) => (path.to_string(), Some(query.to_string())),
        None => (target.to_string(), None),
    }
}

fn parse_content_length(headers: &[(Arc<[u8]>, Arc<[u8]>)]) -> Option<u64> {
    headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case(CONTENT_LENGTH.as_str().as_bytes()))
        .and_then(|(_, value)| std::str::from_utf8(value.as_ref()).ok())
        .and_then(|value| value.trim().parse::<u64>().ok())
}

fn spawn_http3_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    connection: Arc<QuinnConnection>,
    stream: H3ServerRecvStream,
    max_body: u64,
    bytes_read: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) {
    tokio::spawn(async move {
        let stats_for_reader = stats.clone();
        if let Err(err) = run_http3_stream_reader(
            stats_for_reader,
            state,
            connection,
            stream,
            max_body,
            bytes_read,
            content_length,
            idle_timeout,
            total_timeout,
        )
        .await
        {
            #[cfg(feature = "ffi-test")]
            eprintln!(
                "http/3 body reader failed: {} (max_body {}, idle {:?}, total {:?})",
                err, max_body, idle_timeout, total_timeout
            );
            if let Some(stats_ref) = stats.as_ref() {
                stats_ref
                    .set_close_reason(HttpConnectionCloseReason::ProtocolError, Some(err.clone()));
            }
        }
    });
}

async fn run_http3_stream_reader(
    stats: Option<Arc<HttpConnectionStats>>,
    state: Arc<StreamingBodyState>,
    connection: Arc<QuinnConnection>,
    mut stream: H3ServerRecvStream,
    max_body: u64,
    mut bytes_read: u64,
    content_length: Option<u64>,
    idle_timeout: Duration,
    total_timeout: Duration,
) -> Result<(), String> {
    let total_deadline = Instant::now() + total_timeout;
    loop {
        if state.finish_requested() {
            state.mark_finished();
            return Ok(());
        }
        if Instant::now() >= total_deadline {
            if let Some(stats_ref) = stats.as_ref() {
                stats_ref.record_body_timeout(Some("http/3 body total timeout".into()));
                stats_ref.record_goaway(Some("http/3 body total timeout".into()));
            }
            state.mark_error("http/3 body total timeout exceeded".into());
            connection.close(VarInt::from_u32(0), b"http/3 body total timeout exceeded");
            return Err("http/3 body total timeout".into());
        }
        let recv_future = stream.recv_data();
        let chunk = match time::timeout(idle_timeout, recv_future).await {
            Ok(value) => value,
            Err(_) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.record_idle_timeout(Some("http/3 body idle timeout".into()));
                    stats_ref.record_goaway(Some("http/3 body idle timeout".into()));
                }
                state.mark_error("http/3 body idle timeout".into());
                connection.close(VarInt::from_u32(0), b"http/3 body idle timeout");
                return Err("http/3 body idle timeout".into());
            }
        };
        match chunk {
            Ok(Some(mut chunk)) => {
                while chunk.has_remaining() {
                    let len = chunk.remaining();
                    let bytes = chunk.copy_to_bytes(len);
                    bytes_read += len as u64;
                    if bytes_read > max_body
                        || content_length
                            .map(|limit| bytes_read > limit)
                            .unwrap_or(false)
                    {
                        state.mark_error("http/3 body exceeded configured limit".into());
                        return Ok(());
                    }
                    if content_length.is_none() {
                        state.extend_total_len(len);
                    }
                    if !state.finish_requested() {
                        state.enqueue_bytes(bytes);
                    }
                }
            }
            Ok(None) => {
                if let Some(expected) = content_length {
                    if bytes_read != expected {
                        state.mark_error("http/3 body ended before declared Content-Length".into());
                        return Ok(());
                    }
                }
                state.mark_finished();
                return Ok(());
            }
            Err(err) => {
                if let Some(stats_ref) = stats.as_ref() {
                    stats_ref.set_close_reason(
                        HttpConnectionCloseReason::ProtocolError,
                        Some(format!("http/3 body read failed: {}", err)),
                    );
                }
                // `h3-quinn` keeps the underlying recv stream inside an in-flight
                // future while `recv_data()` is being polled. Calling
                // `stop_sending()` on every shutdown path can therefore panic
                // under load if the stream is dropped mid-poll. Marking the body
                // state and letting the request stream drop avoids the panic while
                // preserving timeout/connection-close handling above.
                state.mark_error(format!("http/3 body read failed: {}", err));
                return Err(err.to_string());
            }
        }
    }
}
#[allow(dead_code)]
fn http_summary_from_handshake(
    handshake: &protocol::HttpHandshake,
    route: &config::HttpRouteResolution,
) -> HttpRequestSummary {
    let (path, query) = protocol::split_http_target(&handshake.request.target);
    let normalized_path = if path.is_empty() { "/" } else { path };
    let body_handle = match &handshake.body {
        HttpBodyPhase::Buffered(bytes) => HttpBodyHandle::from_inline(bytes.clone()),
        HttpBodyPhase::Finished => HttpBodyHandle::empty(),
        HttpBodyPhase::NeedsStreaming { .. } => HttpBodyHandle::empty(),
    };
    HttpRequestSummary::new(
        handshake.request.method.clone(),
        handshake.request.target.clone(),
        normalized_path.to_string(),
        query.map(|value| value.to_string()),
        format!("http/1.{}", handshake.request.version),
        handshake.request.version,
        handshake
            .request
            .headers
            .iter()
            .map(|(name, value)| {
                (
                    http_bytes_from_slice(name.as_bytes()),
                    http_bytes_from_slice(value.as_bytes()),
                )
            })
            .collect(),
        body_handle,
        Some(route.realm.clone()),
        Some(route.procedure.clone()),
        Some(route.clone()),
    )
}

async fn send_http3_plain_response(
    stream: &mut H3ServerSendStream,
    status: StatusCode,
    body: &[u8],
    headers: &[(&str, &str)],
) -> Result<(), String> {
    let mut builder = HttpResponse::builder().status(status);
    {
        let header_map = builder.headers_mut().expect("headers available");
        for (name, value) in headers {
            if let (Ok(name), Ok(value)) = (
                HeaderName::from_bytes(name.as_bytes()),
                HeaderValue::from_str(value),
            ) {
                header_map.insert(name, value);
            }
        }
        if let Ok(len_value) = HeaderValue::from_str(&body.len().to_string()) {
            header_map.insert(CONTENT_LENGTH, len_value);
        }
    }
    let response = builder.body(()).map_err(|err| err.to_string())?;
    stream
        .send_response(response)
        .await
        .map_err(|err| err.to_string())?;
    if !body.is_empty() {
        stream
            .send_data(Bytes::copy_from_slice(body))
            .await
            .map_err(|err| err.to_string())?;
    }
    stream.finish().await.map_err(|err| err.to_string())?;
    Ok(())
}

async fn send_http3_response_from_dispatch(
    stream: &mut H3ServerSendStream,
    dispatch: HttpResponseDispatch,
) -> Result<(), String> {
    let HttpResponseDispatch {
        status,
        mut headers,
        body,
    } = dispatch;
    let clamped = status.clamp(100, 599) as u16;
    let status_code = StatusCode::from_u16(clamped).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    match body {
        HttpResponseBody::Buffered(body_bytes) => {
            let mut builder = HttpResponse::builder().status(status_code);
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        HeaderName::from_bytes(name.as_bytes()),
                        HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
                if let Ok(len_value) = HeaderValue::from_str(&body_bytes.len().to_string()) {
                    header_map.insert(CONTENT_LENGTH, len_value);
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            stream
                .send_response(response)
                .await
                .map_err(|err| err.to_string())?;
            if !body_bytes.is_empty() {
                stream
                    .send_data(Bytes::from(body_bytes))
                    .await
                    .map_err(|err| err.to_string())?;
            }
            stream.finish().await.map_err(|err| err.to_string())
        }
        HttpResponseBody::Streaming(mut reader) => {
            http_response_stream_metrics().record_streaming_response();
            strip_content_length(&mut headers);
            let mut builder = HttpResponse::builder().status(status_code);
            {
                let header_map = builder.headers_mut().expect("headers available");
                for (name, value) in &headers {
                    if let (Ok(name), Ok(value)) = (
                        HeaderName::from_bytes(name.as_bytes()),
                        HeaderValue::from_str(value),
                    ) {
                        header_map.insert(name, value);
                    }
                }
            }
            let response = builder.body(()).map_err(|err| err.to_string())?;
            let stream_opened_at = reader.opened_at();
            let headers_send_call_started_at = Instant::now();
            stream
                .send_response(response)
                .await
                .map_err(|err| err.to_string())?;
            let headers_sent_at = Instant::now();
            http_response_stream_metrics().record_headers_sent(
                stream_opened_at,
                headers_send_call_started_at,
                headers_sent_at,
            );
            let mut first_chunk_recorded = false;
            loop {
                match reader.next().await {
                    Ok(ResponseStreamFrame::Chunk { bytes, queued_at }) => {
                        let send_call_started_at = Instant::now();
                        stream
                            .send_data(bytes)
                            .await
                            .map_err(|err| err.to_string())?;
                        if !first_chunk_recorded {
                            let send_call_finished_at = Instant::now();
                            http_response_stream_metrics().record_first_chunk(
                                queued_at,
                                headers_sent_at,
                                send_call_started_at,
                                send_call_started_at,
                                send_call_finished_at,
                            );
                            first_chunk_recorded = true;
                        }
                    }
                    Ok(ResponseStreamFrame::Finished { .. }) => {
                        reader.close();
                        return stream.finish().await.map_err(|err| err.to_string());
                    }
                    Err(err) => {
                        reader.close();
                        return Err(format!("http/3 streaming response failed: {}", err));
                    }
                }
            }
        }
    }
}

fn resolve_socket_addr(addr: &str, port: u16) -> Result<SocketAddr, Error> {
    let mut addrs = (addr, port)
        .to_socket_addrs()
        .map_err(|_| Error::AddressResolution(addr.to_string(), port))?;
    addrs
        .next()
        .ok_or_else(|| Error::AddressResolution(addr.to_string(), port))
}

fn create_listener(
    addr: SocketAddr,
    backlog: u32,
) -> Result<std::net::TcpListener, std::io::Error> {
    use socket2::{Domain, Socket, Type};

    let domain = if addr.is_ipv4() {
        Domain::IPV4
    } else {
        Domain::IPV6
    };
    let socket = Socket::new(domain, Type::STREAM, None)?;
    socket.set_reuse_address(true)?;
    socket.bind(&addr.into())?;
    socket.listen(backlog as i32)?;
    socket.set_nonblocking(true)?;
    Ok(socket.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rcgen::{
        BasicConstraints, CertificateParams, ExtendedKeyUsagePurpose, IsCa, KeyPair,
        KeyUsagePurpose,
    };
    use rustls::{pki_types::ServerName, ClientConfig as RustlsClientConfig};
    use rustls_pemfile::pkcs8_private_keys;
    use serde_json::json;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::sync::mpsc::error::TryRecvError;
    use tokio_rustls::TlsConnector;

    fn test_guard() -> std::sync::MutexGuard<'static, ()> {
        static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
        // Recover the guard after a prior test panic so one flaky runtime test
        // does not cascade into unrelated PoisonError failures.
        GUARD
            .get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    #[test]
    fn parse_runtime_worker_threads_defaults_to_auto() {
        assert_eq!(parse_runtime_worker_threads(None).unwrap(), None);
        assert_eq!(parse_runtime_worker_threads(Some("")).unwrap(), None);
        assert_eq!(parse_runtime_worker_threads(Some("   ")).unwrap(), None);
    }

    #[test]
    fn parse_runtime_worker_threads_accepts_positive_values() {
        assert_eq!(parse_runtime_worker_threads(Some("1")).unwrap(), Some(1));
        assert_eq!(parse_runtime_worker_threads(Some(" 4 ")).unwrap(), Some(4));
    }

    #[test]
    fn parse_runtime_worker_threads_rejects_zero_and_invalid_values() {
        assert!(matches!(
            parse_runtime_worker_threads(Some("0")),
            Err(Error::InvalidRuntimeThreadCount(_))
        ));
        assert!(matches!(
            parse_runtime_worker_threads(Some("abc")),
            Err(Error::InvalidRuntimeThreadCount(_))
        ));
    }

    #[test]
    fn http2_connection_write_tracker_records_headers_to_first_connection_write() {
        let before = http_response_stream_metrics_snapshot();
        let tracker = Http2ConnectionWriteTracker::default();
        let headers_sent_at = Instant::now();
        tracker.note_headers_sent(headers_sent_at);
        std::thread::sleep(Duration::from_millis(2));
        tracker.record_connection_write(Instant::now());
        let after = http_response_stream_metrics_snapshot();
        assert_eq!(
            after.headers_to_first_connection_write_samples_total
                - before.headers_to_first_connection_write_samples_total,
            1
        );
        assert!(
            after.headers_to_first_connection_write_us_total
                > before.headers_to_first_connection_write_us_total
        );
        assert_eq!(
            after.headers_to_first_connection_write_ge_1ms_total
                - before.headers_to_first_connection_write_ge_1ms_total,
            1
        );
    }

    struct GeneratedTlsMaterial {
        ca_pem: String,
        server_chain_pem: String,
        server_key_pem: String,
        client_chain_pem: String,
        client_key_pem: String,
    }

    fn generate_tls_material() -> GeneratedTlsMaterial {
        let mut ca_params = CertificateParams::new(Vec::new()).expect("ca params");
        ca_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        ca_params.key_usages = vec![
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
            KeyUsagePurpose::DigitalSignature,
        ];
        let ca_key = KeyPair::generate().expect("ca key");
        let ca = ca_params.self_signed(&ca_key).expect("ca cert");
        let ca_pem = ca.pem();

        let mut server_params =
            CertificateParams::new(vec!["localhost".to_string()]).expect("server params");
        server_params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
        server_params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];
        let server_key = KeyPair::generate().expect("server key");
        let server = server_params
            .signed_by(&server_key, &ca, &ca_key)
            .expect("server cert");
        let server_chain_pem = format!("{}\n{}", server.pem(), ca_pem.as_str());
        let server_key_pem = server_key.serialize_pem();

        let mut client_params = CertificateParams::new(Vec::new()).expect("client params");
        client_params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ClientAuth];
        client_params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];
        let client_key = KeyPair::generate().expect("client key");
        let client = client_params
            .signed_by(&client_key, &ca, &ca_key)
            .expect("client cert");
        let client_chain_pem = format!("{}\n{}", client.pem(), ca_pem.as_str());
        let client_key_pem = client_key.serialize_pem();

        GeneratedTlsMaterial {
            ca_pem,
            server_chain_pem,
            server_key_pem,
            client_chain_pem,
            client_key_pem,
        }
    }

    #[test]
    fn enqueue_frame_returns_send_queue_full_when_outbound_queue_saturated() {
        let _guard = test_guard();

        let registry = ListenerRegistry::default();
        let connection_id = ConnectionId(1);
        let listener_id = ListenerId(1);
        let peer_addr: SocketAddr = "127.0.0.1:12345".parse().unwrap();

        let (frame_tx, frame_rx) = mpsc::channel(1);
        let _ = frame_tx;

        let (send_tx, send_rx) = mpsc::channel(1);
        let _send_rx = send_rx;

        send_tx
            .try_send(OutboundFrame::message(Bytes::from_static(b"one")))
            .expect("first send fills the queue");

        let rt = Runtime::new().unwrap();
        let reader_abort = rt.spawn(async {}).abort_handle();
        let writer_abort = rt.spawn(async {}).abort_handle();

        let exponent = config::DEFAULT_RAWSOCKET_SIZE_EXPONENT;
        let endpoint_config = Arc::new(config::EndpointRuntimeConfig {
            host: "127.0.0.1".to_string(),
            port: 0,
            tls_mode: config::TlsMode::Disabled,
            client_auth: None,
            protocols: vec![TransportProtocol::Rawsocket],
            idle_timeout: None,
            heartbeat_interval: None,
            heartbeat_timeout: None,
            handshake_timeout: config::DEFAULT_HANDSHAKE_TIMEOUT,
            max_http_content_length: None,
            max_rawsocket_size_exponent: exponent,
            max_rawsocket_size: 1u64 << exponent,
            max_upgrade_exponent: None,
            outbound_send_queue_capacity: 1,
            websocket_path: None,
            sni_certificates: Vec::new(),
            http_routes: Vec::new(),
            http: None,
        });

        registry.connections.lock().unwrap().insert(
            connection_id,
            ConnectionEntry {
                listener_id,
                peer_addr,
                protocol: ConnectionProtocol::RawSocket,
                websocket_protocol: None,
                endpoint_config,
                stats: None,
                record: ConnectionRecord::RawSocket {
                    _serializer: rawsocket::Serializer::Json,
                    max_exponent: exponent,
                    frames: Arc::new(Mutex::new(frame_rx)),
                    reader_abort,
                    writer_abort,
                    heartbeat_abort: None,
                    send_tx,
                },
            },
        );

        match registry.enqueue_frame(
            connection_id,
            OutboundFrame::message(Bytes::from_static(b"two")),
        ) {
            Err(Error::SendQueueFull(id)) => assert_eq!(id, connection_id),
            other => panic!("expected SendQueueFull, got {other:?}"),
        }
    }

    #[test]
    fn http_body_handle_from_inline_bytes_reuses_backing_storage() {
        let bytes = Bytes::from(vec![1u8, 2, 3, 4]);
        let ptr = bytes.as_ptr();
        let handle = HttpBodyHandle::from_inline(bytes);
        let slice = handle.slice(1, 2).expect("body slice available");
        assert_eq!(slice.ptr, unsafe { ptr.add(1) });
        assert_eq!(slice.len, 2);
        assert_eq!(
            unsafe { std::slice::from_raw_parts(slice.ptr, slice.len) },
            &[2, 3]
        );
    }

    #[test]
    fn flatten_headers_preserves_raw_http1_bytes() {
        let mut headers = http::HeaderMap::new();
        headers.insert(
            HeaderName::from_static("x-binary"),
            HeaderValue::from_bytes(b"abc\xff").expect("header value"),
        );

        let flattened = flatten_headers(&headers);
        assert_eq!(flattened.len(), 1);
        assert_eq!(flattened[0].0.as_ref(), b"x-binary");
        assert_eq!(flattened[0].1.as_ref(), b"abc\xff");
    }

    #[test]
    fn flatten_http2_headers_preserves_raw_bytes() {
        let mut headers = http02::HeaderMap::new();
        headers.insert(
            Http2HeaderName::from_static("x-binary"),
            Http2HeaderValue::from_bytes(b"abc\xff").expect("header value"),
        );

        let flattened = flatten_http2_headers(&headers);
        assert_eq!(flattened.len(), 1);
        assert_eq!(flattened[0].0.as_ref(), b"x-binary");
        assert_eq!(flattened[0].1.as_ref(), b"abc\xff");
    }

    #[test]
    fn parse_content_length_reads_byte_backed_headers() {
        let headers = vec![(
            http_bytes_from_slice(b"content-length"),
            http_bytes_from_slice(b" 42 "),
        )];
        assert_eq!(parse_content_length(&headers), Some(42));
    }

    #[test]
    fn http3_server_config_applies_transport_tuning() {
        let tls = generate_tls_material();
        let endpoint = config::EndpointRuntimeConfig {
            host: "localhost".to_string(),
            port: 8443,
            tls_mode: config::TlsMode::Native,
            client_auth: None,
            protocols: vec![TransportProtocol::Http],
            idle_timeout: None,
            heartbeat_interval: None,
            heartbeat_timeout: None,
            handshake_timeout: config::DEFAULT_HANDSHAKE_TIMEOUT,
            max_http_content_length: None,
            max_rawsocket_size_exponent: config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
            max_rawsocket_size: 1u64 << config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
            max_upgrade_exponent: None,
            outbound_send_queue_capacity: config::DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY,
            websocket_path: None,
            sni_certificates: vec![config::SniCertificate {
                hostname: "localhost".to_string(),
                certificate_chain_pem: tls.server_chain_pem,
                private_key_pem: tls.server_key_pem,
            }],
            http_routes: Vec::new(),
            http: None,
        };

        let server = build_http3_server_config(&endpoint).expect("http3 server config");
        let transport_debug = format!("{:?}", server.transport);
        assert!(transport_debug.contains("max_concurrent_bidi_streams: 1024"));
        assert!(transport_debug.contains("max_concurrent_uni_streams: 256"));
        assert!(transport_debug.contains("stream_receive_window: 8388608"));
        assert!(transport_debug.contains("receive_window: 67108864"));
        assert!(transport_debug.contains("send_window: 67108864"));
        assert!(transport_debug.contains("keep_alive_interval: Some(5s)"));
        assert!(transport_debug.contains("datagram_receive_buffer_size: Some(8388608)"));
        assert!(transport_debug.contains("datagram_send_buffer_size: 8388608"));
    }

    fn build_tls_connector(
        ca_pem: &str,
        client_chain_pem: Option<&str>,
        client_key_pem: Option<&str>,
    ) -> TlsConnector {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let mut roots = rustls::RootCertStore::empty();
        let mut ca_reader = Cursor::new(ca_pem.as_bytes());
        let ca_certs = rustls_pemfile::certs(&mut ca_reader)
            .collect::<Result<Vec<_>, _>>()
            .expect("parse ca certs");
        for cert in ca_certs {
            roots.add(cert).expect("add ca cert");
        }

        let builder = RustlsClientConfig::builder_with_provider(Arc::clone(&provider))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_root_certificates(roots);

        let client_config = match (client_chain_pem, client_key_pem) {
            (Some(chain_pem), Some(key_pem)) => {
                let mut chain_reader = Cursor::new(chain_pem.as_bytes());
                let certs = rustls_pemfile::certs(&mut chain_reader)
                    .collect::<Result<Vec<_>, _>>()
                    .expect("parse client cert chain");
                let mut key_reader = Cursor::new(key_pem.as_bytes());
                let key = pkcs8_private_keys(&mut key_reader)
                    .collect::<Result<Vec<_>, _>>()
                    .expect("parse client key")
                    .into_iter()
                    .next()
                    .expect("client key missing")
                    .into();
                builder
                    .with_client_auth_cert(certs, key)
                    .expect("client auth config")
            }
            _ => builder.with_no_client_auth(),
        };

        TlsConnector::from(Arc::new(client_config))
    }

    #[test]
    fn apply_router_config_stores_config() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":8080,"tls_mode":"disabled"}]}"#)
            .expect("config applies");
        let cfg = crate::config::current_config().expect("config stored");
        assert_eq!(cfg.endpoints.len(), 1);
        let endpoint = crate::config::find_endpoint("127.0.0.1", 8080).expect("endpoint");
        assert_eq!(endpoint.host, "127.0.0.1");
    }

    #[test]
    fn apply_router_config_rejects_invalid_rawsocket_exponent() {
        let _guard = test_guard();
        shutdown().ok();
        let err = super::apply_router_config(br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":8080,"tls_mode":"disabled","max_rawsocket_size_exponent":8}]}"#)
            .expect_err("exponent below minimum rejected");
        assert!(matches!(err, Error::RouterConfigInvalid(_)));

        let err = super::apply_router_config(br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":8080,"tls_mode":"disabled","max_rawsocket_size_exponent":31}]}"#)
            .expect_err("exponent above maximum rejected");
        assert!(matches!(err, Error::RouterConfigInvalid(_)));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn runtime_starts_only_once() {
        let _guard = test_guard();
        shutdown().ok();
        start_runtime().expect("first start succeeds");
        let err = start_runtime().expect_err("second start fails");
        assert!(matches!(err, Error::RuntimeAlreadyStarted));
        shutdown().expect("shutdown succeeds");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn listen_accept_and_shutdown() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        assert!(addr.port() > 0);

        let mut receiver = accept_channel(listener_id).unwrap();
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 16, None).await;
        drop(stream);

        let connection_id = receiver.recv().await.expect("receive connection");
        assert!(connection_id.0 > 0);
        assert!(matches!(receiver.try_recv(), Err(TryRecvError::Empty)));

        shutdown().unwrap();
        // Runtime can be started again after shutdown.
        start_runtime().unwrap();
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn listener_close_removes_entry() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();

        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        assert!(local_addr(listener_id).is_ok());
        close_listener(listener_id).unwrap();
        let err = local_addr(listener_id).expect_err("listener removed");
        assert!(matches!(err, Error::ListenerNotFound(_)));
        let err = close_listener(listener_id).expect_err("second close fails");
        assert!(matches!(err, Error::ListenerNotFound(_)));

        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn tls_accepts_rawsocket_connections() {
        let _guard = test_guard();
        shutdown().ok();
        let cert_pem = include_str!("../../../bench/bench_tls.crt");
        let key_pem = include_str!("../../../bench/bench_tls.key");

        let config = json!({
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[{
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "max_rawsocket_size_exponent":16,
                "sni_certificates":[{
                    "hostname":"localhost",
                    "certificate_chain_pem":cert_pem,
                    "private_key_pem":key_pem
                }]
            }]
        });
        let bytes = serde_json::to_vec(&config).unwrap();
        super::apply_router_config(&bytes).unwrap();

        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        #[derive(Debug)]
        struct NoCertificateVerification {
            schemes: Vec<rustls::SignatureScheme>,
        }

        impl rustls::client::danger::ServerCertVerifier for NoCertificateVerification {
            fn verify_server_cert(
                &self,
                _end_entity: &rustls::pki_types::CertificateDer<'_>,
                _intermediates: &[rustls::pki_types::CertificateDer<'_>],
                _server_name: &ServerName<'_>,
                _ocsp_response: &[u8],
                _now: rustls::pki_types::UnixTime,
            ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
                Ok(rustls::client::danger::ServerCertVerified::assertion())
            }

            fn verify_tls12_signature(
                &self,
                _message: &[u8],
                _cert: &rustls::pki_types::CertificateDer<'_>,
                _dss: &rustls::DigitallySignedStruct,
            ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error>
            {
                Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
            }

            fn verify_tls13_signature(
                &self,
                _message: &[u8],
                _cert: &rustls::pki_types::CertificateDer<'_>,
                _dss: &rustls::DigitallySignedStruct,
            ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error>
            {
                Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
            }

            fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
                self.schemes.clone()
            }
        }

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let verifier = Arc::new(NoCertificateVerification {
            schemes: provider
                .signature_verification_algorithms
                .supported_schemes(),
        });
        let client_config = RustlsClientConfig::builder_with_provider(Arc::clone(&provider))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_no_client_auth();
        let connector = TlsConnector::from(Arc::new(client_config));

        let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
        let server_name = ServerName::try_from("localhost").unwrap();
        let mut tls_stream = connector.connect(server_name, tcp).await.unwrap();

        let handshake_byte = ((16u8 - 9) << 4) | 0x01;
        tls_stream
            .write_all(&[0x7F, handshake_byte, 0x00, 0x00])
            .await
            .unwrap();
        let mut response = [0u8; 4];
        tls_stream.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], 0x7F);
        drop(tls_stream);

        let connection_id = receiver.recv().await.expect("connection delivered");
        assert!(connection_id.0 > 0);
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn reload_tls_updates_client_auth_mode() {
        let _guard = test_guard();
        shutdown().ok();

        let tls = generate_tls_material();
        let optional_cfg = json!({
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[{
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "max_rawsocket_size_exponent":16,
                "sni_certificates":[{
                    "hostname":"localhost",
                    "certificate_chain_pem":tls.server_chain_pem,
                    "private_key_pem":tls.server_key_pem
                }],
                "client_auth": {
                    "mode":"optional",
                    "ca_certificates_pem":tls.ca_pem
                }
            }]
        });
        let bytes = serde_json::to_vec(&optional_cfg).unwrap();
        super::apply_router_config(&bytes).unwrap();

        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let connector = build_tls_connector(&tls.ca_pem, None, None);
        let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut tls_stream = connector
            .connect(ServerName::try_from("localhost").unwrap(), tcp)
            .await
            .unwrap();

        let handshake_byte = ((16u8 - 9) << 4) | 0x01;
        tls_stream
            .write_all(&[0x7F, handshake_byte, 0x00, 0x00])
            .await
            .unwrap();
        let mut response = [0u8; 4];
        tls_stream.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], 0x7F);
        drop(tls_stream);

        let connection_id = receiver.recv().await.expect("connection delivered");
        assert!(connection_id.0 > 0);

        let required_cfg = json!({
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[{
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "max_rawsocket_size_exponent":16,
                "sni_certificates":[{
                    "hostname":"localhost",
                    "certificate_chain_pem":tls.server_chain_pem,
                    "private_key_pem":tls.server_key_pem
                }],
                "client_auth": {
                    "mode":"required",
                    "ca_certificates_pem":tls.ca_pem
                }
            }]
        });
        let bytes = serde_json::to_vec(&required_cfg).unwrap();
        super::apply_router_config(&bytes).unwrap();
        reload_tls().unwrap();

        let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
        match connector
            .connect(ServerName::try_from("localhost").unwrap(), tcp)
            .await
        {
            Ok(mut stream) => {
                let result = stream.write_all(&[0x7F, handshake_byte, 0x00, 0x00]).await;
                if result.is_ok() {
                    let mut buf = [0u8; 4];
                    let read = stream.read_exact(&mut buf).await;
                    assert!(read.is_err(), "expected client auth failure");
                }
            }
            Err(_) => {}
        }

        let timeout = tokio::time::timeout(Duration::from_millis(150), receiver.recv()).await;
        assert!(timeout.is_err(), "unexpected connection delivered");

        let client_connector = build_tls_connector(
            &tls.ca_pem,
            Some(&tls.client_chain_pem),
            Some(&tls.client_key_pem),
        );
        let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut tls_stream = client_connector
            .connect(ServerName::try_from("localhost").unwrap(), tcp)
            .await
            .unwrap();
        tls_stream
            .write_all(&[0x7F, handshake_byte, 0x00, 0x00])
            .await
            .unwrap();
        tls_stream.read_exact(&mut response).await.unwrap();
        assert_eq!(response[0], 0x7F);
        drop(tls_stream);

        let connection_id = receiver.recv().await.expect("connection delivered");
        assert!(connection_id.0 > 0);
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connection_runtime_config_exposes_rawsocket_settings() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":30}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 24, Some(30)).await;

        let connection_id = receiver.recv().await.expect("connection delivered");
        let config = connection_runtime_config(connection_id).expect("config available");
        assert_eq!(config.max_rawsocket_size_exponent, 30);
        assert_eq!(config.max_rawsocket_size, 1u64 << 30);
        assert_eq!(config.handshake_timeout, config::DEFAULT_HANDSHAKE_TIMEOUT);
        assert_eq!(
            connection_rawsocket_max_exponent(connection_id).unwrap(),
            30
        );

        let missing_err =
            connection_runtime_config(ConnectionId(9999)).expect_err("missing connection handled");
        assert!(matches!(
            missing_err,
            Error::ConnectionNotFound(ConnectionId(_))
        ));
        drop(stream);
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connect_rawsocket_registers_outbound_client_connection() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":30}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let client_connection_id = connect_rawsocket(
            "127.0.0.1",
            addr.port(),
            false,
            false,
            RawSocketSerializer::Json,
            30,
            None,
            None,
        )
        .unwrap();
        let server_connection_id = receiver.recv().await.expect("server connection");

        assert_eq!(
            connection_rawsocket_max_exponent(client_connection_id).unwrap(),
            30
        );
        assert_eq!(
            connection_rawsocket_max_exponent(server_connection_id).unwrap(),
            30
        );

        send_wamp_message(
            client_connection_id,
            Bytes::from_static(br#"[1,"realm",{}]"#),
        )
        .unwrap();
        let server_message = wait_for_polled_message(server_connection_id).await;
        match server_message.message {
            WampMessage::Hello { realm, .. } => assert_eq!(realm, "realm"),
            other => panic!("unexpected server message: {other:?}"),
        }

        send_wamp_message(server_connection_id, Bytes::from_static(br#"[2,4242,{}]"#)).unwrap();
        let client_message = wait_for_polled_message(client_connection_id).await;
        match client_message.message {
            WampMessage::Welcome { session_id, .. } => assert_eq!(session_id, 4242),
            other => panic!("unexpected client message: {other:?}"),
        }

        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connect_rawsocket_supports_native_tls_client_connections() {
        let _guard = test_guard();
        shutdown().ok();
        let cert_pem = include_str!("../../../bench/bench_tls.crt");
        let key_pem = include_str!("../../../bench/bench_tls.key");
        let config = json!({
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[{
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "max_rawsocket_size_exponent":16,
                "sni_certificates":[{
                    "hostname":"localhost",
                    "certificate_chain_pem":cert_pem,
                    "private_key_pem":key_pem
                }]
            }]
        });
        super::apply_router_config(&serde_json::to_vec(&config).unwrap()).unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let client_connection_id = connect_rawsocket(
            "localhost",
            addr.port(),
            true,
            true,
            RawSocketSerializer::Json,
            16,
            None,
            None,
        )
        .unwrap();
        let server_connection_id = receiver.recv().await.expect("server connection");

        send_wamp_message(
            client_connection_id,
            Bytes::from_static(br#"[1,"realm",{}]"#),
        )
        .unwrap();
        let server_message = wait_for_polled_message(server_connection_id).await;
        match server_message.message {
            WampMessage::Hello { realm, .. } => assert_eq!(realm, "realm"),
            other => panic!("unexpected tls server message: {other:?}"),
        }

        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connect_websocket_registers_outbound_client_connection() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["websocket"]}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let connect = tokio::task::spawn_blocking(move || {
            connect_websocket(
                "127.0.0.1",
                addr.port(),
                "/wamp",
                false,
                false,
                RawSocketSerializer::Json,
                &[("X-Test".to_string(), "1".to_string())],
                None,
                None,
            )
        });

        let server_connection_id = receiver.recv().await.expect("server connection");
        let handshake = connection_take_websocket_handshake(server_connection_id).unwrap();
        assert_eq!(handshake.http.request.header("X-Test"), Some("1"));
        assert!(handshake
            .sec_websocket_protocols
            .iter()
            .any(|value| value == "wamp.2.json"));
        connection_accept_websocket(
            server_connection_id,
            handshake,
            RawSocketSerializer::Json,
            Some("wamp.2.json"),
        )
        .unwrap();

        let client_connection_id = connect.await.unwrap().unwrap();
        assert_eq!(
            connection_websocket_protocol(client_connection_id).unwrap(),
            Some("wamp.2.json".to_string())
        );

        send_wamp_message(
            client_connection_id,
            Bytes::from_static(br#"[1,"realm",{}]"#),
        )
        .unwrap();
        let server_message = wait_for_polled_message(server_connection_id).await;
        match server_message.message {
            WampMessage::Hello { realm, .. } => assert_eq!(realm, "realm"),
            other => panic!("unexpected websocket server message: {other:?}"),
        }

        send_wamp_message(server_connection_id, Bytes::from_static(br#"[2,5150,{}]"#)).unwrap();
        let client_message = wait_for_polled_message(client_connection_id).await;
        match client_message.message {
            WampMessage::Welcome { session_id, .. } => assert_eq!(session_id, 5150),
            other => panic!("unexpected websocket client message: {other:?}"),
        }

        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn close_connection_sends_websocket_close_frame_for_outbound_client() {
        let _guard = test_guard();
        shutdown().ok();
        start_runtime().unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let mut stream = IoStream::plain(socket);
            let headers = read_http_header_block(&mut stream, Duration::from_secs(1))
                .await
                .unwrap();
            let header_text = std::str::from_utf8(&headers).unwrap();
            let key = header_text
                .split("\r\n")
                .find_map(|line| {
                    let (name, value) = line.split_once(':')?;
                    if name.eq_ignore_ascii_case("sec-websocket-key") {
                        Some(value.trim().to_string())
                    } else {
                        None
                    }
                })
                .expect("sec-websocket-key present");
            let accept = websocket_accept_value(&key);
            write_websocket_handshake_response(&mut stream, &accept, Some("wamp.2.json"))
                .await
                .unwrap();
            let (mut reader, _) = tokio::io::split(stream);
            let pool = Arc::new(WebSocketBufferPool::default());
            let close_frame = time::timeout(
                Duration::from_secs(1),
                read_websocket_frame(&mut reader, &pool),
            )
            .await
            .expect("close frame arrives in time")
            .unwrap();
            match close_frame {
                WebSocketFrame::Close(code, reason) => {
                    assert_eq!(code, Some(1000));
                    assert!(reason.is_empty());
                }
                other => panic!("unexpected websocket frame: {other:?}"),
            }
        });

        let client_connection_id = tokio::task::spawn_blocking(move || {
            connect_websocket(
                "127.0.0.1",
                addr.port(),
                "/wamp",
                false,
                false,
                RawSocketSerializer::Json,
                &[],
                None,
                None,
            )
        })
        .await
        .unwrap()
        .unwrap();

        close_connection(client_connection_id).unwrap();
        server.await.unwrap();
        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn connection_messages_can_be_polled() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":16}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let mut client = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut client, 16, None).await;
        let hello = json!([1, "realm", {"roles": {"dealer": {}}}]);
        let payload = serde_json::to_vec(&hello).unwrap();
        send_json_frame(&mut client, &payload).await;

        let connection_id = receiver.recv().await.expect("connection delivered");

        let mut attempts = 0;
        let parsed = loop {
            if let Some(msg) = poll_connection_message(connection_id).expect("poll succeeds") {
                break msg;
            }
            attempts += 1;
            if attempts > 20 {
                panic!("message not delivered in time");
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        };

        match parsed.message {
            WampMessage::Hello { realm, .. } => assert_eq!(realm, "realm"),
            other => panic!("unexpected message: {:?}", other),
        }

        shutdown().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn handshake_timeout_rejects_idle_clients() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","handshake_timeout_ms":100,"max_rawsocket_size_exponent":16}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let addr = local_addr(listener_id).unwrap();
        let mut receiver = accept_channel(listener_id).unwrap();

        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        // Intentionally do not send handshake bytes.
        tokio::time::sleep(Duration::from_millis(150)).await;
        drop(stream);

        assert!(matches!(receiver.try_recv(), Err(TryRecvError::Empty)));
        shutdown().unwrap();
    }

    async fn wait_for_polled_message(connection_id: ConnectionId) -> super::ParsedMessage {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            match poll_connection_message(connection_id).unwrap() {
                Some(message) => return message,
                None if Instant::now() < deadline => {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
                None => panic!("timed out waiting for message on {connection_id:?}"),
            }
        }
    }

    async fn perform_handshake(
        stream: &mut tokio::net::TcpStream,
        exponent: u32,
        upgrade: Option<u32>,
    ) {
        let clamped = exponent.clamp(9, 24);
        let handshake_byte = ((clamped - 9) as u8).min(15) << 4 | 0x01;
        stream
            .write_all(&[0x7F, handshake_byte, 0x00, 0x00])
            .await
            .expect("handshake write");
        let mut response = [0u8; 4];
        stream
            .read_exact(&mut response)
            .await
            .expect("handshake response");
        assert_eq!(response[0], 0x7F);
        if let Some(upgrade_exponent) = upgrade {
            let nibble = (upgrade_exponent.saturating_sub(25)).min(15) as u8;
            stream
                .write_all(&[0x3F, nibble])
                .await
                .expect("upgrade request");
            let mut upgrade_response = [0u8; 2];
            stream
                .read_exact(&mut upgrade_response)
                .await
                .expect("upgrade response");
            assert_eq!(upgrade_response[0], 0x3F);
        }
    }

    async fn send_json_frame(stream: &mut tokio::net::TcpStream, payload: &[u8]) {
        assert!(payload.len() <= super::MAX_FRAME_LEN as usize);
        let mut header = [0u8; 4];
        if payload.len() == super::MAX_FRAME_LEN as usize {
            header[0] = 0x08;
        } else {
            header[0] = 0x00;
            header[1] = ((payload.len() >> 16) & 0xFF) as u8;
            header[2] = ((payload.len() >> 8) & 0xFF) as u8;
            header[3] = (payload.len() & 0xFF) as u8;
        }
        stream.write_all(&header).await.unwrap();
        if !payload.is_empty() {
            stream.write_all(payload).await.unwrap();
        }
    }

    async fn read_websocket_frame_from_bytes(
        frame: &[u8],
    ) -> Result<WebSocketFrame, WebSocketFrameError> {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let payload = frame.to_vec();
        let pool = Arc::new(WebSocketBufferPool::default());

        let reader = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let io = IoStream::plain(stream);
            let (mut reader, _) = tokio::io::split(io);
            read_websocket_frame(&mut reader, &pool).await
        });

        let mut client = tokio::net::TcpStream::connect(addr).await.unwrap();
        client.write_all(&payload).await.unwrap();
        client.shutdown().await.unwrap();

        reader.await.unwrap()
    }

    async fn write_websocket_frame_to_bytes(opcode: u8, segments: Vec<Bytes>) -> Vec<u8> {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let payload_len = segments.iter().map(Bytes::len).sum();

        let writer = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let io = IoStream::plain(stream);
            let (_, mut writer) = tokio::io::split(io);
            write_websocket_frame(&mut writer, opcode, payload_len, &segments)
                .await
                .unwrap();
        });

        let mut client = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut bytes = Vec::new();
        client.read_to_end(&mut bytes).await.unwrap();
        writer.await.unwrap();
        bytes
    }

    async fn write_websocket_frame_client_to_bytes(opcode: u8, segments: Vec<Bytes>) -> Vec<u8> {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let payload_len = segments.iter().map(Bytes::len).sum();

        let writer = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let io = IoStream::plain(stream);
            let (_, mut writer) = tokio::io::split(io);
            write_websocket_frame_client(&mut writer, opcode, payload_len, &segments)
                .await
                .unwrap();
        });

        let mut client = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut bytes = Vec::new();
        client.read_to_end(&mut bytes).await.unwrap();
        writer.await.unwrap();
        bytes
    }

    async fn read_websocket_frames_from_bytes_mode(
        frame: &[u8],
        expect_masked: bool,
    ) -> Vec<WebSocketFrame> {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let payload = frame.to_vec();
        let pool = Arc::new(WebSocketBufferPool::default());

        let reader = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let io = IoStream::plain(stream);
            let (mut reader, _) = tokio::io::split(io);
            let mut frames = Vec::new();
            loop {
                match read_websocket_frame_mode(&mut reader, &pool, expect_masked).await {
                    Ok(frame) => frames.push(frame),
                    Err(err) if err.is_peer_disconnect() => break frames,
                    Err(err) => panic!("unexpected websocket frame read error: {err}"),
                }
            }
        });

        let mut client = tokio::net::TcpStream::connect(addr).await.unwrap();
        client.write_all(&payload).await.unwrap();
        client.shutdown().await.unwrap();

        reader.await.unwrap()
    }

    #[test]
    fn websocket_buffer_pool_recycles_owner_backed_bytes() {
        let pool = Arc::new(WebSocketBufferPool::default());
        let mut buffer = pool.acquire(4);
        buffer.as_mut_slice().copy_from_slice(b"ping");
        let bytes = buffer.into_bytes();
        assert_eq!(pool.available_buffers(), 0);
        assert_eq!(bytes.as_ref(), b"ping");
        drop(bytes);
        assert_eq!(pool.available_buffers(), 1);
    }

    #[test]
    fn websocket_accumulator_returns_single_frame_without_copy() {
        let pool = Arc::new(WebSocketBufferPool::default());
        let mut accumulator = WebSocketMessageAccumulator::new(pool);
        let payload = Bytes::from_static(b"single-frame");
        let ptr = payload.as_ptr();
        accumulator
            .push(0x1, true, payload)
            .expect("single websocket frame accepted");
        let assembled = accumulator.take_complete().expect("message assembled");
        match assembled {
            CompletedWebSocketMessage::Single(bytes) => {
                assert_eq!(bytes.as_ptr(), ptr);
                assert_eq!(bytes.as_ref(), b"single-frame");
            }
            CompletedWebSocketMessage::Segmented { .. } => {
                panic!("single websocket frame should stay single-segment")
            }
        }
    }

    #[tokio::test]
    async fn websocket_client_writer_masks_large_contiguous_payload_in_chunks() {
        let first = vec![0x41; WEBSOCKET_MASK_CHUNK_SIZE * 2 + 137];
        let second = vec![0x42; WEBSOCKET_MASK_CHUNK_SIZE + 19];
        let expected = [first.as_slice(), second.as_slice()].concat();
        let bytes =
            write_websocket_frame_client_to_bytes(0x2, vec![Bytes::from(expected.clone())]).await;
        let frame = read_websocket_frame_from_bytes(&bytes)
            .await
            .expect("masked client frame should decode");
        match frame {
            WebSocketFrame::Data {
                opcode,
                fin,
                payload,
            } => {
                assert_eq!(opcode, 0x2);
                assert!(fin);
                assert_eq!(payload.as_ref(), expected.as_slice());
            }
            other => panic!("expected websocket data frame, got {other:?}"),
        }
    }

    #[test]
    fn websocket_accumulator_keeps_fragment_handles_until_completion() {
        let pool = Arc::new(WebSocketBufferPool::default());
        let mut accumulator = WebSocketMessageAccumulator::new(Arc::clone(&pool));
        let first = Bytes::from_static(b"first-");
        let second = Bytes::from_static(b"second");
        let first_ptr = first.as_ptr();
        let second_ptr = second.as_ptr();
        accumulator
            .push(0x1, false, first)
            .expect("first fragment accepted");
        accumulator
            .push(0x0, true, second)
            .expect("continuation fragment accepted");
        let assembled = accumulator.take_complete().expect("message assembled");
        match assembled {
            CompletedWebSocketMessage::Single(_) => {
                panic!("fragmented websocket message should stay segmented until flatten")
            }
            CompletedWebSocketMessage::Segmented { segments, len } => {
                assert_eq!(len, 12);
                assert_eq!(segments.len(), 2);
                assert_eq!(segments[0].as_ptr(), first_ptr);
                assert_eq!(segments[1].as_ptr(), second_ptr);
                assert_eq!(pool.available_buffers(), 0);
            }
        }
    }

    #[test]
    fn websocket_fragmented_message_flattens_once_and_recycles_after_drop() {
        let pool = Arc::new(WebSocketBufferPool::default());
        let mut accumulator = WebSocketMessageAccumulator::new(Arc::clone(&pool));
        accumulator
            .push(0x1, false, Bytes::from_static(b"first-"))
            .expect("first fragment accepted");
        accumulator
            .push(0x0, true, Bytes::from_static(b"second"))
            .expect("continuation fragment accepted");
        let assembled = accumulator
            .take_complete()
            .expect("message assembled")
            .into_bytes(&pool);
        assert_eq!(assembled.as_ref(), b"first-second");
        assert_eq!(pool.available_buffers(), 0);
        drop(assembled);
        assert_eq!(pool.available_buffers(), 1);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_writer_serializes_segmented_payload() {
        let bytes = write_websocket_frame_to_bytes(
            0x1,
            vec![
                Bytes::from_static(b"hello"),
                Bytes::new(),
                Bytes::from_static(b"-world"),
            ],
        )
        .await;
        assert_eq!(
            bytes,
            [
                0x01, 0x05, b'h', b'e', b'l', b'l', b'o', 0x80, 0x06, b'-', b'w', b'o', b'r', b'l',
                b'd',
            ]
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_client_writer_serializes_segmented_payload_as_continuations() {
        let bytes = write_websocket_frame_client_to_bytes(
            0x2,
            vec![
                Bytes::from_static(b"hello"),
                Bytes::new(),
                Bytes::from_static(b"-world"),
            ],
        )
        .await;
        let frames = read_websocket_frames_from_bytes_mode(&bytes, true).await;
        assert_eq!(frames.len(), 2);
        match &frames[0] {
            WebSocketFrame::Data {
                opcode,
                fin,
                payload,
            } => {
                assert_eq!(*opcode, 0x2);
                assert!(!fin);
                assert_eq!(payload.as_ref(), b"hello");
            }
            other => panic!("expected first segmented websocket data frame, got {other:?}"),
        }
        match &frames[1] {
            WebSocketFrame::Data {
                opcode,
                fin,
                payload,
            } => {
                assert_eq!(*opcode, 0x0);
                assert!(*fin);
                assert_eq!(payload.as_ref(), b"-world");
            }
            other => panic!("expected continuation websocket frame, got {other:?}"),
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_frame_requires_masking() {
        let frame = [0x81, 0x01, b'x'];
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("unmasked client frame rejected");
        assert_eq!(err.close_code(), Some(1002));
        assert!(err.to_string().contains("must be masked"));
        assert!(!err.is_peer_disconnect());
    }

    #[test]
    fn websocket_io_disconnects_are_classified_as_peer_shutdowns() {
        let err =
            WebSocketFrameError::io(io::Error::new(io::ErrorKind::UnexpectedEof, "early eof"));
        assert!(err.is_peer_disconnect());
        assert!(is_benign_socket_shutdown(io::ErrorKind::ConnectionReset));
        assert!(!is_benign_socket_shutdown(io::ErrorKind::InvalidData));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_frame_rejects_reserved_bits() {
        let frame = [0xC1, 0x80, 0x00, 0x00, 0x00, 0x00];
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("reserved bits rejected");
        assert_eq!(err.close_code(), Some(1002));
        assert!(err.to_string().contains("reserved bits"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_frame_rejects_fragmented_control_frames() {
        let frame = [0x09, 0x81, 0x00, 0x00, 0x00, 0x00, b'x'];
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("fragmented ping rejected");
        assert_eq!(err.close_code(), Some(1002));
        assert!(err.to_string().contains("must not be fragmented"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_frame_rejects_oversized_control_payloads() {
        let mut frame = vec![0x89, 0xFE, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00];
        frame.extend(std::iter::repeat_n(0u8, 126));
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("oversized ping rejected");
        assert_eq!(err.close_code(), Some(1002));
        assert!(err.to_string().contains("must not exceed 125 bytes"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_frame_rejects_oversized_messages() {
        let len = super::MAX_WEBSOCKET_MESSAGE_LEN as u64 + 1;
        let mut frame = vec![0x82, 0xFF];
        frame.extend_from_slice(&len.to_be_bytes());
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("oversized websocket message rejected");
        assert_eq!(err.close_code(), Some(1009));
        assert!(err.to_string().contains("exceeds supported length"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_close_frame_rejects_single_byte_payload() {
        let frame = [0x88, 0x81, 0x00, 0x00, 0x00, 0x00, 0x01];
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("1-byte close payload rejected");
        assert_eq!(err.close_code(), Some(1002));
        assert!(err.to_string().contains("2-byte status code"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_close_frame_rejects_invalid_utf8_reason() {
        let frame = [0x88, 0x83, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8, 0xFF];
        let err = read_websocket_frame_from_bytes(&frame)
            .await
            .expect_err("invalid close reason rejected");
        assert_eq!(err.close_code(), Some(1007));
        assert!(err.to_string().contains("valid UTF-8"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn websocket_close_frame_allows_empty_payload() {
        let frame = [0x88, 0x80, 0x00, 0x00, 0x00, 0x00];
        let parsed = read_websocket_frame_from_bytes(&frame)
            .await
            .expect("empty close payload accepted");
        match parsed {
            WebSocketFrame::Close(None, reason) => assert!(reason.is_empty()),
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn accept_channel_only_once() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let listener_id = listen("127.0.0.1", 0, 128).unwrap();
        let _receiver = accept_channel(listener_id).unwrap();
        let err = accept_channel(listener_id).expect_err("second take fails");
        assert!(matches!(
            err,
            Error::AcceptChannelAlreadyTaken(ListenerId(_))
        ));
        shutdown().unwrap();
    }

    #[test]
    fn listen_without_runtime_fails() {
        let _guard = test_guard();
        shutdown().ok();
        let err = listen("127.0.0.1", 0, 128).expect_err("runtime missing");
        assert!(matches!(err, Error::RuntimeNotStarted));
    }

    #[test]
    fn invalid_backlog_is_rejected() {
        let _guard = test_guard();
        shutdown().ok();
        super::apply_router_config(
            br#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled"}]}"#,
        )
        .unwrap();
        start_runtime().unwrap();
        let err = listen("127.0.0.1", 0, 0).expect_err("invalid backlog");
        assert!(matches!(err, Error::InvalidBacklog));
        shutdown().unwrap();
    }

    #[test]
    fn unknown_listener_errors() {
        let _guard = test_guard();
        shutdown().ok();
        start_runtime().unwrap();
        let err = local_addr(ListenerId(999)).expect_err("missing listener");
        assert!(matches!(err, Error::ListenerNotFound(ListenerId(_))));
        shutdown().unwrap();
    }
}
