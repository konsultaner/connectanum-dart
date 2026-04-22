use crate::config::{EndpointRuntimeConfig, TransportProtocol};

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const ENABLE_KTLS_ENV: &str = "CONNECTANUM_ENABLE_KTLS";
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const REQUIRE_KTLS_ENV: &str = "CONNECTANUM_REQUIRE_KTLS";

use std::io::{self, BufRead};
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

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn drain_buffered_plaintext(
    session: &mut rustls::ServerConnection,
) -> Result<Option<Vec<u8>>, String> {
    let mut plaintext = Vec::new();

    loop {
        let chunk_len = {
            let chunk = match session.reader().into_first_chunk() {
                Ok(chunk) => chunk,
                Err(err) if err.kind() == io::ErrorKind::WouldBlock => break,
                Err(err) => {
                    return Err(format!(
                        "failed to drain buffered plaintext before Linux kTLS handoff: {err}"
                    ))
                }
            };

            if chunk.is_empty() {
                break;
            }

            plaintext.extend_from_slice(chunk);
            chunk.len()
        };

        session.reader().consume(chunk_len);
    }

    Ok((!plaintext.is_empty()).then_some(plaintext))
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
    let buffered_plaintext = drain_buffered_plaintext(&mut session)
        .map(|buffer| buffer.map(ktls_core::Buffer::from))
        .map_err(|err| {
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
    let secrets = ktls_core::ExtractedSecrets::try_from(secrets).map_err(|err| {
        disable_server_offload();
        format!("failed to adapt rustls secrets for Linux kTLS handoff: {err}")
    })?;
    // `ktls-stream` expects TLS ULP setup on a connected socket. The accepted
    // TCP stream is only ready for that once the TLS handshake has completed,
    // so the dummy-session helper performs the ULP setup here instead of on
    // the pre-handshake socket.
    let stream = ktls_stream::Stream::new_dummy(stream, secrets, dummy_session, buffered_plaintext)
        .map_err(|err| {
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
    use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
    use rustls::pki_types::{PrivateKeyDer, ServerName};
    use rustls::{ClientConfig as RustlsClientConfig, ServerConfig as RustlsServerConfig};
    use rustls_pemfile::{certs, pkcs8_private_keys};
    use std::{
        io::{Cursor, Write},
        sync::Arc,
        time::Duration,
    };

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

    #[test]
    fn drain_buffered_plaintext_preserves_post_handshake_http2_preface() {
        let server_cert_pem = include_str!("../../../bench/bench_tls.crt");
        let server_key_pem = include_str!("../../../bench/bench_tls.key");
        let cert_chain = parse_cert_chain(server_cert_pem);
        let server_key = parse_private_key(server_key_pem);

        let server_config = Arc::new(
            RustlsServerConfig::builder()
                .with_no_client_auth()
                .with_single_cert(cert_chain, server_key)
                .expect("server config"),
        );
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let verifier = Arc::new(NoCertificateVerification {
            schemes: provider
                .signature_verification_algorithms
                .supported_schemes(),
        });
        let client_config = Arc::new(
            RustlsClientConfig::builder_with_provider(Arc::clone(&provider))
                .with_protocol_versions(&[&rustls::version::TLS13])
                .expect("client protocol versions")
                .dangerous()
                .with_custom_certificate_verifier(verifier)
                .with_no_client_auth(),
        );

        let mut server = rustls::ServerConnection::new(server_config).expect("server connection");
        let mut client = rustls::ClientConnection::new(
            client_config,
            ServerName::try_from("localhost").expect("server name"),
        )
        .expect("client connection");

        complete_handshake(&mut client, &mut server);

        let http2_preface = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
        client
            .writer()
            .write_all(http2_preface)
            .expect("queue application data");
        pump_client_to_server(&mut client, &mut server);

        let drained = drain_buffered_plaintext(&mut server)
            .expect("drain buffered plaintext")
            .expect("buffered plaintext");
        assert_eq!(drained, http2_preface);
        assert!(drain_buffered_plaintext(&mut server)
            .expect("drain after consume")
            .is_none());
    }

    #[derive(Debug)]
    struct NoCertificateVerification {
        schemes: Vec<rustls::SignatureScheme>,
    }

    impl ServerCertVerifier for NoCertificateVerification {
        fn verify_server_cert(
            &self,
            _end_entity: &rustls::pki_types::CertificateDer<'_>,
            _intermediates: &[rustls::pki_types::CertificateDer<'_>],
            _server_name: &ServerName<'_>,
            _ocsp_response: &[u8],
            _now: rustls::pki_types::UnixTime,
        ) -> Result<ServerCertVerified, rustls::Error> {
            Ok(ServerCertVerified::assertion())
        }

        fn verify_tls12_signature(
            &self,
            _message: &[u8],
            _cert: &rustls::pki_types::CertificateDer<'_>,
            _dss: &rustls::DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, rustls::Error> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn verify_tls13_signature(
            &self,
            _message: &[u8],
            _cert: &rustls::pki_types::CertificateDer<'_>,
            _dss: &rustls::DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, rustls::Error> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
            self.schemes.clone()
        }
    }

    fn parse_cert_chain(pem: &str) -> Vec<rustls::pki_types::CertificateDer<'static>> {
        let mut reader = Cursor::new(pem.as_bytes());
        certs(&mut reader)
            .collect::<Result<Vec<_>, _>>()
            .expect("parse certificate chain")
    }

    fn parse_private_key(pem: &str) -> PrivateKeyDer<'static> {
        let mut reader = Cursor::new(pem.as_bytes());
        pkcs8_private_keys(&mut reader)
            .collect::<Result<Vec<_>, _>>()
            .expect("parse private key")
            .into_iter()
            .next()
            .expect("private key present")
            .into()
    }

    fn complete_handshake(
        client: &mut rustls::ClientConnection,
        server: &mut rustls::ServerConnection,
    ) {
        while client.is_handshaking() || server.is_handshaking() {
            pump_client_to_server(client, server);
            pump_server_to_client(server, client);
        }
    }

    fn pump_client_to_server(
        client: &mut rustls::ClientConnection,
        server: &mut rustls::ServerConnection,
    ) {
        let mut tls_bytes = Vec::new();
        while client.wants_write() {
            client
                .write_tls(&mut tls_bytes)
                .expect("write client handshake bytes");
        }
        if tls_bytes.is_empty() {
            return;
        }
        let mut cursor = Cursor::new(tls_bytes);
        server
            .read_tls(&mut cursor)
            .expect("read client handshake bytes");
        server
            .process_new_packets()
            .expect("process client packets");
    }

    fn pump_server_to_client(
        server: &mut rustls::ServerConnection,
        client: &mut rustls::ClientConnection,
    ) {
        let mut tls_bytes = Vec::new();
        while server.wants_write() {
            server
                .write_tls(&mut tls_bytes)
                .expect("write server handshake bytes");
        }
        if tls_bytes.is_empty() {
            return;
        }
        let mut cursor = Cursor::new(tls_bytes);
        client
            .read_tls(&mut cursor)
            .expect("read server handshake bytes");
        client
            .process_new_packets()
            .expect("process server packets");
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
