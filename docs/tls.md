# TLS Configuration

Connectanum endpoints support two production TLS strategies:

1. **Native TLS termination** (`tls.mode: native`) – TLS handshakes and decryption happen in the Rust transport runtime (`ct_core`).
2. **External termination** (`tls.mode: disabled`) – run the router on plain TCP behind a reverse proxy / load balancer that terminates TLS.

`tls.mode: dart` is reserved for a future pure-Dart TLS listener and is currently unsupported.

## Native TLS

Native TLS requires at least one SNI certificate entry.

```yaml
router:
  listeners:
    - endpoint: 0.0.0.0:8443
      authmethods: [anonymous]
      protocols: [rawsocket, websocket, http, http2]
      tls:
        mode: native
        sni_certificates:
          - hostname: example.com
            certificate_chain_file: /etc/connectanum/tls/fullchain.pem
            private_key_file: /etc/connectanum/tls/privkey.pem
      websocket:
        path: /ws
      http:
        alpn: [h2, http/1.1]
```

### `sni_certificates` entries

Each entry maps a hostname to a PEM-encoded certificate chain and private key:

- `hostname` – SNI name to match (e.g. `example.com`).
- `certificate_chain_pem` or `certificate_chain_file`
- `private_key_pem` or `private_key_file`

Note: SNI hostnames must be DNS names (not IP literals). If you need to serve a
certificate for an IP address, add the IP as a SAN in the certificate and use a
DNS hostname for `hostname`.

When loading a config file, the Dart config loader reads `*_file` values and passes the PEM strings to the native runtime. The native runtime does not read certificate files from disk.

### Default certificate fallback

If a client does not send SNI, the first entry in `sni_certificates` is used as the default certificate.

### Client certificate auth (mTLS)

Native TLS can optionally verify client certificates (mTLS) using a configured CA bundle:

```yaml
router:
  listeners:
    - endpoint: 0.0.0.0:8443
      tls:
        mode: native
        sni_certificates:
          - hostname: example.com
            certificate_chain_file: /etc/connectanum/tls/fullchain.pem
            private_key_file: /etc/connectanum/tls/privkey.pem
        client_auth:
          mode: required # or: optional
          ca_certificates_file: /etc/connectanum/tls/client_ca.pem
```

`client_auth.mode` values:

- `required`: clients must present a certificate that validates against the configured CA bundle.
- `optional`: clients may present a certificate; anonymous clients are still allowed.
- `disabled`/`none` (or omit `client_auth`): no client certificate verification.

Like `sni_certificates`, the Dart config loader reads `*_file` values and passes the PEM strings to the native runtime.

## HTTP/3 notes

HTTP/3 runs over QUIC (UDP) and requires TLS. If HTTP/3 is enabled for a listener, `tls.mode` must be `native` and `sni_certificates` must be present.

## External TLS termination

Set `tls.mode: disabled` to run the router on plain TCP and terminate TLS elsewhere. This works well for HTTP and WebSocket traffic behind common reverse proxies. RawSocket traffic typically requires a TCP/TLS capable proxy (or native TLS).
