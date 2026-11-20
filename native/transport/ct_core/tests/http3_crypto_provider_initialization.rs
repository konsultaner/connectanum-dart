use ct_core::{
    close_listener, listen_router_endpoint, listener_http3_port, shutdown, start_runtime,
};

#[test]
fn http3_can_be_the_first_tls_listener_in_a_fresh_process() {
    assert!(rustls::crypto::CryptoProvider::get_default().is_none());
    let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let config = serde_json::to_vec(&serde_json::json!({
        "schema": "connectanum.router", "version": 1,
        "endpoints": [{
            "host": "127.0.0.1", "port": 0, "tls_mode": "native", "protocols": ["http3"],
            "http": {"http3": {"enabled": true, "port": 0}},
            "sni_certificates": [{"hostname": "localhost", "certificate_chain_pem": identity.cert.pem(), "private_key_pem": identity.key_pair.serialize_pem()}]
        }]
    })).unwrap();
    start_runtime().unwrap();
    let started = listen_router_endpoint(&config, 0, 128);
    let result = started
        .as_ref()
        .map(|listener| listener_http3_port(*listener));
    if let Ok(listener) = started {
        close_listener(listener).unwrap();
    }
    shutdown().unwrap();
    assert!(result.is_ok(), "{result:?}");
    assert!(result.unwrap().unwrap().unwrap() > 0);
    let provider = rustls::crypto::CryptoProvider::get_default().unwrap();
    let expected = rustls::crypto::ring::default_provider();
    assert_eq!(
        provider
            .cipher_suites
            .iter()
            .map(|suite| suite.suite())
            .collect::<Vec<_>>(),
        expected
            .cipher_suites
            .iter()
            .map(|suite| suite.suite())
            .collect::<Vec<_>>()
    );
}
