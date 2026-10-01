use super::*;

async fn exchange(
    response: impl FnOnce(&str) -> Vec<u8>,
    target: &str,
) -> (Result<(), Error>, String) {
    time::timeout(Duration::from_secs(5), async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = async {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut request = Vec::new();
            while !request.ends_with(b"\r\n\r\n") {
                assert!(request.len() < 16 * 1024);
                request.push(socket.read_u8().await.unwrap());
            }
            let request = String::from_utf8(request).unwrap();
            let key = request
                .split("\r\n")
                .find_map(|line| {
                    let (name, value) = line.split_once(':')?;
                    name.eq_ignore_ascii_case("sec-websocket-key")
                        .then_some(value.trim())
                })
                .unwrap();
            assert_eq!(Base64Engine.decode(key).unwrap().len(), 16);
            socket
                .write_all(&response(&websocket_accept_value(key)))
                .await
                .unwrap();
            socket.shutdown().await.unwrap();
            request
        };
        let client = async {
            let mut stream = IoStream::plain(tokio::net::TcpStream::connect(addr).await.unwrap());
            let mut headers: Vec<_> = [
                "HOST",
                "Upgrade",
                "connection",
                "Sec-WebSocket-Version",
                "Sec-WebSocket-Key",
                "Sec-WebSocket-Protocol",
            ]
            .into_iter()
            .map(|name| (name.to_owned(), "ignored".to_owned()))
            .collect();
            headers.push(("X-Consumer".to_owned(), "test-client".to_owned()));
            perform_websocket_client_handshake(
                &mut stream,
                "example.test",
                81,
                false,
                target,
                "wamp.2.json",
                &headers,
                Duration::from_secs(1),
            )
            .await
        };
        let (request, result) = tokio::join!(server, client);
        (result, request)
    })
    .await
    .expect("bounded handshake exchange")
}

fn accepted_response(status: &str, accept: &str) -> String {
    format!("{status}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\nSec-WebSocket-Protocol: wamp.2.json\r\n\r\n")
}

#[tokio::test]
async fn websocket_client_preserves_valid_status_headers_and_request_fields() {
    for status in [
        "HTTP/1.1 101 Switching Protocols",
        "HTTP/1.0 101 Switching Protocols",
        "HTTP/1.1 101 ",
        "HTTP/1.0 101 ",
    ] {
        for target in ["", "/wamp?realm=public"] {
            let (result, request) = exchange(
                |accept| {
                    accepted_response(status, accept)
                        .replace("Upgrade: websocket", "uPgRaDe: WebSocket")
                        .replace("Connection: Upgrade", "cOnNeCtIoN: keep-alive, UpGrAdE")
                        .replace("Sec-WebSocket-Accept:", "sec-websocket-accept:")
                        .replace("Sec-WebSocket-Protocol:", "sec-websocket-protocol:")
                        .into_bytes()
                },
                target,
            )
            .await;
            assert!(result.is_ok(), "{status:?}: {result:?}");
            let expected_target = if target.is_empty() { "/" } else { target };
            assert!(request.starts_with(&format!("GET {expected_target} HTTP/1.1\r\n")));
            for line in [
                "Host: example.test:81",
                "Upgrade: websocket",
                "Connection: Upgrade",
                "Sec-WebSocket-Version: 13",
                "Sec-WebSocket-Protocol: wamp.2.json",
                "X-Consumer: test-client",
            ] {
                assert_eq!(
                    request
                        .split("\r\n")
                        .filter(|actual| *actual == line)
                        .count(),
                    1,
                    "{request}"
                );
            }
            assert!(!request.contains("ignored"));
        }
    }
}

