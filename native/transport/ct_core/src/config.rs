use serde::{Deserialize, Deserializer};
use serde_json::Value as JsonValue;
use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, OnceLock, RwLock};
use std::time::Duration;

use crate::Error;

/// Lowest raw socket message size exponent defined by the WAMP specification.
pub const MIN_RAWSOCKET_SIZE_EXPONENT: u32 = 9;
/// Default raw socket message size exponent used when the config omits the field.
pub const DEFAULT_RAWSOCKET_SIZE_EXPONENT: u32 = 16;
/// Connectanum allows larger payloads than the base specification.
pub const CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT: u32 = 30;
/// Default timeout for completing the RawSocket handshake.
pub const DEFAULT_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
/// Default number of queued outbound frames per connection (RawSocket/WebSocket).
pub const DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY: usize = 1024;
pub const MIN_OUTBOUND_SEND_QUEUE_CAPACITY: usize = 1;
pub const MAX_OUTBOUND_SEND_QUEUE_CAPACITY: usize = 65535;

static ROUTER_CONFIG: OnceLock<RwLock<Option<Arc<RouterConfig>>>> = OnceLock::new();

fn config_lock() -> &'static RwLock<Option<Arc<RouterConfig>>> {
    ROUTER_CONFIG.get_or_init(|| RwLock::new(None))
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct RouterConfig {
    pub schema: String,
    pub version: u32,
    pub endpoints: Vec<EndpointConfig>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct EndpointConfig {
    pub host: String,
    pub port: u16,
    pub tls_mode: TlsMode,
    #[serde(
        rename = "idle_timeout_ms",
        default,
        deserialize_with = "deserialize_duration_opt"
    )]
    pub idle_timeout: Option<Duration>,
    #[serde(
        rename = "heartbeat_interval_ms",
        default,
        deserialize_with = "deserialize_duration_opt"
    )]
    pub heartbeat_interval: Option<Duration>,
    #[serde(
        rename = "heartbeat_timeout_ms",
        default,
        deserialize_with = "deserialize_duration_opt"
    )]
    pub heartbeat_timeout: Option<Duration>,
    #[serde(
        rename = "handshake_timeout_ms",
        default,
        deserialize_with = "deserialize_duration_opt"
    )]
    pub handshake_timeout: Option<Duration>,
    pub max_http_content_length: Option<u64>,
    pub max_rawsocket_size_exponent: Option<u32>,
    pub outbound_send_queue_capacity: Option<usize>,
    pub websocket_path: Option<String>,
    #[serde(default)]
    pub sni_certificates: Vec<SniCertificate>,
    pub client_auth: Option<ClientAuthConfig>,
    #[serde(default)]
    pub http_routes: Vec<HttpRouteConfig>,
    #[serde(default = "default_endpoint_protocols")]
    pub protocols: Vec<TransportProtocol>,
    #[serde(default)]
    pub http: Option<HttpEndpointConfig>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct SniCertificate {
    pub hostname: String,
    pub certificate_chain_pem: String,
    pub private_key_pem: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ClientAuthConfig {
    pub mode: ClientAuthMode,
    #[serde(default)]
    pub ca_certificates_pem: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ClientAuthMode {
    Disabled,
    Optional,
    Required,
}

pub fn apply_router_config_bytes(bytes: &[u8]) -> Result<(), Error> {
    let parsed: RouterConfig =
        serde_json::from_slice(bytes).map_err(|err| Error::RouterConfigInvalid(err.to_string()))?;
    let mut sanctioned_ports: HashSet<(String, u16)> = HashSet::new();
    for endpoint in &parsed.endpoints {
        EndpointRuntimeConfig::try_from_endpoint(endpoint)?;
        if !sanctioned_ports.insert((endpoint.host.to_lowercase(), endpoint.port)) {
            return Err(Error::RouterConfigInvalid(format!(
                "duplicate endpoint {}:{}",
                endpoint.host, endpoint.port
            )));
        }
    }
    let mut guard = config_lock()
        .write()
        .map_err(|_| Error::RouterConfigInvalid("lock poisoned".into()))?;
    *guard = Some(Arc::new(parsed));
    Ok(())
}

#[allow(dead_code)]
pub fn current_config() -> Option<Arc<RouterConfig>> {
    config_lock().read().ok().and_then(|guard| guard.clone())
}

pub fn find_endpoint(host: &str, port: u16) -> Option<Arc<EndpointConfig>> {
    config_lock()
        .read()
        .ok()
        .and_then(|guard| guard.clone())
        .and_then(|cfg| {
            cfg.endpoints
                .iter()
                .find(|endpoint| endpoint.host.eq_ignore_ascii_case(host) && endpoint.port == port)
                .cloned()
                .map(Arc::new)
        })
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum TlsMode {
    Disabled,
    Native,
    Dart,
}

fn deserialize_duration_opt<'de, D>(deserializer: D) -> Result<Option<Duration>, D::Error>
where
    D: Deserializer<'de>,
{
    let millis = Option::<u64>::deserialize(deserializer)?;
    Ok(millis.map(Duration::from_millis))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TransportProtocol {
    Rawsocket,
    Websocket,
    Http,
    Http2,
    #[allow(dead_code)]
    Http3,
}

impl TransportProtocol {
    pub fn identifier(&self) -> &'static str {
        match self {
            TransportProtocol::Rawsocket => "rawsocket",
            TransportProtocol::Websocket => "websocket",
            TransportProtocol::Http => "http",
            TransportProtocol::Http2 => "http2",
            TransportProtocol::Http3 => "http3",
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct HttpEndpointConfig {
    #[serde(default)]
    pub alpn: Vec<String>,
    #[serde(default)]
    pub http3: Option<Http3EndpointConfig>,
    #[serde(default)]
    pub options: HashMap<String, JsonValue>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Http3EndpointConfig {
    #[serde(default)]
    pub enabled: bool,
    pub port: Option<u16>,
}

#[derive(Debug, Clone)]
pub struct HttpEndpointRuntime {
    pub alpn: Vec<String>,
    pub http3: Option<Http3EndpointRuntime>,
    pub options: HashMap<String, JsonValue>,
}

#[derive(Debug, Clone)]
pub struct Http3EndpointRuntime {
    pub enabled: bool,
    pub port: Option<u16>,
}

/// Runtime-ready view over endpoint configuration values.
#[derive(Debug, Clone)]
pub struct EndpointRuntimeConfig {
    pub host: String,
    pub port: u16,
    pub tls_mode: TlsMode,
    pub client_auth: Option<ClientAuthRuntime>,
    pub protocols: Vec<TransportProtocol>,
    pub idle_timeout: Option<Duration>,
    pub heartbeat_interval: Option<Duration>,
    pub heartbeat_timeout: Option<Duration>,
    pub handshake_timeout: Duration,
    pub max_http_content_length: Option<u64>,
    pub max_rawsocket_size_exponent: u32,
    pub max_rawsocket_size: u64,
    pub max_upgrade_exponent: Option<u32>,
    pub outbound_send_queue_capacity: usize,
    pub websocket_path: Option<String>,
    pub sni_certificates: Vec<SniCertificate>,
    pub http_routes: Vec<HttpRouteRuntime>,
    pub http: Option<HttpEndpointRuntime>,
}

#[derive(Debug, Clone)]
pub struct ClientAuthRuntime {
    pub mode: ClientAuthMode,
    pub ca_certificates_pem: String,
}

impl EndpointRuntimeConfig {
    pub fn try_from_endpoint(endpoint: &EndpointConfig) -> Result<Self, Error> {
        let mut protocols = sanitize_protocols(&endpoint.protocols);
        if protocols.is_empty() {
            protocols.push(TransportProtocol::Rawsocket);
        }
        let exponent = endpoint
            .max_rawsocket_size_exponent
            .unwrap_or(DEFAULT_RAWSOCKET_SIZE_EXPONENT);
        if exponent < MIN_RAWSOCKET_SIZE_EXPONENT
            || exponent > CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT
        {
            return Err(Error::RouterConfigInvalid(format!(
                "endpoint {}:{} declares max_rawsocket_size_exponent {} outside supported range {}..{}",
                endpoint.host, endpoint.port, exponent, MIN_RAWSOCKET_SIZE_EXPONENT, CONNECTANUM_MAX_RAWSOCKET_SIZE_EXPONENT
            )));
        }
        if let Some(timeout) = endpoint.idle_timeout {
            if timeout.is_zero() {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} idle_timeout_ms must be positive",
                    endpoint.host, endpoint.port
                )));
            }
        }
        if let Some(interval) = endpoint.heartbeat_interval {
            if interval.is_zero() {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} heartbeat_interval_ms must be positive",
                    endpoint.host, endpoint.port
                )));
            }
        }
        if let Some(timeout) = endpoint.heartbeat_timeout {
            if timeout.is_zero() {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} heartbeat_timeout_ms must be positive",
                    endpoint.host, endpoint.port
                )));
            }
        }
        if let (Some(interval), Some(timeout)) =
            (endpoint.heartbeat_interval, endpoint.heartbeat_timeout)
        {
            if timeout < interval {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} heartbeat_timeout_ms must be >= heartbeat_interval_ms",
                    endpoint.host, endpoint.port
                )));
            }
        }
        if let Some(timeout) = endpoint.handshake_timeout {
            if timeout.is_zero() {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} handshake_timeout_ms must be positive",
                    endpoint.host, endpoint.port
                )));
            }
        }
        if let Some(limit) = endpoint.max_http_content_length {
            if limit == 0 {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} max_http_content_length must be positive",
                    endpoint.host, endpoint.port
                )));
            }
        }
        let outbound_send_queue_capacity = endpoint
            .outbound_send_queue_capacity
            .unwrap_or(DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY);
        if outbound_send_queue_capacity < MIN_OUTBOUND_SEND_QUEUE_CAPACITY
            || outbound_send_queue_capacity > MAX_OUTBOUND_SEND_QUEUE_CAPACITY
        {
            return Err(Error::RouterConfigInvalid(format!(
                "endpoint {}:{} outbound_send_queue_capacity {} outside supported range {}..{}",
                endpoint.host,
                endpoint.port,
                outbound_send_queue_capacity,
                MIN_OUTBOUND_SEND_QUEUE_CAPACITY,
                MAX_OUTBOUND_SEND_QUEUE_CAPACITY
            )));
        }
        if !endpoint.http_routes.is_empty() && !protocols.contains(&TransportProtocol::Http) {
            return Err(Error::RouterConfigInvalid(format!(
                "endpoint {}:{} defines http routes but HTTP protocol disabled",
                endpoint.host, endpoint.port
            )));
        }
        let http_routes =
            HttpRouteRuntime::try_from_configs(&endpoint.http_routes).map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} http route invalid: {}",
                    endpoint.host, endpoint.port, err
                ))
            })?;
        let http_runtime = if protocols.contains(&TransportProtocol::Http) {
            HttpEndpointRuntime::try_from_config(endpoint.http.as_ref()).map_err(|err| {
                Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} http config invalid: {}",
                    endpoint.host, endpoint.port, err
                ))
            })?
        } else {
            None
        };
        if let Some(http_runtime) = &http_runtime {
            if http_runtime.alpn.iter().any(|token| token == "h2")
                && !protocols.contains(&TransportProtocol::Http2)
            {
                protocols.push(TransportProtocol::Http2);
            }
            if let Some(http3) = &http_runtime.http3 {
                if http3.enabled && !protocols.contains(&TransportProtocol::Http3) {
                    protocols.push(TransportProtocol::Http3);
                }
            }
        }
        match endpoint.tls_mode {
            TlsMode::Disabled => {
                if protocols.contains(&TransportProtocol::Http3) {
                    return Err(Error::RouterConfigInvalid(format!(
                        "endpoint {}:{} enables http3 but tls_mode is disabled",
                        endpoint.host, endpoint.port
                    )));
                }
            }
            TlsMode::Native => {
                if endpoint.sni_certificates.is_empty() {
                    return Err(Error::RouterConfigInvalid(format!(
                        "endpoint {}:{} tls_mode native requires at least one sni_certificates entry",
                        endpoint.host, endpoint.port
                    )));
                }
            }
            TlsMode::Dart => {
                return Err(Error::RouterConfigInvalid(format!(
                    "endpoint {}:{} tls_mode dart is not supported yet",
                    endpoint.host, endpoint.port
                )));
            }
        }
        let client_auth = match &endpoint.client_auth {
            Some(config) => match config.mode {
                ClientAuthMode::Disabled => None,
                mode => {
                    if endpoint.tls_mode != TlsMode::Native {
                        return Err(Error::RouterConfigInvalid(format!(
                            "endpoint {}:{} client_auth requires tls_mode native",
                            endpoint.host, endpoint.port
                        )));
                    }
                    if config.ca_certificates_pem.trim().is_empty() {
                        return Err(Error::RouterConfigInvalid(format!(
                            "endpoint {}:{} client_auth requires ca_certificates_pem",
                            endpoint.host, endpoint.port
                        )));
                    }
                    Some(ClientAuthRuntime {
                        mode,
                        ca_certificates_pem: config.ca_certificates_pem.trim().to_string(),
                    })
                }
            },
            None => None,
        };
        Ok(Self {
            host: endpoint.host.clone(),
            port: endpoint.port,
            tls_mode: endpoint.tls_mode.clone(),
            client_auth,
            protocols,
            idle_timeout: endpoint.idle_timeout,
            heartbeat_interval: endpoint.heartbeat_interval,
            heartbeat_timeout: endpoint.heartbeat_timeout,
            handshake_timeout: endpoint
                .handshake_timeout
                .unwrap_or(DEFAULT_HANDSHAKE_TIMEOUT),
            max_http_content_length: endpoint.max_http_content_length,
            max_rawsocket_size_exponent: exponent,
            max_rawsocket_size: 1u64 << exponent,
            max_upgrade_exponent: endpoint.max_rawsocket_size_exponent,
            outbound_send_queue_capacity,
            websocket_path: endpoint.websocket_path.clone(),
            sni_certificates: endpoint.sni_certificates.clone(),
            http_routes,
            http: http_runtime,
        })
    }

    pub fn supports_protocol(&self, protocol: TransportProtocol) -> bool {
        self.protocols.contains(&protocol)
    }

    pub fn http_settings(&self) -> Option<&HttpEndpointRuntime> {
        self.http.as_ref()
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HttpRouteMatchKind {
    Exact,
    Prefix,
}

impl Default for HttpRouteMatchKind {
    fn default() -> Self {
        HttpRouteMatchKind::Exact
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct HttpRouteConfig {
    pub path: String,
    #[serde(default)]
    pub match_kind: HttpRouteMatchKind,
    #[serde(default)]
    pub protocols: Vec<String>,
    #[serde(default)]
    pub transport_auth: HttpRouteTransportAuthConfig,
    #[serde(default)]
    pub methods: HashMap<String, HttpRouteMethodConfig>,
    #[serde(default)]
    pub default: Option<HttpRouteMethodConfig>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct HttpRouteTransportAuthConfig {
    #[serde(default)]
    pub require_bearer: bool,
    #[serde(default)]
    pub require_tls: bool,
    #[serde(default)]
    pub require_mtls: bool,
    #[serde(default)]
    pub allow_unauthenticated_cors_preflight: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HttpRouteMethodConfig {
    Translation {
        realm: String,
        procedure: String,
    },
    ReservedRealm {
        #[serde(default)]
        namespace: Option<String>,
        #[serde(default = "HttpRouteMethodConfig::default_append")]
        append_method_suffix: bool,
    },
    Namespace {
        realm: String,
        namespace: String,
        #[serde(default = "HttpRouteMethodConfig::default_append")]
        append_method_suffix: bool,
    },
}

impl HttpRouteMethodConfig {
    fn default_append() -> bool {
        true
    }
}

#[derive(Debug, Clone)]
pub struct HttpRouteRuntime {
    pub path: String,
    pub match_kind: HttpRouteMatchKind,
    pub protocols: Vec<String>,
    pub transport_auth: HttpRouteTransportAuthRuntime,
    pub methods: HashMap<String, HttpRouteTarget>,
    pub default: Option<HttpRouteTarget>,
}

#[derive(Debug, Clone, Default)]
pub struct HttpRouteTransportAuthRuntime {
    pub require_bearer: bool,
    pub require_tls: bool,
    pub require_mtls: bool,
    pub allow_unauthenticated_cors_preflight: bool,
}

#[derive(Debug, Clone)]
pub enum HttpRouteTarget {
    Translation {
        realm: String,
        procedure: String,
    },
    ReservedRealm {
        namespace: Option<String>,
        append_method_suffix: bool,
    },
    Namespace {
        realm: String,
        namespace: String,
        append_method_suffix: bool,
    },
}

impl HttpRouteRuntime {
    fn try_from_configs(configs: &[HttpRouteConfig]) -> Result<Vec<Self>, String> {
        let mut routes = Vec::with_capacity(configs.len());
        for config in configs {
            let path = normalise_path(&config.path)?;
            let protocols = normalise_protocols(&config.protocols)?;
            let mut methods = HashMap::new();
            for (method, handler) in &config.methods {
                let method_key = method.trim().to_uppercase();
                if method_key.is_empty() {
                    return Err("method key may not be empty".into());
                }
                if methods.contains_key(&method_key) {
                    return Err(format!("duplicate method declaration {}", method_key));
                }
                methods.insert(method_key, HttpRouteTarget::from_config(handler)?);
            }
            let default = match &config.default {
                Some(handler) => Some(HttpRouteTarget::from_config(handler)?),
                None => None,
            };
            routes.push(HttpRouteRuntime {
                path,
                match_kind: config.match_kind.clone(),
                protocols,
                transport_auth: HttpRouteTransportAuthRuntime::from_config(&config.transport_auth),
                methods,
                default,
            });
        }
        routes.sort_by(|a, b| b.path.len().cmp(&a.path.len()));
        Ok(routes)
    }
}

impl HttpRouteTarget {
    fn from_config(config: &HttpRouteMethodConfig) -> Result<Self, String> {
        match config {
            HttpRouteMethodConfig::Translation { realm, procedure } => {
                if realm.trim().is_empty() {
                    return Err("translation target realm cannot be empty".into());
                }
                if procedure.trim().is_empty() {
                    return Err("translation target procedure cannot be empty".into());
                }
                Ok(HttpRouteTarget::Translation {
                    realm: realm.trim().to_string(),
                    procedure: procedure.trim().to_string(),
                })
            }
            HttpRouteMethodConfig::ReservedRealm {
                namespace,
                append_method_suffix,
            } => Ok(HttpRouteTarget::ReservedRealm {
                namespace: namespace.as_ref().map(|value| value.trim().to_string()),
                append_method_suffix: *append_method_suffix,
            }),
            HttpRouteMethodConfig::Namespace {
                realm,
                namespace,
                append_method_suffix,
            } => {
                if realm.trim().is_empty() {
                    return Err("namespace mapping realm cannot be empty".into());
                }
                if namespace.trim().is_empty() {
                    return Err("namespace mapping namespace cannot be empty".into());
                }
                Ok(HttpRouteTarget::Namespace {
                    realm: realm.trim().to_string(),
                    namespace: namespace.trim().to_string(),
                    append_method_suffix: *append_method_suffix,
                })
            }
        }
    }
}

impl HttpRouteTransportAuthRuntime {
    fn from_config(config: &HttpRouteTransportAuthConfig) -> Self {
        Self {
            require_bearer: config.require_bearer,
            require_tls: config.require_tls || config.require_mtls,
            require_mtls: config.require_mtls,
            allow_unauthenticated_cors_preflight: config.allow_unauthenticated_cors_preflight,
        }
    }
}

impl HttpEndpointRuntime {
    fn try_from_config(config: Option<&HttpEndpointConfig>) -> Result<Option<Self>, String> {
        let Some(config) = config else {
            return Ok(None);
        };
        let mut alpn = Vec::new();
        let mut seen = HashSet::new();
        for token in &config.alpn {
            let value = token.trim();
            if value.is_empty() {
                continue;
            }
            let lower = value.to_lowercase();
            if seen.insert(lower.clone()) {
                alpn.push(lower);
            }
        }
        let http3 = if let Some(http3) = &config.http3 {
            if http3.enabled {
                Some(Http3EndpointRuntime {
                    enabled: true,
                    port: http3.port,
                })
            } else {
                None
            }
        } else {
            None
        };
        Ok(Some(HttpEndpointRuntime {
            alpn,
            http3,
            options: config.options.clone(),
        }))
    }
}

fn normalise_path(value: &str) -> Result<String, String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err("route path cannot be empty".into());
    }
    if !trimmed.starts_with('/') {
        return Err(format!("route path must start with '/': {}", trimmed));
    }
    Ok(trimmed.to_string())
}

fn normalise_protocols(protocols: &[String]) -> Result<Vec<String>, String> {
    let mut result = Vec::new();
    let mut seen = HashSet::new();
    for protocol in protocols {
        let cleaned = normalise_http_route_protocol(protocol);
        if cleaned.is_empty() {
            return Err("protocol identifiers cannot be empty".into());
        }
        if !seen.insert(cleaned.clone()) {
            continue;
        }
        result.push(cleaned);
    }
    Ok(result)
}

fn normalise_http_route_protocol(protocol: &str) -> String {
    let cleaned = protocol.trim().to_lowercase();
    match cleaned.as_str() {
        "http" | "http1" | "http/1" | "http/1.0" | "http/1.1" => "http".to_string(),
        "h2" | "http2" | "http/2" => "http2".to_string(),
        "h3" | "http3" | "http/3" => "http3".to_string(),
        _ => cleaned,
    }
}

fn default_endpoint_protocols() -> Vec<TransportProtocol> {
    vec![TransportProtocol::Rawsocket]
}

fn sanitize_protocols(protocols: &[TransportProtocol]) -> Vec<TransportProtocol> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for protocol in protocols {
        if seen.insert(*protocol) {
            result.push(*protocol);
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn default_protocols_include_rawsocket() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled"
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();
        assert_eq!(runtime.protocols, vec![TransportProtocol::Rawsocket]);
    }

    #[test]
    fn duplicate_protocols_are_deduplicated() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["rawsocket", "http", "websocket", "http"]
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();
        assert_eq!(
            runtime.protocols,
            vec![
                TransportProtocol::Rawsocket,
                TransportProtocol::Http,
                TransportProtocol::Websocket
            ]
        );
    }

    #[test]
    fn http_routes_require_http_protocol() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["rawsocket"],
            "http_routes": [{
                "path": "/metrics",
                "match_kind": "prefix",
                "methods": {
                    "GET": {"type": "reserved_realm"}
                }
            }]
        }))
        .unwrap();
        let err = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap_err();
        assert!(
            format!("{err}").contains("defines http routes but HTTP protocol disabled"),
            "{err}"
        );
    }

    #[test]
    fn http_route_protocol_aliases_and_mismatches_are_explicit() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["http"],
            "http_routes": [
                {
                    "path": "/api/h1",
                    "protocols": ["http"],
                    "methods": {
                        "GET": {"type": "reserved_realm"}
                    }
                },
                {
                    "path": "/api/h2-only",
                    "protocols": ["http/2", "h2"],
                    "methods": {
                        "GET": {"type": "reserved_realm"}
                    }
                }
            ]
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();

        let h1_match = runtime.match_http_route("/api/h1", None, "GET", "http/1.1");
        assert!(matches!(h1_match, HttpRouteMatch::Resolved(_)));

        match runtime.match_http_route("/api/h2-only", None, "GET", "http/1.1") {
            HttpRouteMatch::ProtocolNotAllowed { allowed_protocols } => {
                assert_eq!(allowed_protocols, vec!["http2".to_string()]);
            }
            other => panic!("expected protocol mismatch, got {other:?}"),
        }

        let h2_match = runtime.match_http_route("/api/h2-only", None, "GET", "http2");
        assert!(matches!(h2_match, HttpRouteMatch::Resolved(_)));
    }

    #[test]
    fn http_route_method_mismatches_are_explicit() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["http"],
            "http_routes": [{
                "path": "/api/items",
                "methods": {
                    "GET": {"type": "reserved_realm"},
                    "POST": {"type": "reserved_realm"}
                }
            }]
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();

        match runtime.match_http_route("/api/items", None, "DELETE", "http/1.1") {
            HttpRouteMatch::MethodNotAllowed { allowed_methods } => {
                assert_eq!(allowed_methods, vec!["GET".to_string(), "POST".to_string()]);
            }
            other => panic!("expected method mismatch, got {other:?}"),
        }

        assert!(matches!(
            runtime.match_http_route("/api/missing", None, "DELETE", "http/1.1"),
            HttpRouteMatch::NotFound
        ));
    }

    #[test]
    fn http_route_root_prefix_is_catch_all_and_specific_routes_win() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["http"],
            "http_routes": [
                {
                    "path": "/",
                    "match_kind": "prefix",
                    "methods": {
                        "GET": {
                            "type": "translation",
                            "realm": "realm1",
                            "procedure": "com.example.catch_all"
                        }
                    }
                },
                {
                    "path": "/api",
                    "match_kind": "prefix",
                    "methods": {
                        "GET": {
                            "type": "translation",
                            "realm": "realm1",
                            "procedure": "com.example.api"
                        }
                    }
                }
            ]
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();

        match runtime.match_http_route("/other/path", None, "GET", "http/1.1") {
            HttpRouteMatch::Resolved(resolution) => {
                assert_eq!(resolution.procedure, "com.example.catch_all");
            }
            other => panic!("expected catch-all resolution, got {other:?}"),
        }

        match runtime.match_http_route("/api/items", None, "GET", "http/1.1") {
            HttpRouteMatch::Resolved(resolution) => {
                assert_eq!(resolution.procedure, "com.example.api");
            }
            other => panic!("expected specific route resolution, got {other:?}"),
        }
    }

    #[test]
    fn http_prefix_namespace_shorthand_maps_relative_path_segments() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["http"],
            "http_routes": [{
                "path": "/api",
                "match_kind": "prefix",
                "methods": {
                    "GET": {
                        "type": "namespace",
                        "realm": "realm1",
                        "namespace": "api",
                        "append_method_suffix": true
                    }
                }
            }]
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();

        match runtime.match_http_route("/api/items/42", None, "GET", "http/1.1") {
            HttpRouteMatch::Resolved(resolution) => {
                assert_eq!(resolution.realm, "realm1");
                assert_eq!(resolution.procedure, "api.items.42.get");
                assert_eq!(resolution.path, "/api/items/42");
            }
            other => panic!("expected namespace prefix resolution, got {other:?}"),
        }

        match runtime.match_http_route("/api", None, "GET", "http/1.1") {
            HttpRouteMatch::Resolved(resolution) => {
                assert_eq!(resolution.procedure, "api.index.get");
                assert_eq!(resolution.path, "/api");
            }
            other => panic!("expected namespace index resolution, got {other:?}"),
        }
    }

    #[test]
    fn http_reserved_shorthand_keeps_full_path_segments() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "protocols": ["http"],
            "http_routes": [
                {
                    "path": "/healthz",
                    "methods": {
                        "GET": {
                            "type": "reserved_realm",
                            "append_method_suffix": true
                        }
                    }
                },
                {
                    "path": "/ops",
                    "match_kind": "prefix",
                    "methods": {
                        "POST": {
                            "type": "reserved_realm",
                            "namespace": "ops",
                            "append_method_suffix": true
                        }
                    }
                }
            ]
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();

        match runtime.match_http_route("/healthz", None, "GET", "http/1.1") {
            HttpRouteMatch::Resolved(resolution) => {
                assert_eq!(resolution.realm, RESERVED_HTTP_REALM);
                assert_eq!(resolution.procedure, "healthz.get");
                assert_eq!(resolution.path, "/healthz");
            }
            other => panic!("expected exact shorthand resolution, got {other:?}"),
        }

        match runtime.match_http_route("/ops/restart", None, "POST", "http/1.1") {
            HttpRouteMatch::Resolved(resolution) => {
                assert_eq!(resolution.realm, RESERVED_HTTP_REALM);
                assert_eq!(resolution.procedure, "ops.ops.restart.post");
                assert_eq!(resolution.path, "/ops/restart");
            }
            other => panic!("expected reserved prefix resolution, got {other:?}"),
        }
    }

    #[test]
    fn http_settings_parse_alpn_and_options() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "native",
            "protocols": ["rawsocket", "http"],
            "sni_certificates": [{
                "hostname": "localhost",
                "certificate_chain_pem": "CERT",
                "private_key_pem": "KEY"
            }],
            "http": {
                "alpn": ["h2", "http/1.1", "h2"],
                "http3": {"enabled": true, "port": 9443},
                "options": {"max_concurrent_streams": 32}
            }
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();
        let http = runtime.http_settings().expect("http runtime");
        assert_eq!(http.alpn, vec!["h2", "http/1.1"]);
        let http3 = http.http3.as_ref().expect("http3 enabled");
        assert!(http3.enabled);
        assert_eq!(http3.port, Some(9443));
        assert_eq!(
            http.options.get("max_concurrent_streams"),
            Some(&serde_json::Value::from(32))
        );
        assert!(runtime.protocols.contains(&TransportProtocol::Http2));
        assert!(runtime.protocols.contains(&TransportProtocol::Http3));
    }

    #[test]
    fn client_auth_requires_native_tls() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "client_auth": {"mode": "required", "ca_certificates_pem": "CERT"}
        }))
        .unwrap();
        let err = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap_err();
        assert!(
            format!("{err}").contains("client_auth requires tls_mode native"),
            "{err}"
        );
    }

    #[test]
    fn client_auth_requires_ca_certificates() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "native",
            "sni_certificates": [{
                "hostname": "localhost",
                "certificate_chain_pem": "CERT",
                "private_key_pem": "KEY"
            }],
            "client_auth": {"mode": "required"}
        }))
        .unwrap();
        let err = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap_err();
        assert!(
            format!("{err}").contains("client_auth requires ca_certificates_pem"),
            "{err}"
        );
    }

    #[test]
    fn outbound_send_queue_capacity_defaults_and_validates() {
        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled"
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();
        assert_eq!(
            runtime.outbound_send_queue_capacity,
            DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY
        );

        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "outbound_send_queue_capacity": 32
        }))
        .unwrap();
        let runtime = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap();
        assert_eq!(runtime.outbound_send_queue_capacity, 32);

        let cfg: EndpointConfig = serde_json::from_value(json!({
            "host": "127.0.0.1",
            "port": 0,
            "tls_mode": "disabled",
            "outbound_send_queue_capacity": 0
        }))
        .unwrap();
        let err = EndpointRuntimeConfig::try_from_endpoint(&cfg).unwrap_err();
        assert!(
            format!("{err}").contains("outbound_send_queue_capacity"),
            "{err}"
        );
    }
}

