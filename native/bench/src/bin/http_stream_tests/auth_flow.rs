use super::*;
use hyper::{server::conn::Http, service::service_fn, Response};
use std::net::Ipv4Addr;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::{net::TcpListener, sync::oneshot, task::JoinSet};

#[path = "auth_h3.rs"]
mod h3_peer;

#[derive(Clone, Debug, PartialEq)]
struct Observed {
    connection: usize,
    method: String,
    path: String,
    bearer: Option<String>,
    body: Vec<u8>,
}

#[derive(Clone)]
struct Step {
    request: Observed,
    status: u16,
    body: Vec<u8>,
}

impl Step {
    fn json(request: Value, status: u16, response: Value) -> Self {
        Self {
            request: Observed {
                connection: 0,
                method: "POST".into(),
                path: "/auth".into(),
                bearer: None,
                body: serde_json::to_vec(&request).unwrap(),
            },
            status,
            body: serde_json::to_vec(&response).unwrap(),
        }
    }
}

struct Peer {
    endpoint: HttpEndpoint,
    requests: Arc<Mutex<Vec<Observed>>>,
    connections: Arc<AtomicUsize>,
    stop: Option<oneshot::Sender<()>>,
    server: Option<tokio::task::JoinHandle<()>>,
}

impl Peer {
    async fn new(h2: bool, steps: Vec<Step>) -> Self {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let endpoint = HttpEndpoint {
            scheme: "http".into(),
            host: "127.0.0.1".into(),
            port: listener.local_addr().unwrap().port(),
            http3_port: None,
        };
        let requests = Arc::new(Mutex::new(Vec::new()));
        let recorded = Arc::clone(&requests);
        let connections = Arc::new(AtomicUsize::new(0));
        let accepted = Arc::clone(&connections);
        let steps = Arc::new(steps);
        let (stop, mut stopping) = oneshot::channel();
        let server = tokio::spawn(async move {
            let mut workers = JoinSet::new();
            loop {
                tokio::select! {
                    _ = &mut stopping => break,
                    Some(result) = workers.join_next(), if !workers.is_empty() => {
                        result.expect("HTTP fixture worker panicked");
                    }
                    connection = listener.accept() => {
                        let (socket, _) = connection.unwrap();
                        let connection_id = accepted.fetch_add(1, Ordering::SeqCst);
                        assert!(connection_id < 16);
                        let recorded = recorded.clone();
                        let steps = steps.clone();
                        workers.spawn(async move {
                            if h2 {
                                let mut connection = h2::server::handshake(socket).await.unwrap();
                                while let Some(request) = connection.accept().await {
                                    let (request, mut response) = request.unwrap();
                                    let (parts, mut body) = request.into_parts();
                                    let mut bytes = Vec::new();
                                    while let Some(chunk) = body.data().await {
                                        let chunk = chunk.unwrap();
                                        bytes.extend_from_slice(&chunk);
                                        body.flow_control().release_capacity(chunk.len()).unwrap();
                                    }
                                    let observed = Observed {
                                        connection: connection_id,
                                        method: parts.method.to_string(),
                                        path: parts.uri.path().into(),
                                        bearer: parts.headers.get("authorization")
                                            .map(|value| value.to_str().unwrap().into()),
                                        body: bytes,
                                    };
                                    let step = {
                                        let mut recorded = recorded.lock().unwrap();
                                        let index = recorded.len();
                                        recorded.push(observed);
                                        steps.get(index).cloned().expect("unexpected extra request")
                                    };
                                    let mut stream = response.send_response(
                                        http3::Response::builder().status(step.status).body(()).unwrap(),
                                        step.body.is_empty(),
                                    ).unwrap();
                                    if !step.body.is_empty() {
                                        stream.send_data(Bytes::from(step.body), true).unwrap();
                                    }
                                }
                                return;
                            }
                            let service = service_fn(move |request: Request<Body>| {
                                let recorded = recorded.clone();
                                let steps = steps.clone();
                                async move {
                                    let (parts, body) = request.into_parts();
                                    let body = hyper::body::to_bytes(body).await?;
                                    let mut recorded = recorded.lock().unwrap();
                                    let index = recorded.len();
                                    recorded.push(Observed {
                                        connection: connection_id,
                                        method: parts.method.to_string(),
                                        path: parts.uri.path().into(),
                                        bearer: parts.headers.get("authorization")
                                            .map(|value| value.to_str().unwrap().into()),
                                        body: body.to_vec(),
                                    });
                                    let response = if let Some(step) = steps.get(index) {
                                        Response::builder().status(step.status)
                                            .body(Body::from(step.body.clone())).unwrap()
                                    } else {
                                        Response::builder().status(500)
                                            .body(Body::from("unexpected extra request")).unwrap()
                                    };
                                    Ok::<_, hyper::Error>(response)
                                }
                            });
                            Http::new().http1_only(true)
                                .serve_connection(socket, service).await.unwrap();
                        });
                    }
                }
            }
            workers.abort_all();
            while let Some(result) = workers.join_next().await {
                if let Err(error) = result {
                    assert!(error.is_cancelled(), "fixture task failed: {error}");
                }
            }
        });
        Self {
            endpoint,
            requests,
            connections,
            stop: Some(stop),
            server: Some(server),
        }
    }

