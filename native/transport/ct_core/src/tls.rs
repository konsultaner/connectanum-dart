use std::{io::Cursor, sync::Arc};

use rustls::{
    crypto::ring::default_provider,
    pki_types::{CertificateDer, PrivateKeyDer},
    server::{ClientHello, ResolvesServerCert, ResolvesServerCertUsingSni},
    sign::CertifiedKey,
    ServerConfig as RustlsServerConfig,
};
use rustls_pemfile::{certs as load_certs, pkcs8_private_keys, rsa_private_keys};
use tokio_rustls::TlsAcceptor;

use crate::{
    config::{EndpointRuntimeConfig, TlsMode, TransportProtocol},
    Error,
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
        let certified_key = CertifiedKey::from_der(cert_chain, key_der, &provider).map_err(|err| {
            Error::RouterConfigInvalid(format!(
                "endpoint {}:{} tls certificate invalid for {}: {}",
                endpoint.host, endpoint.port, entry.hostname, err
            ))
        })?;
        if index == 0 {
            default_key = Some(Arc::new(certified_key.clone()));
        }
        sni.add(entry.hostname.as_str(), certified_key).map_err(|err| {
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
    let mut config = RustlsServerConfig::builder()
        .with_no_client_auth()
        .with_cert_resolver(Arc::new(resolver));
    config.alpn_protocols = tcp_alpn_protocols(endpoint);

    Ok(Some(TlsAcceptor::from(Arc::new(config))))
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