pub const RESERVED_HTTP_REALM: &str = "router.http";

#[derive(Debug, Clone)]
pub struct HttpRouteResolution {
    pub realm: String,
    pub procedure: String,
    pub method: String,
    pub protocol: String,
    pub path: String,
    pub query: Option<String>,
    pub transport_auth: HttpRouteTransportAuthRuntime,
}

#[derive(Debug, Clone)]
pub enum HttpRouteMatch {
    NotFound,
    MethodNotAllowed { allowed_methods: Vec<String> },
    ProtocolNotAllowed { allowed_protocols: Vec<String> },
    Resolved(HttpRouteResolution),
}

impl EndpointRuntimeConfig {
    pub fn match_http_route(
        &self,
        path: &str,
        query: Option<&str>,
        method: &str,
        protocol: &str,
    ) -> HttpRouteMatch {
        let mut best: Option<(usize, HttpRouteResolution)> = None;
        let mut method_not_allowed: Option<HashSet<String>> = None;
        let mut protocol_not_allowed: Option<HashSet<String>> = None;
        let request_protocol = normalise_http_route_protocol(protocol);
        for route in &self.http_routes {
            if !route.matches_path(path) {
                continue;
            }
            if !route.allows_protocol(&request_protocol) {
                let entry = protocol_not_allowed.get_or_insert_with(HashSet::new);
                for allowed in route.allowed_protocols() {
                    entry.insert(allowed);
                }
                continue;
            }
            match route.resolve_for_method(path, query, method, protocol) {
                Some(resolution) => {
                    let priority = route.path.len();
                    let replace = best
                        .as_ref()
                        .map(|(len, _)| priority > *len)
                        .unwrap_or(true);
                    if replace {
                        best = Some((priority, resolution));
                    }
                }
                None => {
                    let entry = method_not_allowed.get_or_insert_with(HashSet::new);
                    for allowed in route.allowed_methods() {
                        entry.insert(allowed);
                    }
                }
            }
        }

        if let Some((_, resolution)) = best {
            HttpRouteMatch::Resolved(resolution)
        } else if let Some(allowed_set) = method_not_allowed {
            let mut allowed: Vec<String> = allowed_set.into_iter().collect();
            allowed.sort();
            HttpRouteMatch::MethodNotAllowed {
                allowed_methods: allowed,
            }
        } else if let Some(allowed_set) = protocol_not_allowed {
            let mut allowed: Vec<String> = allowed_set.into_iter().collect();
            allowed.sort();
            HttpRouteMatch::ProtocolNotAllowed {
                allowed_protocols: allowed,
            }
        } else {
            HttpRouteMatch::NotFound
        }
    }
}