    async fn finish(mut self) -> (usize, Vec<Observed>) {
        self.stop.take().unwrap().send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(3), self.server.as_mut().unwrap())
            .await
            .expect("fixture shutdown timeout")
            .expect("fixture server failed");
        self.server.take();
        let requests = self.requests.lock().unwrap().clone();
        (self.connections.load(Ordering::SeqCst), requests)
    }
}

impl Drop for Peer {
    fn drop(&mut self) {
        if let Some(server) = &self.server {
            server.abort();
        }
    }
}

fn exchange(index: u32) -> [Step; 2] {
    [
        Step::json(
            json!({"realm":"fixture.realm", "authid":"reader", "authmethod":"ticket"}),
            401,
            json!({"state":format!("state-{index}"), "challenge":{}}),
        ),
        Step::json(
            json!({"state":format!("state-{index}"), "signature":"fixture-ticket", "extra":{}}),
            200,
            json!({"access_token":format!("access-{index}"), "refresh_token":format!("refresh-{index}")}),
        ),
    ]
}

fn script(flow: &str) -> (Vec<Step>, Vec<(u64, u64)>) {
    let mut steps = Vec::new();
    let mut sizes = Vec::new();
    if matches!(flow, "protected" | "refresh") {
        steps.extend(exchange(0));
    }
    for iteration in 0..3 {
        match flow {
            "login" => {
                let pair = exchange(iteration);
                sizes.push((
                    pair.iter().map(|step| step.request.body.len() as u64).sum(),
                    pair.iter().map(|step| step.body.len() as u64).sum(),
                ));
                steps.extend(pair);
            }
            "refresh" => {
                let step = Step::json(
                    json!({"grant_type":"refresh_token",
                    "refresh_token":format!("refresh-{iteration}")}),
                    200,
                    json!({"access_token":format!("access-{}", iteration+1),
                    "refresh_token":format!("refresh-{}", iteration+1)}),
                );
                sizes.push((step.request.body.len() as u64, step.body.len() as u64));
                steps.push(step);
            }
            "protected" | "preset" => {
                steps.push(Step {
                    request: Observed {
                        connection: 0,
                        method: "PUT".into(),
                        path: "/protected".into(),
                        bearer: Some(
                            if flow == "preset" {
                                "Bearer preset-token"
                            } else {
                                "Bearer access-0"
                            }
                            .into(),
                        ),
                        body: vec![0, 31, 0, 31, 0],
                    },
                    status: 200,
                    body: b"payload".to_vec(),
                });
                sizes.push((5, 7));
            }
            _ => unreachable!(),
        }
    }
    (steps, sizes)
}

