use super::*;

fn endpoint() -> Arc<config::EndpointRuntimeConfig> {
    let config = serde_json::from_value::<config::EndpointConfig>(serde_json::json!({
        "host": "127.0.0.1", "port": 0, "tls_mode": "disabled"
    }));
    assert!(config.is_ok());
    let runtime = config::EndpointRuntimeConfig::try_from_endpoint(&config.unwrap());
    assert!(runtime.is_ok());
    Arc::new(runtime.unwrap())
}

fn missing<T>(result: Result<T, Error>, id: ConnectionId) {
    assert!(matches!(result, Err(Error::ConnectionNotFound(actual)) if actual == id));
}

fn unsupported<T>(result: Result<T, Error>, id: ConnectionId, protocol: ConnectionProtocol) {
    assert!(
        matches!(result, Err(Error::UnsupportedProtocol(actual, actual_protocol))
        if actual == id && actual_protocol == protocol)
    );
}

fn request(
    id: ConnectionId,
    path: &str,
) -> (QueuedHttpRequest, oneshot::Receiver<HttpResponseDispatch>) {
    let (sender, receiver) = oneshot::channel();
    (
        QueuedHttpRequest {
            summary: HttpRequestSummary::new(
                "POST".into(),
                path.into(),
                path.into(),
                None,
                "HTTP".into(),
                1,
                vec![],
                HttpBodyHandle::from_bytes(path.as_bytes().to_vec()),
                None,
                None,
                None,
            ),
            response: HttpResponseHandle::new(id, sender),
        },
        receiver,
    )
}

fn response(status: i32, body: &[u8]) -> HttpResponseDispatch {
    HttpResponseDispatch {
        status,
        headers: vec![("content-type".into(), "application/octet-stream".into())],
        body: HttpResponseBody::Buffered(body.to_vec()),
    }
}

// HTTP/2 and HTTP/3 fixtures represent records after the handshake was taken.
// Their queue/accessor contracts do not require a network connection.
fn register_pending(registry: &ListenerRegistry, id: ConnectionId, protocol: ConnectionProtocol) {
    let endpoint = endpoint();
    let peer = SocketAddr::from(([127, 0, 0, 1], 12345));
    if protocol == ConnectionProtocol::Http {
        registry.register_http_connection(ListenerId(17), id, endpoint, peer);
        return;
    }
    let record = match protocol {
        ConnectionProtocol::Http2 => ConnectionRecord::Http2Pending {
            handshake: Mutex::new(None),
            pending_requests: Mutex::new(VecDeque::new()),
        },
        ConnectionProtocol::Http3 => ConnectionRecord::Http3Pending {
            handshake: Mutex::new(None),
            connection: Mutex::new(None),
            streams: Arc::new(Http3StreamChannels::new()),
            pending_requests: Mutex::new(VecDeque::new()),
        },
        ConnectionProtocol::WebSocket => ConnectionRecord::WebSocketPending {
            handshake: Mutex::new(None),
        },
        _ => panic!("unsupported test fixture"),
    };
    registry.connections.lock().unwrap().insert(
        id,
        ConnectionEntry {
            listener_id: ListenerId(17),
            peer_addr: peer,
            protocol,
            websocket_protocol: None,
            endpoint_config: endpoint,
            stats: Some(HttpConnectionStats::new(protocol)),
            record,
        },
    );
}

#[test]
fn missing_connection_ids_preserve_identity_across_accessors() {
    let registry = ListenerRegistry::default();
    for id in [ConnectionId(0), ConnectionId(1), ConnectionId(u32::MAX)] {
        missing(registry.connection_config(id), id);
        missing(registry.connection_stats(id), id);
        missing(registry.connection_exponent(id), id);
        missing(registry.connection_supports_file_segments(id), id);
        missing(registry.connection_protocol(id), id);
        missing(registry.connection_websocket_protocol(id), id);
        missing(registry.poll_message(id), id);
        missing(registry.message_frames(id), id);
        missing(
            registry.enqueue_frame(id, OutboundFrame::message(Bytes::new())),
            id,
        );
        missing(
            registry.enqueue_file_frame(id, OutboundFrame::message(Bytes::new())),
            id,
        );
        missing(registry.take_websocket_handshake(id), id);
        missing(registry.take_http2_handshake(id), id);
        missing(registry.take_http3_handshake(id), id);
        missing(registry.http3_connection(id), id);
        missing(registry.poll_http3_stream(id), id);
        missing(registry.poll_http_request(id), id);
        let (request, mut receiver) = request(id, "/missing");
        missing(registry.enqueue_http_request(id, request), id);
        assert!(matches!(
            receiver.try_recv(),
            Err(oneshot::error::TryRecvError::Closed)
        ));
        missing(registry.close_connection(id), id);
        assert!(registry.connections.lock().unwrap().is_empty());
    }
}

