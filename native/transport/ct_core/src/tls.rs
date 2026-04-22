use std::{io::Cursor, sync::Arc};

use rustls::{
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::ring::default_provider,
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
    config.enable_secret_extraction = ktls::secret_extraction_requested();
    config.alpn_protocols = tcp_alpn_protocols(endpoint);

    Ok(Some(TlsAcceptor::from(Arc::new(config))))
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
