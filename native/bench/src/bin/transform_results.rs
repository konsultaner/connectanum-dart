use std::path::PathBuf;

use anyhow::Result;
use clap::Parser;

use connectanum_bench_orchestrator::artifacts::{load_reports_from_jsonl, write_artifact_bundle};

#[derive(Parser, Debug)]
#[command(
    author,
    version,
    about = "Transform bench JSONL reports into dashboard-friendly artifacts"
)]
struct Args {
    /// Input JSONL results file produced by http_stream.rs
    #[arg(long, default_value = "native/bench/artifacts/bench_results.jsonl")]
    input: PathBuf,

    /// Optional output directory for the generated .prom and .summary.json files
    #[arg(long)]
    output_dir: Option<PathBuf>,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let reports = load_reports_from_jsonl(&args.input)?;
    let paths = write_artifact_bundle(&reports, &args.input, args.output_dir.as_deref())?;
    println!("Wrote {}", paths.prometheus.display());
    println!("Wrote {}", paths.summary_json.display());
    Ok(())
}