#[test]
fn http_accessors_reject_wamp_protocols_without_consuming_requests() {
    let registry = ListenerRegistry::default();
    for (index, protocol) in [
        ConnectionProtocol::Http,
        ConnectionProtocol::Http2,
        ConnectionProtocol::Http3,
    ]
    .into_iter()
    .enumerate()
    {
        let id = ConnectionId(index as u32 + 11);
        register_pending(&registry, id, protocol);
        assert_eq!(registry.connection_protocol(id).unwrap(), protocol);
        assert!(!registry.connection_supports_file_segments(id).unwrap());
        let config = registry.connection_config(id).unwrap();
        assert!(Arc::ptr_eq(
            &config,
            &registry.connection_config(id).unwrap()
        ));
        assert_eq!(
            registry.connection_stats(id).unwrap().is_some(),
            protocol != ConnectionProtocol::Http
        );
        let (request, mut receiver) = request(id, "/preserved");
        assert!(registry.enqueue_http_request(id, request).is_ok());
        unsupported(registry.connection_exponent(id), id, protocol);
        unsupported(registry.connection_websocket_protocol(id), id, protocol);
        unsupported(registry.message_frames(id), id, protocol);
        unsupported(registry.poll_message(id), id, protocol);
        unsupported(
            registry.enqueue_frame(id, OutboundFrame::message(Bytes::new())),
            id,
            protocol,
        );
        unsupported(
            registry.enqueue_file_frame(id, OutboundFrame::message(Bytes::new())),
            id,
            protocol,
        );
        unsupported(registry.take_websocket_handshake(id), id, protocol);
        if protocol != ConnectionProtocol::Http2 {
            unsupported(registry.take_http2_handshake(id), id, protocol);
        } else {
            assert!(
                matches!(registry.take_http2_handshake(id), Err(Error::HandshakeAlreadyTaken(actual)) if actual == id)
            );
        }
        if protocol != ConnectionProtocol::Http3 {
            unsupported(registry.take_http3_handshake(id), id, protocol);
            unsupported(registry.http3_connection(id), id, protocol);
            unsupported(registry.poll_http3_stream(id), id, protocol);
        } else {
            assert!(
                matches!(registry.take_http3_handshake(id), Err(Error::HandshakeAlreadyTaken(actual)) if actual == id)
            );
            assert!(
                matches!(registry.http3_connection(id), Err(Error::ConnectionHandleUnavailable(actual)) if actual == id)
            );
            assert!(matches!(registry.poll_http3_stream(id), Ok(None)));
        }
        assert!(matches!(
            receiver.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ));
        let pending = registry.poll_http_request(id);
        assert!(matches!(&pending, Ok(Some(_))));
        let (summary, handle) = pending.unwrap().unwrap();
        assert_eq!(summary.path.as_ref(), b"/preserved");
        let inline = summary.body.inline_bytes();
        assert!(inline.is_some());
        assert_eq!(inline.unwrap().as_ref(), b"/preserved");
        assert!(matches!(registry.poll_http_request(id), Ok(None)));
        assert!(handle.respond(response(201, b"kept")).is_ok());
        let delivered = receiver.try_recv();
        assert!(delivered.is_ok());
        assert_eq!(delivered.unwrap().status, 201);
        assert!(registry.close_connection(id).is_ok());
        missing(registry.connection_protocol(id), id);
    }
}