impl HttpRouteRuntime {
    fn matches_path(&self, path: &str) -> bool {
        match self.match_kind {
            HttpRouteMatchKind::Exact => path == self.path,
            HttpRouteMatchKind::Prefix => {
                if self.path == "/" {
                    return true;
                }
                if !path.starts_with(&self.path) {
                    return false;
                }
                if path.len() == self.path.len() {
                    return true;
                }
                let boundary = self.path.as_bytes().last().copied().unwrap_or(b'/');
                if boundary == b'/' {
                    return true;
                }
                path.as_bytes()
                    .get(self.path.len())
                    .map(|byte| *byte == b'/')
                    .unwrap_or(false)
            }
        }
    }

    fn allows_protocol(&self, protocol: &str) -> bool {
        if self.protocols.is_empty() {
            return true;
        }
        self.protocols.iter().any(|candidate| candidate == protocol)
    }

    fn resolve_for_method(
        &self,
        path: &str,
        query: Option<&str>,
        method: &str,
        protocol: &str,
    ) -> Option<HttpRouteResolution> {
        let method_key = method.trim().to_uppercase();
        let target = self
            .methods
            .get(&method_key)
            .or_else(|| self.default.as_ref())?;
        let target_path = self.target_path(target, path);
        Some(target.materialise(
            &self.transport_auth,
            target_path.as_ref(),
            query,
            &method_key,
            protocol,
            path,
        ))
    }

