// A bounded stdio/lifecycle peer, not a router or a benchmark implementation.
use std::{
    env, fs, io,
    net::TcpListener,
    path::PathBuf,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

fn main() {
    let root = PathBuf::from(env::var_os("BENCH_CLI_TEST_ROOT").unwrap());
    let stop = root.join("stop");
    let _ = fs::remove_file(&stop);
    let mode = env::var("BENCH_CLI_TEST_MODE").unwrap();
    let stubborn = mode.starts_with("stubborn");
    let _owned_listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    fs::write(
        root.join("child-address"),
        _owned_listener.local_addr().unwrap().to_string(),
    )
    .unwrap();
    let mut record = format!(
        "library={}\nthreads={}\n",
        env::var("CONNECTANUM_NATIVE_LIB").unwrap(),
        env::var("CONNECTANUM_NATIVE_RUNTIME_THREADS").unwrap_or_else(|_| "auto".into())
    );
    for arg in env::args().skip(1) {
        record.push_str(&format!("arg={arg}\n"));
    }
    fs::write(root.join("child-arguments"), record).unwrap();
    if mode == "eof" {
        return;
    }
    if mode != "timeout" && mode != "stubborn-timeout" {
        println!("Running build hooks...READY");
    }
    let (send, receive) = mpsc::channel();
    thread::spawn(move || {
        let mut line = String::new();
        let result = match io::stdin().read_line(&mut line) {
            Ok(0) => "EOF".to_string(),
            Ok(_) => line.trim().to_string(),
            Err(error) => format!("ERROR:{error}"),
        };
        let _ = send.send(result);
    });
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        // The test owns this directory; its removal must also release the fixture.
        if !root.exists() {
            return;
        }
        let reason = if stop.exists() {
            Some("HTTP".to_string())
        } else if stubborn {
            None
        } else {
            receive.try_recv().ok()
        };
        if let Some(reason) = reason {
            fs::write(root.join("child-stopped"), reason).unwrap();
            return;
        }
        if Instant::now() >= deadline {
            fs::write(root.join("child-stopped"), "FIXTURE_DEADLINE").unwrap();
            std::process::exit(2);
        }
        thread::sleep(Duration::from_millis(5));
    }
}