#[test]
fn http_queues_are_fifo_and_keep_each_response_channel() {
    let registry = ListenerRegistry::default();
    for protocol in [
        ConnectionProtocol::Http,
        ConnectionProtocol::Http2,
        ConnectionProtocol::Http3,
    ] {
        let id = ConnectionId(29);
        register_pending(&registry, id, protocol);
        let mut receivers = Vec::new();
        for path in ["/first", "/second", "/third"] {
            let (request, receiver) = request(id, path);
            assert!(registry.enqueue_http_request(id, request).is_ok());
            receivers.push(receiver);
        }
        if let Some(stats) = registry.connection_stats(id).unwrap() {
            let event = stats.finalize(id, HttpConnectionCloseReason::Graceful, None);
            assert_eq!(event.backpressure_events, 2);
            assert_eq!(event.max_backpressure_depth, 3);
        }
        for (index, path) in ["/first", "/second", "/third"].into_iter().enumerate() {
            let pending = registry.poll_http_request(id);
            assert!(matches!(&pending, Ok(Some(_))));
            let (summary, handle) = pending.unwrap().unwrap();
            assert_eq!(summary.path.as_ref(), path.as_bytes());
            assert!(handle
                .respond(response(201 + index as i32, path.as_bytes()))
                .is_ok());
            let delivered = receivers[index].try_recv();
            assert!(delivered.is_ok());
            let delivered = delivered.unwrap();
            assert_eq!(delivered.status, 201 + index as i32);
            assert_eq!(
                delivered.headers,
                [("content-type".into(), "application/octet-stream".into())]
            );
            assert!(
                matches!(delivered.body, HttpResponseBody::Buffered(bytes) if bytes == path.as_bytes())
            );
            for receiver in receivers.iter_mut().skip(index + 1) {
                assert!(matches!(
                    receiver.try_recv(),
                    Err(oneshot::error::TryRecvError::Empty)
                ));
            }
        }
        assert!(matches!(registry.poll_http_request(id), Ok(None)));
        assert!(registry.close_connection(id).is_ok());
    }
}

#[test]
fn close_cancels_queued_requests_but_preserves_an_already_taken_response() {
    for protocol in [
        ConnectionProtocol::Http,
        ConnectionProtocol::Http2,
        ConnectionProtocol::Http3,
    ] {
        let registry = ListenerRegistry::default();
        let id = ConnectionId(42);
        register_pending(&registry, id, protocol);
        let (first, mut first_receiver) = request(id, "/taken");
        let (second, mut second_receiver) = request(id, "/queued");
        assert!(registry.enqueue_http_request(id, first).is_ok());
        assert!(registry.enqueue_http_request(id, second).is_ok());
        let taken = registry.poll_http_request(id);
        assert!(matches!(&taken, Ok(Some(_))));
        let (_, handle) = taken.unwrap().unwrap();
        assert!(registry.close_connection(id).is_ok());
        assert!(matches!(
            second_receiver.try_recv(),
            Err(oneshot::error::TryRecvError::Closed)
        ));
        missing(registry.close_connection(id), id);
        missing(registry.poll_http_request(id), id);
        assert!(matches!(
            first_receiver.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ));
        assert!(handle.respond(response(202, b"owned")).is_ok());
        let delivered = first_receiver.try_recv();
        assert!(delivered.is_ok());
        assert_eq!(delivered.unwrap().status, 202);
    }
}

#[test]
fn pending_websocket_rejects_http_and_retains_handshake_state() {
    let registry = ListenerRegistry::default();
    let id = ConnectionId(73);
    let protocol = ConnectionProtocol::WebSocket;
    register_pending(&registry, id, protocol);
    let (request, mut receiver) = request(id, "/wrong-protocol");
    unsupported(registry.enqueue_http_request(id, request), id, protocol);
    assert!(matches!(
        receiver.try_recv(),
        Err(oneshot::error::TryRecvError::Closed)
    ));
    unsupported(registry.poll_http_request(id), id, protocol);
    unsupported(registry.take_http2_handshake(id), id, protocol);
    unsupported(registry.take_http3_handshake(id), id, protocol);
    unsupported(registry.http3_connection(id), id, protocol);
    unsupported(registry.poll_http3_stream(id), id, protocol);
    unsupported(registry.message_frames(id), id, protocol);
    unsupported(
        registry.enqueue_frame(id, OutboundFrame::message(Bytes::new())),
        id,
        protocol,
    );
    unsupported(
        registry.enqueue_file_frame(id, OutboundFrame::message(Bytes::new())),
        id,
        protocol,
    );
    unsupported(registry.connection_exponent(id), id, protocol);
    assert!(!registry.connection_supports_file_segments(id).unwrap());
    assert!(matches!(
        registry.connection_websocket_protocol(id),
        Ok(None)
    ));
    assert!(
        matches!(registry.take_websocket_handshake(id), Err(Error::HandshakeAlreadyTaken(actual)) if actual == id)
    );
    assert!(registry.close_connection(id).is_ok());
}

#[test]
fn failed_response_reports_the_owning_connection() {
    for id in [ConnectionId(0), ConnectionId(83), ConnectionId(u32::MAX)] {
        let (request, receiver) = request(id, "/gone");
        drop(receiver);
        assert!(matches!(request.response.respond(response(204, b"")),
            Err(Error::Http3ResponseSend(actual)) if actual == id));
    }
}

