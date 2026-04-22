use crate::config::{EndpointRuntimeConfig, TransportProtocol};

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const ENABLE_KTLS_ENV: &str = "CONNECTANUM_ENABLE_KTLS";
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const REQUIRE_KTLS_ENV: &str = "CONNECTANUM_REQUIRE_KTLS";

#[cfg(target_os = "linux")]
use std::sync::Arc;
#[cfg(target_os = "linux")]
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(target_os = "linux")]
use tokio::{io::AsyncWriteExt, net::TcpStream};

#[cfg(target_os = "linux")]
static SERVER_OFFLOAD_DISABLED: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "linux")]
const UNBUFFERED_TLS_READ_CHUNK: usize = 16 * 1024;
#[cfg(target_os = "linux")]
const UNBUFFERED_TLS_WRITE_CHUNK: usize = 16 * 1024;

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ServerKtlsMode {
    Disabled,
    Try,
    Require,
}

pub(crate) fn secret_extraction_requested() -> bool {
    #[cfg(target_os = "linux")]
    {
        !matches!(server_mode(), ServerKtlsMode::Disabled)
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn server_mode_from_env(enable_raw: Option<&str>, require_raw: Option<&str>) -> ServerKtlsMode {
    if !parse_enabled_flag(enable_raw) {
        ServerKtlsMode::Disabled
    } else if parse_enabled_flag(require_raw) {
        ServerKtlsMode::Require
    } else {
        ServerKtlsMode::Try
    }
}

#[cfg(target_os = "linux")]
fn server_mode() -> ServerKtlsMode {
    server_mode_from_env(
        std::env::var(ENABLE_KTLS_ENV).ok().as_deref(),
        std::env::var(REQUIRE_KTLS_ENV).ok().as_deref(),
    )
}

#[cfg(not(target_os = "linux"))]
fn server_mode() -> ServerKtlsMode {
    ServerKtlsMode::Disabled
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn server_http_eligible(endpoint: &EndpointRuntimeConfig) -> bool {
    endpoint.supports_protocol(TransportProtocol::Http)
        || endpoint.supports_protocol(TransportProtocol::Http2)
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) fn server_runtime_requested(endpoint: &EndpointRuntimeConfig) -> bool {
    #[cfg(target_os = "linux")]
    {
        if !server_http_eligible(endpoint) {
            return false;
        }

        match server_mode() {
            ServerKtlsMode::Disabled => false,
            ServerKtlsMode::Try => !SERVER_OFFLOAD_DISABLED.load(Ordering::Relaxed),
            ServerKtlsMode::Require => true,
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = endpoint;
        false
    }
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) fn server_runtime_required(endpoint: &EndpointRuntimeConfig) -> bool {
    server_http_eligible(endpoint) && matches!(server_mode(), ServerKtlsMode::Require)
}

#[cfg(target_os = "linux")]
fn disable_server_offload() {
    if !matches!(server_mode(), ServerKtlsMode::Require) {
        SERVER_OFFLOAD_DISABLED.store(true, Ordering::Relaxed);
    }
}

#[cfg(target_os = "linux")]
fn discard_front(buffer: &mut Vec<u8>, discard: usize) {
    if discard == 0 {
        return;
    }
    buffer.drain(..discard);
}

#[cfg(target_os = "linux")]
fn encode_unbuffered_tls(
    mut encode: rustls::unbuffered::EncodeTlsData<'_, rustls::server::ServerConnectionData>,
    outgoing_tls: &mut Vec<u8>,
) -> Result<usize, String> {
    loop {
        match encode.encode(outgoing_tls.as_mut_slice()) {
            Ok(encoded) => return Ok(encoded),
            Err(rustls::unbuffered::EncodeError::InsufficientSize(required)) => {
                outgoing_tls.resize(required.required_size, 0);
            }
            Err(err) => {
                return Err(format!(
                    "failed to encode TLS handshake data for Linux kTLS handoff: {err}"
                ));
            }
        }
    }
}

#[cfg(target_os = "linux")]
fn negotiated_alpn(
    session: &rustls::server::UnbufferedServerConnection,
) -> Option<String> {
    session
        .alpn_protocol()
        .map(|bytes| String::from_utf8_lossy(bytes).to_string())
}

#[cfg(target_os = "linux")]
fn into_plaintext_buffer(bytes: Vec<u8>) -> Option<ktls_core::Buffer> {
    (!bytes.is_empty()).then_some(ktls_core::Buffer::from(bytes))
}

#[cfg(target_os = "linux")]
pub(crate) async fn accept_server_stream(
    config: Arc<rustls::ServerConfig>,
    mut stream: TcpStream,
) -> Result<crate::io_stream::IoStream, String> {
    let mut session = rustls::server::UnbufferedServerConnection::new(config).map_err(|err| {
        disable_server_offload();
        format!("failed to initialize unbuffered TLS server for Linux kTLS handoff: {err}")
    })?;
    let mut incoming_tls = Vec::new();
    let mut outgoing_tls = vec![0; UNBUFFERED_TLS_WRITE_CHUNK];
    let mut pending_outgoing_len: Option<usize> = None;
    let mut buffered_plaintext = Vec::new();
    let mut read_buf = [0u8; UNBUFFERED_TLS_READ_CHUNK];

    loop {
        let status = session.process_tls_records(incoming_tls.as_mut_slice());
        let mut discard = status.discard;
        let state = status.state.map_err(|err| {
            disable_server_offload();
            format!("failed to process TLS handshake for Linux kTLS handoff: {err}")
        })?;
        match state {
            rustls::unbuffered::ConnectionState::EncodeTlsData(encode) => {
                let encoded = encode_unbuffered_tls(encode, &mut outgoing_tls).map_err(|err| {
                    disable_server_offload();
                    err
                })?;
                discard_front(&mut incoming_tls, discard);
                pending_outgoing_len = Some(encoded);
            }
            rustls::unbuffered::ConnectionState::TransmitTlsData(transmit) => {
                discard_front(&mut incoming_tls, discard);
                let encoded = pending_outgoing_len.take().ok_or_else(|| {
                    disable_server_offload();
                    "rustls requested TLS transmit without encoded handshake bytes".to_string()
                })?;
                stream.write_all(&outgoing_tls[..encoded]).await.map_err(|err| {
                    disable_server_offload();
                    format!(
                        "failed to transmit TLS handshake bytes before Linux kTLS handoff: {err}"
                    )
                })?;
                transmit.done();
            }
            rustls::unbuffered::ConnectionState::BlockedHandshake => {
                discard_front(&mut incoming_tls, discard);
                let read = tokio::io::AsyncReadExt::read(&mut stream, &mut read_buf)
                    .await
                    .map_err(|err| {
                        disable_server_offload();
                        format!(
                            "failed to read TLS handshake bytes before Linux kTLS handoff: {err}"
                        )
                    })?;
                if read == 0 {
                    disable_server_offload();
                    return Err("tls handshake eof before Linux kTLS handoff".into());
                }
                incoming_tls.extend_from_slice(&read_buf[..read]);
            }
            rustls::unbuffered::ConnectionState::ReadTraffic(mut read_traffic) => {
                while let Some(record) = read_traffic.next_record() {
                    let record = record.map_err(|err| {
                        disable_server_offload();
                        format!(
                            "failed to decode post-handshake application data before Linux kTLS handoff: {err}"
                        )
                    })?;
                    discard += record.discard;
                    buffered_plaintext.extend_from_slice(record.payload);
                }
                drop(read_traffic);
                discard_front(&mut incoming_tls, discard);
            }
            rustls::unbuffered::ConnectionState::ReadEarlyData(mut early_data) => {
                while let Some(record) = early_data.next_record() {
                    let record = record.map_err(|err| {
                        disable_server_offload();
                        format!(
                            "failed to decode early data before Linux kTLS handoff: {err}"
                        )
                    })?;
                    discard += record.discard;
                    buffered_plaintext.extend_from_slice(record.payload);
                }
                drop(early_data);
                discard_front(&mut incoming_tls, discard);
            }
            rustls::unbuffered::ConnectionState::WriteTraffic(write_traffic) => {
                discard_front(&mut incoming_tls, discard);
                drop(write_traffic);

                let negotiated_alpn = negotiated_alpn(&session);
                let (secrets, kernel_connection) = session
                    .dangerous_into_kernel_connection()
                    .map_err(|err| {
                        disable_server_offload();
                        format!(
                            "failed to convert TLS session into Linux kTLS kernel connection: {err}"
                        )
                    })?;
                let secrets = ktls_core::ExtractedSecrets::try_from(secrets).map_err(|err| {
                    disable_server_offload();
                    format!("failed to adapt rustls secrets for Linux kTLS handoff: {err}")
                })?;
                ktls_core::setup_ulp(&stream).map_err(|err| {
                    disable_server_offload();
                    format!("failed to set TLS ULP before Linux kTLS handoff: {err}")
                })?;
                let stream = ktls_stream::Stream::new(
                    stream,
                    secrets,
                    kernel_connection,
                    into_plaintext_buffer(buffered_plaintext),
                )
                .map_err(|err| {
                    disable_server_offload();
                    format!("failed to initialize Linux kTLS stream: {err}")
                })?;
                return Ok(crate::io_stream::IoStream::ktls_server(
                    stream,
                    negotiated_alpn,
                ));
            }
            rustls::unbuffered::ConnectionState::PeerClosed => {
                discard_front(&mut incoming_tls, discard);
                disable_server_offload();
                return Err("peer closed during Linux kTLS handshake handoff".into());
            }
            rustls::unbuffered::ConnectionState::Closed => {
                discard_front(&mut incoming_tls, discard);
                disable_server_offload();
                return Err("connection closed during Linux kTLS handshake handoff".into());
            }
            _ => {
                discard_front(&mut incoming_tls, discard);
                disable_server_offload();
                return Err("unexpected rustls unbuffered state during Linux kTLS handoff".into());
            }
        }
    }
}

#[cfg(not(target_os = "linux"))]
pub(crate) async fn accept_server_stream(
    config: std::sync::Arc<rustls::ServerConfig>,
    stream: tokio::net::TcpStream,
) -> Result<crate::io_stream::IoStream, String> {
    let _ = config;
    let _ = stream;
    Err("kTLS server handoff is unavailable on this platform".into())
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn parse_enabled_flag(raw: Option<&str>) -> bool {
    matches!(
        raw.map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| value.to_ascii_lowercase()),
        Some(value) if matches!(value.as_str(), "1" | "true" | "yes" | "on")
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{EndpointRuntimeConfig, TlsMode};
    use std::time::Duration;

    #[test]
    fn parse_enabled_flag_accepts_common_truthy_values() {
        for value in ["1", "true", "TRUE", "yes", "on"] {
            assert!(
                parse_enabled_flag(Some(value)),
                "expected {value} to enable kTLS"
            );
        }
    }

    #[test]
    fn parse_enabled_flag_rejects_empty_and_falsey_values() {
        for value in [
            None,
            Some(""),
            Some("0"),
            Some("false"),
            Some("off"),
            Some("no"),
        ] {
            assert!(
                !parse_enabled_flag(value),
                "expected {value:?} to disable kTLS"
            );
        }
    }

    #[test]
    fn server_mode_requires_enable_flag() {
        assert_eq!(
            server_mode_from_env(None, Some("1")),
            ServerKtlsMode::Disabled,
        );
        assert_eq!(
            server_mode_from_env(Some("0"), Some("1")),
            ServerKtlsMode::Disabled,
        );
    }

    #[test]
    fn server_mode_distinguishes_try_and_require_modes() {
        assert_eq!(server_mode_from_env(Some("1"), None), ServerKtlsMode::Try,);
        assert_eq!(
            server_mode_from_env(Some("true"), Some("1")),
            ServerKtlsMode::Require,
        );
    }

    #[test]
    fn server_http_eligible_requires_http_or_http2() {
        assert!(server_http_eligible(&endpoint_with_protocols(vec![
            TransportProtocol::Http
        ])));
        assert!(server_http_eligible(&endpoint_with_protocols(vec![
            TransportProtocol::Http2
        ])));
        assert!(!server_http_eligible(&endpoint_with_protocols(vec![
            TransportProtocol::Rawsocket
        ])));
        assert!(!server_http_eligible(&endpoint_with_protocols(vec![
            TransportProtocol::Websocket
        ])));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn discard_front_removes_prefix_bytes() {
        let mut buffer = b"abcdef".to_vec();
        discard_front(&mut buffer, 2);
        assert_eq!(buffer, b"cdef");
        discard_front(&mut buffer, 0);
        assert_eq!(buffer, b"cdef");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn into_plaintext_buffer_omits_empty_vectors() {
        assert!(into_plaintext_buffer(Vec::new()).is_none());
        assert!(into_plaintext_buffer(vec![1, 2, 3]).is_some());
    }

    fn endpoint_with_protocols(protocols: Vec<TransportProtocol>) -> EndpointRuntimeConfig {
        EndpointRuntimeConfig {
            host: "127.0.0.1".into(),
            port: 443,
            tls_mode: TlsMode::Native,
            client_auth: None,
            protocols,
            idle_timeout: None,
            heartbeat_interval: None,
            heartbeat_timeout: None,
            handshake_timeout: Duration::from_secs(5),
            max_http_content_length: None,
            max_rawsocket_size_exponent: 16,
            max_rawsocket_size: 1u64 << 16,
            max_upgrade_exponent: None,
            outbound_send_queue_capacity: 1024,
            websocket_path: None,
            sni_certificates: Vec::new(),
            http_routes: Vec::new(),
            http: None,
        }
    }
}
