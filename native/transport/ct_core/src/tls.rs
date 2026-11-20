use std::{io::Cursor, sync::Arc};

use rustls::{
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::ring::default_provider as ring_provider,
    pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime},
    server::{ClientHello, ResolvesServerCert, ResolvesServerCertUsingSni},
    sign::CertifiedKey,
    ClientConfig as RustlsClientConfig, RootCertStore, ServerConfig as RustlsServerConfig,
};
use rustls_native_certs::load_native_certs;
use rustls_pemfile::{certs as load_certs, pkcs8_private_keys, rsa_private_keys};
use tokio_rustls::{TlsAcceptor, TlsConnector};

use crate::{
    config::{ClientAuthMode, EndpointRuntimeConfig, TlsMode, TransportProtocol},
    ktls, Error,
};

fn default_provider() -> rustls::crypto::CryptoProvider {
    let mut provider = ring_provider();
    let accelerated = rustls::crypto::aws_lc_rs::default_provider();
    provider.cipher_suites = provider
        .cipher_suites
        .iter()
        .map(|original| {
            accelerated
                .cipher_suites
                .iter()
                .find(|candidate| candidate.suite() == original.suite())
                .copied()
                .unwrap_or(*original)
        })
        .collect();
    // Preserve the process's first explicit provider; otherwise keep ring's
    // exact algorithm selection with accelerated cipher-suite implementations.
    let _ = provider.clone().install_default();
    provider
}

#[derive(Debug)]
struct ResolverWithDefault {
    inner: ResolvesServerCertUsingSni,
    default_key: Arc<CertifiedKey>,
}

impl ResolvesServerCert for ResolverWithDefault {
    fn resolve(&self, client_hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        self.inner
            .resolve(client_hello)
            .or_else(|| Some(Arc::clone(&self.default_key)))
    }
}

pub(crate) fn build_tls_acceptor(
    endpoint: &EndpointRuntimeConfig,
) -> Result<Option<TlsAcceptor>, Error> {
    match endpoint.tls_mode {
        TlsMode::Disabled => return Ok(None),
        TlsMode::Dart => {
            return Err(Error::RouterConfigInvalid(format!(
                "endpoint {}:{} tls_mode 'dart' not supported yet",
                endpoint.host, endpoint.port
            )));
        }
        TlsMode::Native => {}
    }

    if endpoint.sni_certificates.is_empty() {
        return Err(Error::RouterConfigInvalid(format!(
            "endpoint {}:{} tls_mode 'native' requires at least one sni_certificates entry",
            endpoint.host, endpoint.port
        )));
    }

    let provider = default_provider();
    let mut sni = ResolvesServerCertUsingSni::new();
    let mut default_key: Option<Arc<CertifiedKey>> = None;

    for (index, entry) in endpoint.sni_certificates.iter().enumerate() {
        let (cert_chain, key_der) = parse_identity(entry, endpoint)?;
        let certified_key =
            CertifiedKey::from_der(cert_chain, key_der, &provider).map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} tls certificate invalid for {}: {}",
                    endpoint.host, endpoint.port, entry.hostname, err
                ))
            })?;
        if index == 0 {
            default_key = Some(Arc::new(certified_key.clone()));
        }
        sni.add(entry.hostname.as_str(), certified_key)
            .map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} tls SNI certificate invalid for {}: {}",
                    endpoint.host, endpoint.port, entry.hostname, err
                ))
            })?;
    }

    let default_key = default_key.expect("sni certificates checked non-empty");
    let resolver = ResolverWithDefault {
        inner: sni,
        default_key,
    };
    let mut config = match build_client_cert_verifier(endpoint, &provider)? {
        Some(verifier) => RustlsServerConfig::builder()
            .with_client_cert_verifier(verifier)
            .with_cert_resolver(Arc::new(resolver)),
        None => RustlsServerConfig::builder()
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(resolver)),
    };
    apply_server_tls_runtime_settings(&mut config, endpoint, ktls::secret_extraction_requested());

    Ok(Some(TlsAcceptor::from(Arc::new(config))))
}