fn workload(flow: &str, protocol: &str, reuse: bool) -> PreparedWorkload {
    let configured_flow = if flow == "preset" { "protected" } else { flow };
    let config: WorkloadConfig = toml::from_str(&format!(
        r#"
name = "auth-wire-contract"
protocol = "{protocol}"
method = "PUT"
path = "/protected"
iterations = 3
request_bytes = 5
response_bytes = 7
request_chunk_bytes = 2
reuse_connections = {reuse}
auth_flow = "{configured_flow}"
auth_path = "/auth"
auth_realm = "fixture.realm"
auth_method = "ticket"
auth_id = "reader"
auth_secret = "fixture-ticket"
{}"#,
        if flow == "preset" {
            "auth_bearer_token = \"preset-token\"\n"
        } else {
            ""
        }
    ))
    .unwrap();
    PreparedWorkload::from_config(&config).unwrap()
}

fn assign_connections(steps: &mut [Step], flow: &str, reuse: bool) {
    for (index, step) in steps.iter_mut().enumerate() {
        step.request.connection = if reuse {
            0
        } else {
            match flow {
                "login" => index / 2,
                "protected" | "refresh" => index.saturating_sub(2),
                "preset" => index,
                _ => unreachable!(),
            }
        };
    }
}

async fn run_worker(
    protocol: &str,
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
) -> Result<HttpWorkerExecution> {
    tokio::time::timeout(Duration::from_secs(5), async {
        match protocol {
            "h1" => run_h1_worker(endpoint, workload, 17).await,
            "h2" => run_h2_worker(endpoint, workload, 17).await,
            "h3" => run_h3_worker(endpoint, workload, 17).await,
            _ => unreachable!(),
        }
    })
    .await
    .expect("auth workload timeout")
}

async fn exercise(flow: &str, protocol: &str, reuse: bool) {
    let (mut steps, sizes) = script(flow);
    assign_connections(&mut steps, flow, reuse);
    let workload = workload(flow, protocol, reuse);
    let peer = if protocol == "h3" {
        h3_peer::spawn(steps.clone()).await
    } else {
        Peer::new(protocol == "h2", steps.clone()).await
    };
    let result = run_worker(protocol, peer.endpoint.clone(), workload).await;
    assert!(result.is_ok(), "auth workload failed: {:?}", result.err());
    let result = result.unwrap();
    let (connections, requests) = peer.finish().await;
    assert_eq!(
        requests,
        steps
            .into_iter()
            .map(|step| step.request)
            .collect::<Vec<_>>()
    );
    assert_eq!(result.samples.len(), 3);
    for (iteration, (sample, (request, response))) in result.samples.iter().zip(sizes).enumerate() {
        assert_eq!((sample.worker, sample.iteration), (17, iteration as u32));
        assert_eq!(
            (sample.request_bytes, sample.response_bytes),
            (request, response)
        );
        assert!(sample.latency_ms.is_finite() && sample.latency_ms >= 0.0);
        assert!(sample.http_fresh_connection_timing.is_none());
        assert!(sample.http_phase_timing.is_none());
    }
    let expected_connections = if reuse { 1 } else { 3 };
    assert_eq!(connections, expected_connections, "accepted socket count");
    assert_eq!(result.connections_opened, expected_connections as u32);
}

macro_rules! auth_case {
    ($name:ident, $flow:literal, $protocol:literal, $reuse:literal) => {
        #[tokio::test]
        async fn $name() {
            exercise($flow, $protocol, $reuse).await;
        }
    };
}

auth_case!(h1_login_reuse, "login", "h1", true);
auth_case!(h1_login_fresh, "login", "h1", false);
auth_case!(h1_protected_reuse, "protected", "h1", true);
auth_case!(h1_protected_fresh, "protected", "h1", false);
auth_case!(h1_preset_reuse, "preset", "h1", true);
auth_case!(h1_preset_fresh, "preset", "h1", false);
auth_case!(h1_refresh_reuse, "refresh", "h1", true);
auth_case!(h1_refresh_fresh, "refresh", "h1", false);
auth_case!(h2_login_reuse, "login", "h2", true);
auth_case!(h2_login_fresh, "login", "h2", false);
auth_case!(h2_protected_reuse, "protected", "h2", true);
auth_case!(h2_protected_fresh, "protected", "h2", false);
auth_case!(h2_preset_reuse, "preset", "h2", true);
auth_case!(h2_preset_fresh, "preset", "h2", false);
auth_case!(h2_refresh_reuse, "refresh", "h2", true);
auth_case!(h2_refresh_fresh, "refresh", "h2", false);
auth_case!(h3_login_reuse, "login", "h3", true);
auth_case!(h3_login_fresh, "login", "h3", false);
auth_case!(h3_protected_reuse, "protected", "h3", true);
auth_case!(h3_protected_fresh, "protected", "h3", false);
auth_case!(h3_preset_reuse, "preset", "h3", true);
auth_case!(h3_preset_fresh, "preset", "h3", false);
auth_case!(h3_refresh_reuse, "refresh", "h3", true);
auth_case!(h3_refresh_fresh, "refresh", "h3", false);