#[test]
fn inline_body_slices_preserve_owner_and_clamp_overflow() {
    for body in [
        HttpBodyHandle::from_bytes(vec![0, 127, 128, 255]),
        HttpBodyHandle::from_inline(Bytes::from_static(&[0, 127, 128, 255])),
    ] {
        let retained = body.clone();
        drop(body);
        assert_eq!(retained.len(), 4);
        assert!(!retained.is_empty());
        assert!(!retained.is_streaming());
        assert!(retained.inline_bytes().is_some());
        assert_eq!(
            retained.inline_bytes().unwrap().as_ref(),
            &[0, 127, 128, 255]
        );
        let pointer = retained.inline_bytes().unwrap().as_ptr();
        for (offset, length, expected) in [
            (0, 0, 0),
            (0, 99, 4),
            (1, 2, 2),
            (3, usize::MAX, 1),
            (4, 1, 0),
        ] {
            let slice = retained.slice(offset, length);
            assert!(slice.is_some());
            let slice = slice.unwrap();
            assert_eq!(slice.len, expected);
            assert_eq!(slice.ptr, pointer.wrapping_add(offset));
        }
        assert!(retained.slice(5, 0).is_none());
        assert!(retained.slice(usize::MAX, 1).is_none());
        assert!(matches!(retained.stream_read(1), Ok(None)));
        retained.request_finish();
        assert_eq!(
            retained.inline_bytes().unwrap().as_ref(),
            &[0, 127, 128, 255]
        );
    }
    for empty in [
        HttpBodyHandle::empty(),
        HttpBodyHandle::from_bytes(vec![]),
        HttpBodyHandle::from_inline(Bytes::new()),
    ] {
        assert!(empty.is_empty());
        assert_eq!(empty.len(), 0);
        let slice = empty.slice(0, usize::MAX);
        assert!(slice.is_some());
        assert_eq!(slice.unwrap().len, 0);
        assert!(empty.slice(1, 0).is_none());
    }
}

#[test]
fn streaming_body_handles_forward_reads_completion_and_errors() {
    let state = StreamingBodyState::new(4);
    let bytes = Bytes::from_static(&[0, 127, 128, 255]);
    let pointer = bytes.as_ptr();
    state.enqueue_bytes(bytes);
    state.mark_finished();
    let body = HttpBodyHandle::streaming(Arc::clone(&state));
    assert!(body.is_streaming());
    assert!(!body.is_empty());
    assert_eq!(body.len(), 4);
    assert!(body.inline_bytes().is_none());
    assert!(body.slice(0, 4).is_none());
    assert!(!state.finish_requested());
    body.request_finish();
    assert!(state.finish_requested());
    let first = body.stream_read(2);
    assert!(matches!(&first, Ok(Some(_))));
    let first = first.unwrap().unwrap();
    assert_eq!(first.len, 2);
    assert_eq!(first.ptr, pointer);
    let second = body.stream_read(usize::MAX);
    assert!(matches!(&second, Ok(Some(_))));
    let second = second.unwrap().unwrap();
    assert_eq!(second.len, 2);
    assert_eq!(second.ptr, pointer.wrapping_add(2));
    assert!(matches!(body.stream_read(1), Ok(None)));
    let failed = StreamingBodyState::new(0);
    failed.mark_error("body read failed".into());
    let body = HttpBodyHandle::streaming(failed);
    assert!(
        matches!(body.stream_read(1), Err(StreamingError::Io(message)) if message == "body read failed")
    );
}