fn apply_server_tls_runtime_settings(
    config: &mut RustlsServerConfig,
    endpoint: &EndpointRuntimeConfig,
    secret_extraction_requested: bool,
) {
    config.enable_secret_extraction = secret_extraction_requested;
    config.alpn_protocols = tcp_alpn_protocols(endpoint);

    if secret_extraction_requested {
        // The current Linux kTLS server path hands traffic off after the TLS
        // handshake and no longer keeps rustls around to emit post-handshake
        // TLS 1.3 session tickets, so suppress them on that prototype path.
        config.send_tls13_tickets = 0;
    }
}

#[derive(Debug)]
struct NoCertificateVerification {
    schemes: Vec<rustls::SignatureScheme>,
}

impl ServerCertVerifier for NoCertificateVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.schemes.clone()
    }
}

pub(crate) fn build_client_connector(
    allow_insecure: bool,
    alpn_protocols: &[Vec<u8>],
) -> Result<TlsConnector, Error> {
    let provider = Arc::new(default_provider());
    let mut config = if allow_insecure {
        let verifier = Arc::new(NoCertificateVerification {
            schemes: provider
                .signature_verification_algorithms
                .supported_schemes(),
        });
        RustlsClientConfig::builder_with_provider(Arc::clone(&provider))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "client tls protocol configuration invalid: {}",
                    err
                ))
            })?
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_no_client_auth()
    } else {
        let mut roots = RootCertStore::empty();
        let certs = load_native_certs();
        for cert in certs.certs {
            roots.add(cert).map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "failed to load native tls certificate store: {}",
                    err
                ))
            })?;
        }
        RustlsClientConfig::builder_with_provider(Arc::clone(&provider))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "client tls protocol configuration invalid: {}",
                    err
                ))
            })?
            .with_root_certificates(roots)
            .with_no_client_auth()
    };
    config.enable_secret_extraction = ktls::secret_extraction_requested();
    config.alpn_protocols = alpn_protocols.to_vec();
    Ok(TlsConnector::from(Arc::new(config)))
}

pub(crate) fn build_client_cert_verifier(
    endpoint: &EndpointRuntimeConfig,
    provider: &rustls::crypto::CryptoProvider,
) -> Result<Option<Arc<dyn rustls::server::danger::ClientCertVerifier>>, Error> {
    // HTTP/3 calls this before its first implicit rustls builder as well.
    let _ = default_provider();
    let Some(client_auth) = &endpoint.client_auth else {
        return Ok(None);
    };
    let mut reader = Cursor::new(client_auth.ca_certificates_pem.as_bytes());
    let certs = load_certs(&mut reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} failed to parse client_auth ca_certificates_pem: {}",
                endpoint.host, endpoint.port, err
            ))
        })?;
    let mut roots = RootCertStore::empty();
    let (added, _) = roots.add_parsable_certificates(certs);
    if added == 0 {
        return Err(Error::RouterConfigInvalid(format!(
            "endpoint {}:{} client_auth ca_certificates_pem did not contain valid certificates",
            endpoint.host, endpoint.port
        )));
    }
    let mut builder = rustls::server::WebPkiClientVerifier::builder_with_provider(
        Arc::new(roots),
        Arc::new(provider.clone()),
    );
    if client_auth.mode == ClientAuthMode::Optional {
        builder = builder.allow_unauthenticated();
    }
    let verifier = builder.build().map_err(|err| {
        Error::RouterConfigInvalid(format!(
            "endpoint {}:{} client_auth verifier invalid: {}",
            endpoint.host, endpoint.port, err
        ))
    })?;
    Ok(Some(verifier))
}

