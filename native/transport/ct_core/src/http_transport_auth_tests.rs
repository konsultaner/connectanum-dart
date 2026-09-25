use super::*;

fn endpoint(
    tls_mode: config::TlsMode,
    client_auth: Option<config::ClientAuthMode>,
) -> config::EndpointRuntimeConfig {
    config::EndpointRuntimeConfig {
        host: "127.0.0.1".into(),
        port: 0,
        tls_mode,
        client_auth: client_auth.map(|mode| config::ClientAuthRuntime {
            mode,
            ca_certificates_pem: String::new(),
        }),
        protocols: vec![TransportProtocol::Http],
        idle_timeout: None,
        heartbeat_interval: None,
        heartbeat_timeout: None,
        handshake_timeout: Duration::from_secs(1),
        max_http_content_length: None,
        max_rawsocket_size_exponent: config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
        max_rawsocket_size: 1u64 << config::DEFAULT_RAWSOCKET_SIZE_EXPONENT,
        max_upgrade_exponent: None,
        outbound_send_queue_capacity: config::DEFAULT_OUTBOUND_SEND_QUEUE_CAPACITY,
        websocket_path: None,
        sni_certificates: vec![],
        http_routes: vec![],
        http: None,
    }
}

fn strings(headers: &[(&str, &str)]) -> Vec<(String, String)> {
    headers
        .iter()
        .map(|(name, value)| (name.to_string(), value.to_string()))
        .collect()
}

fn bytes(headers: &[(&str, &str)]) -> Vec<(Arc<[u8]>, Arc<[u8]>)> {
    headers
        .iter()
        .map(|(name, value)| (Arc::from(name.as_bytes()), Arc::from(value.as_bytes())))
        .collect()
}

fn failure_name(failure: Option<HttpTransportAuthFailure>) -> Option<&'static str> {
    failure.map(|value| match value {
        HttpTransportAuthFailure::BearerRequired => "bearer",
        HttpTransportAuthFailure::TlsRequired => "tls",
        HttpTransportAuthFailure::MutualTlsRequired => "mtls",
    })
}

#[test]
fn string_and_binary_transport_gates_preserve_failure_precedence() {
    use config::{ClientAuthMode as Client, TlsMode as Tls};
    // Each expected result is a contract oracle, not a call to another auth helper.
    let cases = [
        (false, false, false, Tls::Disabled, None, false, None),
        (
            true,
            false,
            false,
            Tls::Disabled,
            None,
            false,
            Some("bearer"),
        ),
        (true, false, false, Tls::Disabled, None, true, None),
        (false, true, false, Tls::Disabled, None, true, Some("tls")),
        (true, true, false, Tls::Native, None, false, Some("bearer")),
        (true, true, false, Tls::Native, None, true, None),
        (true, true, false, Tls::Dart, None, true, None),
        (true, true, true, Tls::Disabled, None, false, Some("mtls")),
        (
            true,
            true,
            true,
            Tls::Native,
            Some(Client::Disabled),
            true,
            Some("mtls"),
        ),
        (
            true,
            true,
            true,
            Tls::Native,
            Some(Client::Optional),
            true,
            Some("mtls"),
        ),
        (
            true,
            true,
            true,
            Tls::Disabled,
            Some(Client::Required),
            true,
            Some("tls"),
        ),
        (
            true,
            true,
            true,
            Tls::Native,
            Some(Client::Required),
            false,
            Some("bearer"),
        ),
        (
            true,
            true,
            true,
            Tls::Native,
            Some(Client::Required),
            true,
            None,
        ),
        (
            false,
            false,
            true,
            Tls::Native,
            Some(Client::Required),
            false,
            None,
        ),
    ];
    for (index, (bearer, tls, mtls, mode, client, token, expected)) in cases.into_iter().enumerate()
    {
        let requirements = config::HttpRouteTransportAuthRuntime {
            require_bearer: bearer,
            require_tls: tls,
            require_mtls: mtls,
            allow_unauthenticated_cors_preflight: false,
        };
        let endpoint = endpoint(mode, client);
        let headers = if token {
            vec![("Authorization", "Bearer test-token")]
        } else {
            vec![]
        };
        assert_eq!(
            failure_name(evaluate_http_transport_auth_string_headers(
                &requirements,
                &endpoint,
                "GET",
                &strings(&headers)
            )),
            expected,
            "string case {index}"
        );
        assert_eq!(
            failure_name(evaluate_http_transport_auth_bytes_headers(
                &requirements,
                &endpoint,
                "GET",
                &bytes(&headers)
            )),
            expected,
            "byte case {index}"
        );
    }
}