#[cfg(any(unix, windows))]
#[tokio::test]
async fn active_wamp_records_preserve_frames_backpressure_and_close_semantics() {
    for (protocol, files) in [
        (ConnectionProtocol::RawSocket, false),
        (ConnectionProtocol::RawSocket, true),
        (ConnectionProtocol::WebSocket, true),
    ] {
        let registry = ListenerRegistry::default();
        let id = ConnectionId(94);
        let (frame_tx, frame_rx) = mpsc::channel(1);
        let frames = Arc::new(Mutex::new(frame_rx));
        let (send_tx, mut send_rx) = mpsc::channel(1);
        let reader = tokio::spawn(std::future::pending::<()>());
        let writer = tokio::spawn(std::future::pending::<()>());
        let heartbeat = tokio::spawn(std::future::pending::<()>());
        let record = if protocol == ConnectionProtocol::RawSocket {
            ConnectionRecord::RawSocket {
                _serializer: rawsocket::Serializer::Json,
                max_exponent: 19,
                supports_file_segments: files,
                frames: Arc::clone(&frames),
                reader_abort: reader.abort_handle(),
                writer_abort: writer.abort_handle(),
                heartbeat_abort: Some(heartbeat.abort_handle()),
                send_tx,
            }
        } else {
            ConnectionRecord::WebSocket {
                _serializer: rawsocket::Serializer::Json,
                frames: Arc::clone(&frames),
                reader_abort: reader.abort_handle(),
                writer_abort: writer.abort_handle(),
                heartbeat_abort: Some(heartbeat.abort_handle()),
                send_tx,
            }
        };
        registry.connections.lock().unwrap().insert(
            id,
            ConnectionEntry {
                listener_id: ListenerId(17),
                peer_addr: SocketAddr::from(([127, 0, 0, 1], 12345)),
                protocol,
                websocket_protocol: (protocol == ConnectionProtocol::WebSocket)
                    .then(|| "wamp.2.json".into()),
                endpoint_config: endpoint(),
                stats: None,
                record,
            },
        );
        assert_eq!(
            registry.connection_supports_file_segments(id).ok(),
            Some(files)
        );
        if protocol == ConnectionProtocol::RawSocket {
            assert_eq!(registry.connection_exponent(id).ok(), Some(19));
        } else {
            assert_eq!(
                registry
                    .connection_websocket_protocol(id)
                    .ok()
                    .flatten()
                    .as_deref(),
                Some("wamp.2.json")
            );
        }
        let registered_frames = registry.message_frames(id);
        assert!(registered_frames.is_ok());
        assert!(Arc::ptr_eq(&frames, &registered_frames.unwrap()));
        assert!(matches!(registry.poll_message(id), Ok(None)));
        let parsed = wamp::parse_message(
            rawsocket::Serializer::Json,
            Bytes::from_static(b"[6,{},\"wamp.close.normal\"]"),
        );
        assert!(parsed.is_ok());
        assert!(frame_tx.try_send(parsed.unwrap()).is_ok());
        let message = registry.poll_message(id);
        assert!(matches!(&message, Ok(Some(_))));
        assert_eq!(message.unwrap().unwrap().raw.len(), 26);
        drop(frame_tx);
        assert!(matches!(registry.poll_message(id), Ok(None)));
        assert!(registry
            .enqueue_frame(id, OutboundFrame::message(Bytes::from_static(b"first")))
            .is_ok());
        assert!(
            matches!(registry.enqueue_frame(id, OutboundFrame::message(Bytes::new())), Err(Error::SendQueueFull(actual)) if actual == id)
        );
        let delivered = send_rx.try_recv();
        assert!(delivered.is_ok());
        let delivered = delivered.unwrap();
        assert_eq!(delivered.payload_len, 5);
        assert_eq!(delivered.segments, [Bytes::from_static(b"first")]);
        let file_result =
            registry.enqueue_file_frame(id, OutboundFrame::message(Bytes::from_static(b"file")));
        if files {
            assert!(file_result.is_ok());
            assert!(
                matches!(registry.enqueue_file_frame(id, OutboundFrame::message(Bytes::new())), Err(Error::SendQueueFull(actual)) if actual == id)
            );
            assert_eq!(
                send_rx.try_recv().unwrap().segments,
                [Bytes::from_static(b"file")]
            );
        } else {
            unsupported(file_result, id, protocol);
            assert!(matches!(send_rx.try_recv(), Err(TryRecvError::Empty)));
        }
        drop(send_rx);
        missing(
            registry.enqueue_frame(id, OutboundFrame::message(Bytes::new())),
            id,
        );
        if files {
            missing(
                registry.enqueue_file_frame(id, OutboundFrame::message(Bytes::new())),
                id,
            );
        }
        assert!(registry.close_connection(id).is_ok());
        let closed_reader = tokio::time::timeout(Duration::from_secs(1), reader).await;
        assert!(closed_reader.is_ok());
        assert!(closed_reader
            .unwrap()
            .is_err_and(|error| error.is_cancelled()));
        let closed_heartbeat = tokio::time::timeout(Duration::from_secs(1), heartbeat).await;
        assert!(closed_heartbeat.is_ok());
        assert!(closed_heartbeat
            .unwrap()
            .is_err_and(|error| error.is_cancelled()));
        if protocol == ConnectionProtocol::WebSocket {
            // Graceful close leaves the writer to flush its closed send channel.
            assert!(!writer.is_finished());
            writer.abort();
        }
        let closed_writer = tokio::time::timeout(Duration::from_secs(1), writer).await;
        assert!(closed_writer.is_ok());
        assert!(closed_writer
            .unwrap()
            .is_err_and(|error| error.is_cancelled()));
        missing(registry.connection_protocol(id), id);
    }
}
