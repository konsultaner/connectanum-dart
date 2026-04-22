use crate::config::{EndpointRuntimeConfig, TransportProtocol};

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const ENABLE_KTLS_ENV: &str = "CONNECTANUM_ENABLE_KTLS";
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const REQUIRE_KTLS_ENV: &str = "CONNECTANUM_REQUIRE_KTLS";

#[cfg(target_os = "linux")]
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(target_os = "linux")]
use tokio::{io::AsyncWriteExt, net::TcpStream};
#[cfg(target_os = "linux")]
use tokio_rustls::server::TlsStream as ServerTlsStream;

#[cfg(target_os = "linux")]
static SERVER_OFFLOAD_DISABLED: AtomicBool = AtomicBool::new(false);

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
fn dummy_server_session(
    protocol_version: Option<rustls::ProtocolVersion>,
) -> Result<ktls_core::DummyTlsSession, String> {
    match protocol_version {
        Some(rustls::ProtocolVersion::TLSv1_2) => Ok(ktls_core::DUMMY_TLS_12_SESSION_SERVER),
        Some(rustls::ProtocolVersion::TLSv1_3) => Ok(ktls_core::DUMMY_TLS_13_SESSION_SERVER),
        Some(version) => Err(format!(
            "unsupported TLS protocol version for Linux kTLS handoff: {version:?}"
        )),
        None => Err("missing negotiated TLS protocol version for Linux kTLS handoff".into()),
    }
}

#[cfg(target_os = "linux")]
pub(crate) async fn try_offload_server_stream(
    mut tls_stream: ServerTlsStream<TcpStream>,
) -> Result<crate::io_stream::IoStream, String> {
    let negotiated_alpn = tls_stream
        .get_ref()
        .1
        .alpn_protocol()
        .map(|bytes| String::from_utf8_lossy(bytes).to_string());
    tls_stream
        .flush()
        .await
        .map_err(|err| format!("failed to flush TLS handshake before kTLS handoff: {err}"))?;
    let (stream, session) = tls_stream.into_inner();
    let dummy_session = dummy_server_session(session.protocol_version()).map_err(|err| {
        disable_server_offload();
        err
    })?;
    // tokio-rustls returns a buffered ServerConnection. Its public API exposes
    // secret extraction, but not rustls's kernel-connection handoff, so the
    // prototype uses a dummy server-side session for short-lived validation
    // traffic instead of tracking TLS 1.3 key updates or ticket state.
    let secrets = session.dangerous_extract_secrets().map_err(|err| {
        disable_server_offload();
        format!("failed to extract TLS secrets for Linux kTLS handoff: {err}")
    })?;
    // `ktls-stream` expects TLS ULP setup on a connected socket. The accepted
    // TCP stream is only ready for that once the TLS handshake has completed,
    // so the dummy-session helper performs the ULP setup here instead of on
    // the pre-handshake socket.
    let stream = ktls_stream::Stream::new_dummy(stream, secrets, dummy_session, None).map_err(|err| {
        disable_server_offload();
        format!("failed to initialize Linux kTLS stream: {err}")
    })?;
    Ok(crate::io_stream::IoStream::ktls_server(
        stream,
        negotiated_alpn,
    ))
}

#[cfg(not(target_os = "linux"))]
pub(crate) async fn try_offload_server_stream(
    tls_stream: tokio_rustls::server::TlsStream<tokio::net::TcpStream>,
) -> Result<crate::io_stream::IoStream, String> {
    let _ = tls_stream;
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