#[test]
fn preflight_exception_requires_opt_in_and_both_nonempty_headers() {
    let cases = [
        ("OPTIONS", "https://example.test", "POST", true),
        ("oPtIoNs", "https://example.test", "POST", true),
        ("GET", "https://example.test", "POST", false),
        ("OPTIONS", "", "POST", false),
        ("OPTIONS", " \t", "POST", false),
        ("OPTIONS", "https://example.test", "", false),
        ("OPTIONS", "https://example.test", "\t ", false),
    ];
    for (method, origin, requested_method, preflight) in cases {
        let headers = [
            ("oRiGiN", origin),
            ("Access-Control-Request-Method", requested_method),
        ];
        assert_eq!(
            is_cors_preflight_string(method, &strings(&headers)),
            preflight
        );
        assert_eq!(is_cors_preflight_bytes(method, &bytes(&headers)), preflight);
        for allowed in [false, true] {
            let requirements = config::HttpRouteTransportAuthRuntime {
                require_bearer: true,
                allow_unauthenticated_cors_preflight: allowed,
                ..Default::default()
            };
            let endpoint = endpoint(config::TlsMode::Native, None);
            let expected = if allowed && preflight {
                None
            } else {
                Some("bearer")
            };
            assert_eq!(
                failure_name(evaluate_http_transport_auth_string_headers(
                    &requirements,
                    &endpoint,
                    method,
                    &strings(&headers)
                )),
                expected
            );
            assert_eq!(
                failure_name(evaluate_http_transport_auth_bytes_headers(
                    &requirements,
                    &endpoint,
                    method,
                    &bytes(&headers)
                )),
                expected
            );
        }
    }
    for headers in [
        vec![],
        vec![("Origin", "https://example.test")],
        vec![("Access-Control-Request-Method", "POST")],
    ] {
        assert!(!is_cors_preflight_string("OPTIONS", &strings(&headers)));
        assert!(!is_cors_preflight_bytes("OPTIONS", &bytes(&headers)));
    }
}

#[test]
fn preflight_never_bypasses_tls_or_mutual_tls() {
    let headers = [
        ("Origin", "https://example.test"),
        ("Access-Control-Request-Method", "POST"),
    ];
    for (mtls, expected) in [(false, "tls"), (true, "mtls")] {
        let requirements = config::HttpRouteTransportAuthRuntime {
            require_bearer: true,
            require_tls: true,
            require_mtls: mtls,
            allow_unauthenticated_cors_preflight: true,
        };
        let endpoint = endpoint(config::TlsMode::Disabled, None);
        assert_eq!(
            failure_name(evaluate_http_transport_auth_string_headers(
                &requirements,
                &endpoint,
                "OPTIONS",
                &strings(&headers)
            )),
            Some(expected)
        );
        assert_eq!(
            failure_name(evaluate_http_transport_auth_bytes_headers(
                &requirements,
                &endpoint,
                "OPTIONS",
                &bytes(&headers)
            )),
            Some(expected)
        );
    }
}

#[test]
fn bearer_screening_handles_case_length_whitespace_and_utf8_boundaries() {
    // This screen checks presence only; token validation happens downstream.
    for (name, value, expected) in [
        ("authorization", "Bearer x", true),
        ("AUTHORIZATION", "bEaReR test-token", true),
        ("authorization", "Basic token", false),
        ("authorization", "Bearer ", false),
        ("authorization", "Bearer", false),
        ("authorization", "Bearer \t  ", false),
        ("authorization", "Bearer\tx", false),
        ("authorization", " Bearer x", false),
        ("proxy-authorization", "Bearer x", false),
        ("authorization", "xxxxxx\u{1f642}", false),
    ] {
        let headers = [(name, value)];
        assert_eq!(
            has_bearer_header_string(&strings(&headers)),
            expected,
            "{value:?}"
        );
        assert_eq!(
            has_bearer_header_bytes(&bytes(&headers)),
            expected,
            "{value:?}"
        );
    }
    assert!(!has_bearer_header_string(&[]));
    assert!(!has_bearer_header_bytes(&[]));
    let headers = [
        ("X-Other", "ignored"),
        ("Authorization", ""),
        ("Authorization", "Bearer later"),
    ];
    assert!(has_bearer_header_string(&strings(&headers)));
    assert!(has_bearer_header_bytes(&bytes(&headers)));
}

#[test]
fn malformed_binary_headers_do_not_satisfy_auth_or_preflight() {
    for (name, value) in [
        (&b"authorizatio\xff"[..], &b"Bearer x"[..]),
        (&b"authorization"[..], &b"Bearer \xff"[..]),
    ] {
        let headers = vec![(Arc::from(name), Arc::from(value))];
        assert!(!has_bearer_header_bytes(&headers));
        let requirements = config::HttpRouteTransportAuthRuntime {
            require_bearer: true,
            ..Default::default()
        };
        assert_eq!(
            failure_name(evaluate_http_transport_auth_bytes_headers(
                &requirements,
                &endpoint(config::TlsMode::Native, None),
                "GET",
                &headers
            )),
            Some("bearer")
        );
    }
    for (name, value) in [
        (&b"origi\xff"[..], &b"https://example.test"[..]),
        (&b"origin"[..], &b"\xff"[..]),
    ] {
        let headers = vec![
            (Arc::from(name), Arc::from(value)),
            (
                Arc::from(&b"access-control-request-method"[..]),
                Arc::from(&b"POST"[..]),
            ),
        ];
        assert!(!is_cors_preflight_bytes("OPTIONS", &headers));
        assert!(!has_non_empty_header_bytes(&headers, b"origin"));
    }
}
