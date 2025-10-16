use serde::Deserialize;
use std::sync::{Arc, OnceLock, RwLock};

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
    pub tls_mode: String,
    pub idle_timeout_ms: Option<u64>,
    pub max_http_content_length: Option<u64>,
    pub max_rawsocket_size_exponent: Option<u32>,
    pub websocket_path: Option<String>,
    pub sni_certificates: Option<Vec<SniCertificate>>,
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
    let cfg = config_lock().read().ok()?.clone()?;
    cfg.endpoints
        .iter()
        .find(|endpoint| endpoint.host.eq_ignore_ascii_case(host) && endpoint.port == port)
        .cloned()
        .map(Arc::new)
}