    fn allowed_methods(&self) -> Vec<String> {
        let mut methods: Vec<String> = self.methods.keys().cloned().collect();
        methods.sort();
        methods
    }

    fn allowed_protocols(&self) -> Vec<String> {
        let mut protocols = self.protocols.clone();
        protocols.sort();
        protocols
    }

    fn target_path<'a>(&self, target: &HttpRouteTarget, request_path: &'a str) -> Cow<'a, str> {
        if matches!(&self.match_kind, HttpRouteMatchKind::Prefix)
            && self.path != "/"
            && matches!(target, HttpRouteTarget::Namespace { .. })
        {
            Cow::Owned(route_relative_path(&self.path, request_path))
        } else {
            Cow::Borrowed(request_path)
        }
    }
}

impl HttpRouteTarget {
    fn materialise(
        &self,
        transport_auth: &HttpRouteTransportAuthRuntime,
        target_path: &str,
        query: Option<&str>,
        method: &str,
        protocol: &str,
        request_path: &str,
    ) -> HttpRouteResolution {
        match self {
            HttpRouteTarget::Translation { realm, procedure } => HttpRouteResolution {
                realm: realm.clone(),
                procedure: procedure.clone(),
                method: method.to_string(),
                protocol: protocol.to_string(),
                path: request_path.to_string(),
                query: query.map(|value| value.to_string()),
                transport_auth: transport_auth.clone(),
            },
            HttpRouteTarget::ReservedRealm {
                namespace,
                append_method_suffix,
            } => {
                let mut identifier = namespace
                    .as_ref()
                    .map(|value| normalise_namespace(value))
                    .unwrap_or_else(|| String::new());
                append_path_segments(&mut identifier, target_path);
                if *append_method_suffix {
                    append_suffix(&mut identifier, method);
                }
                HttpRouteResolution {
                    realm: RESERVED_HTTP_REALM.to_string(),
                    procedure: identifier,
                    method: method.to_string(),
                    protocol: protocol.to_string(),
                    path: request_path.to_string(),
                    query: query.map(|value| value.to_string()),
                    transport_auth: transport_auth.clone(),
                }
            }
            HttpRouteTarget::Namespace {
                realm,
                namespace,
                append_method_suffix,
            } => {
                let mut identifier = normalise_namespace(namespace);
                append_path_segments(&mut identifier, target_path);
                if *append_method_suffix {
                    append_suffix(&mut identifier, method);
                }
                HttpRouteResolution {
                    realm: realm.clone(),
                    procedure: identifier,
                    method: method.to_string(),
                    protocol: protocol.to_string(),
                    path: request_path.to_string(),
                    query: query.map(|value| value.to_string()),
                    transport_auth: transport_auth.clone(),
                }
            }
        }
    }
}