#[tokio::test]
async fn websocket_client_rejects_missing_and_mismatched_upgrade_fields() {
    for (old, replacements, expected_error) in [
        (
            "Upgrade: websocket\r\n",
            ["", "Upgrade: h2c\r\n"],
            "missing Upgrade",
        ),
        (
            "Connection: Upgrade\r\n",
            ["", "Connection: notupgrade\r\n"],
            "missing Connection",
        ),
        (
            "Sec-WebSocket-Protocol: wamp.2.json\r\n",
            ["", "Sec-WebSocket-Protocol: wamp.2.cbor\r\n"],
            "unexpected protocol",
        ),
    ] {
        for replacement in replacements {
            let (result, _) = exchange(
                |accept| {
                    accepted_response("HTTP/1.1 101 Switching Protocols", accept)
                        .replace(old, replacement)
                        .into_bytes()
                },
                "/wamp",
            )
            .await;
            assert!(
                matches!(&result, Err(Error::Io(err)) if err.kind() == io::ErrorKind::InvalidData && err.to_string().contains(expected_error)),
                "{old:?} -> {replacement:?}: {result:?}"
            );
        }
    }
    for missing in [false, true] {
        let (result, _) = exchange(
            |accept| {
                let response = accepted_response("HTTP/1.1 101 Switching Protocols", accept);
                if missing {
                    response
                        .replace(&format!("Sec-WebSocket-Accept: {accept}\r\n"), "")
                        .into_bytes()
                } else {
                    response.replace(accept, "incorrect").into_bytes()
                }
            },
            "/wamp",
        )
        .await;
        let expected_error = if missing {
            "missing Sec-WebSocket-Accept"
        } else {
            "accept value mismatch"
        };
        assert!(
            matches!(&result, Err(Error::Io(err)) if err.kind() == io::ErrorKind::InvalidData && err.to_string().contains(expected_error)),
            "{result:?}"
        );
    }
}

#[tokio::test]
async fn websocket_client_rejects_malformed_headers_utf8_and_truncated_responses() {
    let (malformed, _) = exchange(
        |accept| {
            accepted_response("HTTP/1.1 101 Switching Protocols", accept)
                .replace("Upgrade: websocket", "broken header")
                .into_bytes()
        },
        "/wamp",
    )
    .await;
    assert!(
        matches!(&malformed, Err(Error::Io(err)) if err.kind() == io::ErrorKind::InvalidData && err.to_string().contains("invalid websocket handshake header")),
        "{malformed:?}"
    );
    let (utf8, _) = exchange(
        |accept| {
            let mut response =
                accepted_response("HTTP/1.1 101 Switching Protocols", accept).into_bytes();
            response[0] = 0xff;
            response
        },
        "/wamp",
    )
    .await;
    assert!(
        matches!(&utf8, Err(Error::Io(err)) if err.kind() == io::ErrorKind::InvalidData && err.to_string().contains("not valid utf-8")),
        "{utf8:?}"
    );
    let (truncated, _) = exchange(
        |_| b"HTTP/1.1 101 Switching Protocols\r\n".to_vec(),
        "/wamp",
    )
    .await;
    assert!(
        matches!(&truncated, Err(Error::Io(err)) if err.kind() == io::ErrorKind::UnexpectedEof),
        "{truncated:?}"
    );
    let (refused, _) = exchange(
        |accept| accepted_response("HTTP/1.1 403 Forbidden", accept).into_bytes(),
        "/wamp",
    )
    .await;
    assert!(
        matches!(&refused, Err(Error::Io(err)) if err.kind() == io::ErrorKind::ConnectionRefused),
        "{refused:?}"
    );
}

#[tokio::test]
async fn websocket_client_rejects_status_code_prefixes() {
    for status in [
        "HTTP/1.1 1010 Switching Protocols",
        "HTTP/1.0 101xyz",
        "HTTP/1.1 101.1",
        "HTTP/1.1 101",
    ] {
        let (result, _) = exchange(
            |accept| accepted_response(status, accept).into_bytes(),
            "/wamp",
        )
        .await;
        assert!(
            matches!(&result, Err(Error::Io(err)) if err.kind() == io::ErrorKind::ConnectionRefused),
            "accepted malformed status {status:?}: {result:?}"
        );
    }
}