fn tcp_alpn_protocols(endpoint: &EndpointRuntimeConfig) -> Vec<Vec<u8>> {
    let mut tokens = Vec::new();
    if let Some(http) = endpoint.http_settings() {
        for token in &http.alpn {
            if token.eq_ignore_ascii_case("h3") || token.starts_with("h3-") {
                continue;
            }
            tokens.push(token.as_bytes().to_vec());
        }
    }
    if tokens.is_empty() {
        if endpoint.supports_protocol(TransportProtocol::Http2) {
            tokens.push(b"h2".to_vec());
        }
        if endpoint.supports_protocol(TransportProtocol::Http)
            || endpoint.supports_protocol(TransportProtocol::Websocket)
        {
            tokens.push(b"http/1.1".to_vec());
        }
    }
    tokens
}

fn parse_identity(
    entry: &crate::config::SniCertificate,
    endpoint: &EndpointRuntimeConfig,
) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>), Error> {
    let mut cert_reader = Cursor::new(entry.certificate_chain_pem.as_bytes());
    let certs = load_certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} failed to parse tls certificate for {}: {}",
                endpoint.host, endpoint.port, entry.hostname, err
            ))
        })?;
    if certs.is_empty() {
        return Err(Error::RouterConfigInvalid(format!(
            "endpoint {}:{} tls certificate chain empty for {}",
            endpoint.host, endpoint.port, entry.hostname
        )));
    }

    let private_key = {
        let mut key_reader = Cursor::new(entry.private_key_pem.as_bytes());
        let mut keys = pkcs8_private_keys(&mut key_reader)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} failed to parse pkcs8 key for tls {}: {}",
                    endpoint.host, endpoint.port, entry.hostname, err
                ))
            })?
            .into_iter()
            .map(|der| der.into())
            .collect::<Vec<_>>();
        if keys.is_empty() {
            let mut rsa_reader = Cursor::new(entry.private_key_pem.as_bytes());
            keys = rsa_private_keys(&mut rsa_reader)
                .collect::<Result<Vec<_>, _>>()
                .map_err(|err| {
                    Error::RouterConfigInvalid(format!(
                        "endpoint {}:{} failed to parse rsa key for tls {}: {}",
                        endpoint.host, endpoint.port, entry.hostname, err
                    ))
                })?
                .into_iter()
                .map(|der| der.into())
                .collect();
        }
        keys.into_iter().next().ok_or_else(|| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} tls private key missing for {}",
                endpoint.host, endpoint.port, entry.hostname
            ))
        })?
    };

    Ok((certs, private_key))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{EndpointRuntimeConfig, SniCertificate, TlsMode, TransportProtocol};
    use std::time::Duration;

    fn configuration_error<T>(result: Result<T, Error>, expected: &str) {
        assert!(
            matches!(&result, Err(Error::RouterConfigInvalid(_))),
            "expected a TLS configuration rejection: {expected}"
        );
        if let Err(Error::RouterConfigInvalid(message)) = result {
            assert!(message.contains("127.0.0.1:443"), "{message}");
            assert!(message.contains(expected), "{message}");
        }
    }

    #[test]
    fn accelerated_provider_preserves_ring_algorithm_policy() {
        let before = ring_provider();
        let after = default_provider();
        assert_eq!(
            before
                .cipher_suites
                .iter()
                .map(|suite| suite.suite())
                .collect::<Vec<_>>(),
            after
                .cipher_suites
                .iter()
                .map(|suite| suite.suite())
                .collect::<Vec<_>>()
        );
        assert_eq!(before.kx_groups.len(), after.kx_groups.len());
        for (expected, actual) in before.kx_groups.iter().zip(&after.kx_groups) {
            assert!(std::ptr::eq(*expected, *actual));
        }
        assert!(std::ptr::eq(
            before.signature_verification_algorithms.all,
            after.signature_verification_algorithms.all
        ));
        assert!(std::ptr::eq(
            before.signature_verification_algorithms.mapping,
            after.signature_verification_algorithms.mapping
        ));
        assert!(std::ptr::eq(before.secure_random, after.secure_random));
        assert!(std::ptr::eq(before.key_provider, after.key_provider));
    }

    #[test]
    fn accelerated_records_interoperate_with_ring_for_each_tls13_cipher() {
        use rustls::{ClientConnection, Connection, ServerConnection};
        use std::io::{Read, Write};
        fn deliver(source: &mut Connection, target: &mut Connection) {
            let mut wire = Vec::new();
            while source.wants_write() {
                source.write_tls(&mut wire).unwrap();
            }
            let mut cursor = Cursor::new(wire);
            while cursor.position() < cursor.get_ref().len() as u64 {
                assert!(target.read_tls(&mut cursor).unwrap() > 0);
                target.process_new_packets().unwrap();
            }
        }
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let cert = identity.cert.der().clone();
        for suite in ring_provider()
            .cipher_suites
            .into_iter()
            .filter(|suite| suite.tls13().is_some())
        {
            for accelerated_server in [false, true] {
                let mut client_provider = if accelerated_server {
                    ring_provider()
                } else {
                    default_provider()
                };
                let mut server_provider = if accelerated_server {
                    default_provider()
                } else {
                    ring_provider()
                };
                client_provider
                    .cipher_suites
                    .retain(|candidate| candidate.suite() == suite.suite());
                server_provider
                    .cipher_suites
                    .retain(|candidate| candidate.suite() == suite.suite());
                let mut roots = RootCertStore::empty();
                roots.add(cert.clone()).unwrap();
                let mut client_config =
                    RustlsClientConfig::builder_with_provider(Arc::new(client_provider))
                        .with_protocol_versions(&[&rustls::version::TLS13])
                        .unwrap()
                        .with_root_certificates(roots)
                        .with_no_client_auth();
                client_config.alpn_protocols = vec![b"h2".to_vec()];
                let key =
                    rustls::pki_types::PrivatePkcs8KeyDer::from(identity.key_pair.serialize_der());
                let mut server_config =
                    RustlsServerConfig::builder_with_provider(Arc::new(server_provider))
                        .with_protocol_versions(&[&rustls::version::TLS13])
                        .unwrap()
                        .with_no_client_auth()
                        .with_single_cert(vec![cert.clone()], key.into())
                        .unwrap();
                server_config.alpn_protocols = vec![b"h2".to_vec()];
                let mut client = Connection::Client(
                    ClientConnection::new(
                        Arc::new(client_config),
                        ServerName::try_from("localhost").unwrap(),
                    )
                    .unwrap(),
                );
                let mut server =
                    Connection::Server(ServerConnection::new(Arc::new(server_config)).unwrap());
                for _ in 0..16 {
                    deliver(&mut client, &mut server);
                    deliver(&mut server, &mut client);
                    if !client.is_handshaking()
                        && !server.is_handshaking()
                        && !client.wants_write()
                        && !server.wants_write()
                    {
                        break;
                    }
                }
                for peer in [&client, &server] {
                    assert!(!peer.is_handshaking());
                    assert_eq!(
                        peer.negotiated_cipher_suite().unwrap().suite(),
                        suite.suite()
                    );
                    assert_eq!(
                        peer.protocol_version(),
                        Some(rustls::ProtocolVersion::TLSv1_3)
                    );
                    assert_eq!(peer.alpn_protocol(), Some(b"h2".as_slice()));
                    assert_eq!(
                        peer.negotiated_key_exchange_group().unwrap().name(),
                        ring_provider().kx_groups[0].name()
                    );
                }
                for size in [1, 16383, 16384, 16385, 65537] {
                    let bytes: Vec<u8> = (0..size).map(|index| (index * 37 + 11) as u8).collect();
                    for chunk in bytes.chunks(16385) {
                        client.writer().write_all(chunk).unwrap();
                        deliver(&mut client, &mut server);
                        let mut received = vec![0; chunk.len()];
                        server.reader().read_exact(&mut received).unwrap();
                        assert_eq!(received, chunk);
                        server.writer().write_all(chunk).unwrap();
                        deliver(&mut server, &mut client);
                        client.reader().read_exact(&mut received).unwrap();
                        assert_eq!(received, chunk);
                    }
                }
                client
                    .writer()
                    .write_all(b"authenticated ciphertext")
                    .unwrap();
                let mut wire = Vec::new();
                while client.wants_write() {
                    client.write_tls(&mut wire).unwrap();
                }
                *wire.last_mut().unwrap() ^= 1;
                assert_eq!(server.read_tls(&mut Cursor::new(wire)).unwrap() > 0, true);
                assert!(server.process_new_packets().is_err());
            }
        }
    }

    #[test]
    fn identity_rejects_missing_and_malformed_credentials_with_context() {
        let endpoint = test_endpoint_config();
        for (pem, expected) in [
            ("", "tls certificate chain empty for localhost"),
            (
                "not a PEM certificate",
                "tls certificate chain empty for localhost",
            ),
            (
                "-----BEGIN CERTIFICATE-----\n%%%\n-----END CERTIFICATE-----\n",
                "failed to parse tls certificate for localhost",
            ),
        ] {
            let mut entry = endpoint.sni_certificates[0].clone();
            entry.certificate_chain_pem = pem.into();
            configuration_error(parse_identity(&entry, &endpoint), expected);
        }
        for (pem, expected) in [
            ("", "tls private key missing for localhost"),
            ("not a PEM key", "tls private key missing for localhost"),
            (
                "-----BEGIN PRIVATE KEY-----\n%%%\n-----END PRIVATE KEY-----\n",
                "failed to parse pkcs8 key for tls localhost",
            ),
        ] {
            let mut entry = endpoint.sni_certificates[0].clone();
            entry.private_key_pem = pem.into();
            configuration_error(parse_identity(&entry, &endpoint), expected);
        }
        assert!(parse_identity(&endpoint.sni_certificates[0], &endpoint).is_ok());
    }

    #[test]
    fn acceptor_rejects_invalid_identity_and_modes_without_fallback() {
        let mut endpoint = test_endpoint_config();
        endpoint.tls_mode = TlsMode::Disabled;
        endpoint.sni_certificates.clear();
        assert!(build_tls_acceptor(&endpoint).unwrap().is_none());
        endpoint.tls_mode = TlsMode::Dart;
        configuration_error(
            build_tls_acceptor(&endpoint),
            "tls_mode 'dart' not supported",
        );
        endpoint.tls_mode = TlsMode::Native;
        configuration_error(
            build_tls_acceptor(&endpoint),
            "requires at least one sni_certificates entry",
        );

        let mut endpoint = test_endpoint_config();
        endpoint.sni_certificates[0].private_key_pem =
            "-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----\n".into();
        configuration_error(
            build_tls_acceptor(&endpoint),
            "tls certificate invalid for localhost",
        );
        let mut endpoint = test_endpoint_config();
        endpoint.sni_certificates[0].hostname = "invalid host name".into();
        configuration_error(
            build_tls_acceptor(&endpoint),
            "tls SNI certificate invalid for invalid host name",
        );
        assert!(build_tls_acceptor(&test_endpoint_config())
            .unwrap()
            .is_some());
    }

    #[test]
    fn client_auth_rejects_unusable_trust_roots_even_when_optional() {
        for mode in [ClientAuthMode::Required, ClientAuthMode::Optional] {
            for (pem, expected) in [
                ("", "did not contain valid certificates"),
                (
                    "not a PEM certificate",
                    "did not contain valid certificates",
                ),
                (
                    "-----BEGIN CERTIFICATE-----\nAQID\n-----END CERTIFICATE-----\n",
                    "did not contain valid certificates",
                ),
                (
                    "-----BEGIN CERTIFICATE-----\n%%%\n-----END CERTIFICATE-----\n",
                    "failed to parse client_auth ca_certificates_pem",
                ),
            ] {
                let mut endpoint = test_endpoint_config();
                endpoint.client_auth = Some(crate::config::ClientAuthRuntime {
                    mode,
                    ca_certificates_pem: pem.into(),
                });
                configuration_error(
                    build_client_cert_verifier(&endpoint, &default_provider()),
                    expected,
                );
                configuration_error(build_tls_acceptor(&endpoint), expected);
            }
        }
    }

    #[test]
    fn client_auth_modes_preserve_certificate_validation() {
        let mut endpoint = test_endpoint_config();
        assert!(build_client_cert_verifier(&endpoint, &default_provider())
            .unwrap()
            .is_none());
        for (mode, mandatory) in [
            (ClientAuthMode::Required, true),
            (ClientAuthMode::Optional, false),
        ] {
            endpoint.client_auth = Some(crate::config::ClientAuthRuntime {
                mode,
                ca_certificates_pem: include_str!("../../../bench/bench_tls.crt").into(),
            });
            let verifier = build_client_cert_verifier(&endpoint, &default_provider())
                .unwrap()
                .unwrap();
            assert!(verifier.offer_client_auth());
            assert_eq!(verifier.client_auth_mandatory(), mandatory);
            assert!(!verifier.root_hint_subjects().is_empty());
            assert!(verifier
                .verify_client_cert(
                    &CertificateDer::from(vec![1, 2, 3]),
                    &[],
                    UnixTime::since_unix_epoch(Duration::from_secs(1)),
                )
                .is_err());
            assert!(build_tls_acceptor(&endpoint).unwrap().is_some());
        }
    }

    #[test]
    fn apply_server_tls_runtime_settings_disables_tls13_tickets_for_secret_extraction() {
        let endpoint = test_endpoint_config();
        let mut config = test_server_config(&endpoint);

        assert!(config.send_tls13_tickets > 0);

        apply_server_tls_runtime_settings(&mut config, &endpoint, true);

        assert!(config.enable_secret_extraction);
        assert_eq!(config.send_tls13_tickets, 0);
        assert_eq!(config.alpn_protocols, vec![b"h2".to_vec()]);
    }

    #[test]
    fn apply_server_tls_runtime_settings_preserves_ticket_defaults_without_secret_extraction() {
        let endpoint = test_endpoint_config();
        let mut config = test_server_config(&endpoint);
        let default_ticket_count = config.send_tls13_tickets;

        apply_server_tls_runtime_settings(&mut config, &endpoint, false);

        assert!(!config.enable_secret_extraction);
        assert_eq!(config.send_tls13_tickets, default_ticket_count);
        assert_eq!(config.alpn_protocols, vec![b"h2".to_vec()]);
    }

    fn test_server_config(endpoint: &EndpointRuntimeConfig) -> RustlsServerConfig {
        let cert_entry = endpoint
            .sni_certificates
            .first()
            .expect("test endpoint tls certificate");
        let (cert_chain, key_der) = parse_identity(cert_entry, endpoint).expect("test identity");

        RustlsServerConfig::builder_with_provider(Arc::new(default_provider()))
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(cert_chain, key_der)
            .expect("server config")
    }

    fn test_endpoint_config() -> EndpointRuntimeConfig {
        EndpointRuntimeConfig {
            host: "127.0.0.1".into(),
            port: 443,
            tls_mode: TlsMode::Native,
            client_auth: None,
            protocols: vec![TransportProtocol::Http2],
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
            sni_certificates: vec![SniCertificate {
                hostname: "localhost".into(),
                certificate_chain_pem: include_str!("../../../bench/bench_tls.crt").into(),
                private_key_pem: include_str!("../../../bench/bench_tls.key").into(),
            }],
            http_routes: Vec::new(),
            http: None,
        }
    }
}