async fn rejects_without_replay(protocol: &str, case: &str) {
    let (flow, index, status, body, expected_error) = match case {
        "challenge-status" => ("login", 0, 200, b"{}".as_slice(), "expected 401 challenge"),
        "challenge-json" => ("login", 0, 401, b"not-json".as_slice(), "decode JSON"),
        "challenge-state" => ("login", 0, 401, b"{}".as_slice(), "missing state"),
        "proof-rejected" => (
            "protected",
            1,
            403,
            b"{}".as_slice(),
            "expected 200 success",
        ),
        "proof-token" => (
            "protected",
            1,
            200,
            b"{}".as_slice(),
            "missing access_token",
        ),
        "refresh-rejected" => ("refresh", 2, 401, b"{}".as_slice(), "expected 200 success"),
        "refresh-token" => (
            "refresh",
            2,
            200,
            br#"{"access_token":"new"}"#.as_slice(),
            "missing refresh_token",
        ),
        "protected-rejected" => (
            "preset",
            0,
            403,
            b"denied".as_slice(),
            "unexpected protected",
        ),
        "protected-after-one" => (
            "preset",
            1,
            403,
            b"denied".as_slice(),
            "unexpected protected",
        ),
        "refresh-after-one" => ("refresh", 3, 401, b"{}".as_slice(), "expected 200 success"),
        _ => unreachable!(),
    };
    for reuse in [true, false] {
        let (mut steps, _) = script(flow);
        steps.truncate(index + 1);
        steps[index].status = status;
        steps[index].body = body.to_vec();
        assign_connections(&mut steps, flow, reuse);
        let peer = if protocol == "h3" {
            h3_peer::spawn(steps.clone()).await
        } else {
            Peer::new(protocol == "h2", steps.clone()).await
        };
        let result = run_worker(
            protocol,
            peer.endpoint.clone(),
            workload(flow, protocol, reuse),
        )
        .await;
        let (connections, requests) = peer.finish().await;
        let error = result
            .err()
            .expect("rejected exchange returned benchmark success");
        assert!(
            format!("{error:#}").contains(expected_error),
            "{case}: {error:#}"
        );
        assert_eq!(
            requests,
            steps
                .iter()
                .map(|step| step.request.clone())
                .collect::<Vec<_>>(),
            "rejected request must not be replayed or followed by more work"
        );
        assert_eq!(connections, steps.last().unwrap().request.connection + 1);
    }
}

macro_rules! rejection_case {
    ($name:ident, $case:literal) => {
        #[tokio::test]
        async fn $name() {
            for protocol in ["h1", "h2", "h3"] {
                rejects_without_replay(protocol, $case).await;
            }
        }
    };
}

rejection_case!(rejects_wrong_challenge_status, "challenge-status");
rejection_case!(rejects_invalid_challenge_json, "challenge-json");
rejection_case!(rejects_missing_challenge_state, "challenge-state");
rejection_case!(rejects_invalid_proof, "proof-rejected");
rejection_case!(rejects_missing_access_token, "proof-token");
rejection_case!(rejects_invalid_refresh, "refresh-rejected");
rejection_case!(rejects_missing_refresh_token, "refresh-token");
rejection_case!(rejects_protected_request, "protected-rejected");
rejection_case!(
    does_not_replay_after_protected_success,
    "protected-after-one"
);
rejection_case!(does_not_replay_after_refresh_success, "refresh-after-one");
