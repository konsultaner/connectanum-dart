use serde::{Deserialize, Deserializer};
use std::collections::HashSet;
use std::sync::{Arc, OnceLock, RwLock};
use std::time::Duration;

use crate::Error;

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
    pub max_http_content_length: Option<u64>,
    pub max_rawsocket_size_exponent: Option<u32>,
    pub websocket_path: Option<String>,
    #[serde(default)]
    pub sni_certificates: Vec<SniCertificate>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct SniCertificate {
    pub hostname: String,
    pub certificate_chain_pem: String,
    pub private_key_pem: String,
}

pub fn apply_router_config_bytes(bytes: &[u8]) -> Result<(), Error> {
    let parsed: RouterConfig =
        serde_json::from_slice(bytes).map_err(|err| Error::RouterConfigInvalid(err.to_string()))?;
    let mut sanctioned_ports: HashSet<(String, u16)> = HashSet::new();
    for endpoint in &parsed.endpoints {
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
