use crate::runtime::{self, CtHttpHandshakeInfo, CtHttpHeader, CtWebSocketHandshakeInfo};
use std::ffi::c_char;

// Check synchronous ownership postconditions before any peer read or join.
// A successful no-op must not hide behind a later network timeout.
pub(super) fn ct_http_response_send(
    handshake: i32,
    status: i32,
    headers: *const CtHttpHeader,
    headers_len: usize,
    body: *const u8,
    body_len: usize,
) -> i32 {
    let result =
        runtime::ct_http_response_send(handshake, status, headers, headers_len, body, body_len);
    if result == runtime::SUCCESS {
        assert_eq!(
            runtime::ct_http_handshake_get(handshake, &mut CtHttpHandshakeInfo::default()),
            runtime::ERR_INVALID_ARGUMENT,
            "successful HTTP response must consume its handshake"
        );
    }
    result
}

pub(super) fn ct_http_response_stream_finish(stream: i32) -> i32 {
    let result = runtime::ct_http_response_stream_finish(stream);
    if result == runtime::SUCCESS {
        let byte = [0u8];
        assert_eq!(
            runtime::ct_http_response_stream_write(stream, byte.as_ptr(), byte.len()),
            runtime::ERR_HANDLE_UNAVAILABLE,
            "finished response stream must reject further writes"
        );
    }
    result
}

pub(super) fn ct_connection_accept_websocket(
    connection: i32,
    handshake: i32,
    serializer: i32,
    protocol: *const c_char,
    protocol_len: i32,
) -> i32 {
    let result = runtime::ct_connection_accept_websocket(
        connection,
        handshake,
        serializer,
        protocol,
        protocol_len,
    );
    if result == runtime::SUCCESS {
        assert_eq!(
            runtime::ct_websocket_handshake_get(
                handshake,
                &mut CtWebSocketHandshakeInfo::default(),
            ),
            runtime::ERR_INVALID_ARGUMENT,
            "accepted WebSocket must consume its handshake"
        );
    }
    result
}
