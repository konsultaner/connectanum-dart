use crate::config::{EndpointRuntimeConfig, TransportProtocol};

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const ENABLE_KTLS_ENV: &str = "CONNECTANUM_ENABLE_KTLS";

#[cfg(target_os = "linux")]
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(target_os = "linux")]
use tokio::{io::AsyncWriteExt, net::TcpStream};
#[cfg(target_os = "linux")]
use tokio_rustls::server::TlsStream as ServerTlsStream;

#[cfg(target_os = "linux")]
static SERVER_OFFLOAD_DISABLED: AtomicBool = AtomicBool::new(false);

pub(crate) fn secret_extraction_requested() -> bool {
    #[cfg(target_os = "linux")]
    {
        parse_enabled_flag(std::env::var(ENABLE_KTLS_ENV).ok().as_deref())
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn server_http_eligible(endpoint: &EndpointRuntimeConfig) -> bool {
    endpoint.supports_protocol(TransportProtocol::Http)
        || endpoint.supports_protocol(TransportProtocol::Http2)
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn server_runtime_requested(endpoint: &EndpointRuntimeConfig) -> bool {
    #[cfg(target_os = "linux")]
    {
        secret_extraction_requested()
            && !SERVER_OFFLOAD_DISABLED.load(Ordering::Relaxed)
            && server_http_eligible(endpoint)
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = endpoint;
        false
    }
}

#[cfg(target_os = "linux")]
fn disable_server_offload() {
    SERVER_OFFLOAD_DISABLED.store(true, Ordering::Relaxed);
}

#[cfg(target_os = "linux")]
pub(crate) fn prepare_server_socket(
    endpoint: &EndpointRuntimeConfig,
    stream: &TcpStream,
) -> Result<bool, String> {
    if !server_runtime_requested(endpoint) {
        return Ok(false);
    }
    ktls_stream::prelude::setup_ulp(stream).map_err(|err| {
        disable_server_offload();
        err.to_string()
    })?;
    Ok(true)
}

#[cfg(not(target_os = "linux"))]
pub(crate) fn prepare_server_socket(
    endpoint: &EndpointRuntimeConfig,
    stream: &tokio::net::TcpStream,
) -> Result<bool, String> {
    let _ = (endpoint, stream);
    Ok(false)
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
    let (secrets, kernel_connection) =
        session.dangerous_into_kernel_connection().map_err(|err| {
            disable_server_offload();
            format!("failed to extract TLS kernel connection state: {err}")
        })?;
    let stream =
        ktls_stream::Stream::new(stream, secrets, kernel_connection, None).map_err(|err| {
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