fn normalise_namespace(namespace: &str) -> String {
    let trimmed = namespace.trim().trim_matches('.');
    if trimmed.is_empty() {
        String::new()
    } else {
        format!("{}.", trimmed)
    }
}

fn append_path_segments(buffer: &mut String, path: &str) {
    let segments = segments_from_path(path);
    if segments.is_empty() {
        if !buffer.is_empty() {
            buffer.push_str("index");
        } else {
            buffer.push_str("index");
        }
        return;
    }
    for segment in segments {
        if !buffer.is_empty() && !buffer.ends_with('.') {
            buffer.push('.');
        }
        buffer.push_str(&segment);
    }
}

fn append_suffix(buffer: &mut String, method: &str) {
    let suffix = method.to_ascii_lowercase();
    if !buffer.is_empty() {
        buffer.push('.');
    }
    buffer.push_str(&suffix);
}

fn route_relative_path(route_path: &str, request_path: &str) -> String {
    let Some(remainder) = request_path.strip_prefix(route_path) else {
        return request_path.to_string();
    };
    if remainder.is_empty() {
        return "/".to_string();
    }
    if remainder.starts_with('/') {
        remainder.to_string()
    } else {
        format!("/{remainder}")
    }
}

fn segments_from_path(path: &str) -> Vec<String> {
    let trimmed = if path.is_empty() { "/" } else { path };
    let stripped = trimmed.trim_matches('/');
    if stripped.is_empty() {
        return vec![];
    }
    stripped.split('/').map(sanitise_segment).collect()
}

fn sanitise_segment(segment: &str) -> String {
    let mut result = String::with_capacity(segment.len());
    for ch in segment.chars() {
        if ch.is_ascii_alphanumeric() {
            result.push(ch.to_ascii_lowercase());
        } else if ch == '_' || ch == '-' {
            result.push('_');
        } else {
            result.push('_');
        }
    }
    if result.is_empty() {
        "index".into()
    } else {
        result
    }
}
