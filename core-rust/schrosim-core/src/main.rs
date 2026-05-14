use chrono::{DateTime, SecondsFormat, Utc};
use ring::hmac;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::ops::{Index, IndexMut};
use std::process;
#[cfg(debug_assertions)]
use std::process::Command;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

const CLI_VERSION: &str = "0.2.0";
const COMPILER_NAME: &str = "rust-core-v2";
const CONTRACTION_POLICY: &str = "hybrid_auto";

const SCHEMA_MIN_VERSION: i64 = 1;
const SCHEMA_MAX_VERSION: i64 = 1;
const FOUNDRY_REGISTRY_CURRENT_SCHEMA_VERSION: i64 = 1;
const PARITY_ENABLED: bool = cfg!(debug_assertions);
const BENCH_MIN_WALL_DELTA_MS: f64 = 0.05;
const BENCH_MIN_EXEC_DELTA_MS: f64 = 0.001;

const FOCK_DISPLACE_TAYLOR_TERMS: usize = 60;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CliCommand {
    Version,
    Info,
    Run,
    Trace,
    Bench,
    Parity,
}

#[derive(Debug, Clone)]
struct RunOptions {
    path: String,
    backend_override: Option<String>,
    cutoff_override: Option<usize>,
    seed_override: Option<u64>,
    prod_mode: bool,
    foundry_registry_path: Option<String>,
    foundry_key: Option<String>,
}

#[derive(Debug, Clone)]
struct TraceOptions {
    run: RunOptions,
    role: String,
    max_frames: Option<usize>,
    ring_buffer: Option<usize>,
}

#[derive(Debug, Clone)]
struct BenchOptions {
    suite: BenchSuite,
    iterations: usize,
    warmup: usize,
    max_regression_pct: f64,
    baseline_path: Option<String>,
    write_baseline_path: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BenchSuite {
    Core,
    Scaling,
    All,
}

impl BenchSuite {
    fn as_str(self) -> &'static str {
        match self {
            Self::Core => "core",
            Self::Scaling => "scaling",
            Self::All => "all",
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum BenchInputSource {
    File(&'static str),
    GeneratedScaling { modes: usize, layers: usize },
}

#[derive(Debug, Clone, Copy)]
struct BenchCaseDefinition {
    name: &'static str,
    input: BenchInputSource,
    requested_backend: &'static str,
    expected_backend: &'static str,
}

const BENCHMARK_CORE_CASES: [BenchCaseDefinition; 5] = [
    BenchCaseDefinition {
        name: "basic_loss_gaussian",
        input: BenchInputSource::File("examples/basic_loss.json"),
        requested_backend: "gaussian",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "seeded_homodyne_gaussian",
        input: BenchInputSource::File("examples/seeded_homodyne.json"),
        requested_backend: "gaussian",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "fock_injection_fock",
        input: BenchInputSource::File("examples/fock_injection_smoke.json"),
        requested_backend: "fock",
        expected_backend: "fock",
    },
    BenchCaseDefinition {
        name: "fock_injection_hybrid",
        input: BenchInputSource::File("examples/fock_injection_smoke.json"),
        requested_backend: "hybrid",
        expected_backend: "fock",
    },
    BenchCaseDefinition {
        name: "complex_foundry_hybrid",
        input: BenchInputSource::File(
            "demos/circuit-ssamples/complex_foundry_circuit_compliant_runtime_input.json",
        ),
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
];

const BENCHMARK_SCALING_CASES: [BenchCaseDefinition; 6] = [
    BenchCaseDefinition {
        name: "scaling_mode2_depth24",
        input: BenchInputSource::GeneratedScaling {
            modes: 2,
            layers: 24,
        },
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "scaling_mode8_depth24",
        input: BenchInputSource::GeneratedScaling {
            modes: 8,
            layers: 24,
        },
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "scaling_mode16_depth24",
        input: BenchInputSource::GeneratedScaling {
            modes: 16,
            layers: 24,
        },
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "scaling_mode8_depth8",
        input: BenchInputSource::GeneratedScaling {
            modes: 8,
            layers: 8,
        },
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "scaling_mode8_depth32",
        input: BenchInputSource::GeneratedScaling {
            modes: 8,
            layers: 32,
        },
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
    BenchCaseDefinition {
        name: "scaling_mode8_depth64",
        input: BenchInputSource::GeneratedScaling {
            modes: 8,
            layers: 64,
        },
        requested_backend: "hybrid",
        expected_backend: "gaussian",
    },
];

#[derive(Debug, Clone)]
struct BenchCaseResult {
    name: String,
    path: String,
    backend_requested: String,
    backend_used: String,
    median_wall_ms: f64,
    median_exec_ms: f64,
    min_wall_ms: f64,
    max_wall_ms: f64,
    min_exec_ms: f64,
    max_exec_ms: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BenchBaselineCase {
    name: String,
    median_wall_ms: f64,
    median_exec_ms: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BenchBaselineDocument {
    schema_version: i64,
    #[serde(default)]
    suite: Option<String>,
    cases: Vec<BenchBaselineCase>,
}

#[cfg(debug_assertions)]
#[derive(Debug, Clone)]
struct ParityOptions {
    run: RunOptions,
    role: String,
    swift_exec: String,
}

#[derive(Debug, Deserialize)]
struct CircuitInput {
    schema_version: Option<i64>,
    modes: usize,
    backend: Option<String>,
    seed: Option<u64>,
    cutoff: Option<usize>,
    foundry: Option<FoundryInput>,
    foundry_profile: Option<FoundryProfileInput>,
    gates: Vec<GateInput>,
}

#[derive(Debug, Deserialize)]
struct FoundryInput {
    name: Option<String>,
    #[serde(rename = "max_modes")]
    max_modes: Option<i64>,
    #[serde(rename = "max_squeezing_r")]
    max_squeezing_r: Option<f64>,
    #[serde(rename = "allow_non_gaussian")]
    allow_non_gaussian: Option<bool>,
    #[serde(rename = "allow_measurements")]
    allow_measurements: Option<bool>,
    #[serde(rename = "mode_loss_eta")]
    mode_loss_eta: Option<Vec<f64>>,
    #[serde(rename = "inject_mode_loss")]
    inject_mode_loss: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct FoundryProfileInput {
    profile_id: String,
    version: i64,
}

#[derive(Debug, Clone)]
struct FoundrySpec {
    name: String,
    max_modes: Option<usize>,
    max_squeezing_r: Option<f64>,
    allow_non_gaussian: bool,
    allow_measurements: bool,
    mode_loss_eta: Vec<f64>,
    inject_mode_loss: bool,
}

#[derive(Debug, Deserialize)]
struct FoundryRegistry {
    #[serde(rename = "schema_version")]
    schema_version: i64,
    profiles: Vec<FoundryRegistryProfile>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
enum FoundryRegistryStatus {
    Draft,
    Approved,
    Deprecated,
}

impl FoundryRegistryStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Approved => "approved",
            Self::Deprecated => "deprecated",
        }
    }
}

#[derive(Debug, Deserialize)]
struct FoundryRegistryProfile {
    #[serde(rename = "profile_id")]
    profile_id: String,
    version: i64,
    status: FoundryRegistryStatus,
    #[serde(rename = "valid_from")]
    valid_from: String,
    #[serde(rename = "valid_to")]
    valid_to: Option<String>,
    approvers: Vec<String>,
    #[serde(rename = "change_ticket")]
    change_ticket: Option<String>,
    signature: Option<String>,
    spec: FoundryRegistrySpec,
}

#[derive(Debug, Deserialize)]
struct FoundryRegistrySpec {
    name: Option<String>,
    #[serde(rename = "max_modes")]
    max_modes: Option<i64>,
    #[serde(rename = "max_squeezing_r")]
    max_squeezing_r: Option<f64>,
    #[serde(rename = "allow_non_gaussian")]
    allow_non_gaussian: Option<bool>,
    #[serde(rename = "allow_measurements")]
    allow_measurements: Option<bool>,
    #[serde(rename = "mode_loss_eta")]
    mode_loss_eta: Option<Vec<f64>>,
    #[serde(rename = "inject_mode_loss")]
    inject_mode_loss: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct GateInput {
    #[serde(rename = "type")]
    gate_type: String,
    mode: Option<i64>,
    #[serde(rename = "mode_a")]
    mode_a: Option<i64>,
    #[serde(rename = "mode_b")]
    mode_b: Option<i64>,
    theta: Option<f64>,
    r: Option<f64>,
    q: Option<f64>,
    p: Option<f64>,
    eta: Option<f64>,
    #[serde(rename = "n_th")]
    n_th: Option<f64>,
    label: Option<String>,
    state: Option<String>,
    n: Option<i64>,
    alpha: Option<f64>,
    delta: Option<f64>,
    on: Option<i64>,
    #[serde(rename = "on_value_index")]
    on_value_index: Option<i64>,
    #[serde(rename = "on_comparator")]
    on_comparator: Option<String>,
    #[serde(rename = "on_threshold")]
    on_threshold: Option<f64>,
    #[serde(rename = "apply_type")]
    apply_type: Option<String>,
    #[serde(rename = "apply_mode")]
    apply_mode: Option<i64>,
    #[serde(rename = "apply_mode_a")]
    apply_mode_a: Option<i64>,
    #[serde(rename = "apply_mode_b")]
    apply_mode_b: Option<i64>,
    #[serde(rename = "apply_theta")]
    apply_theta: Option<f64>,
    #[serde(rename = "apply_r")]
    apply_r: Option<f64>,
    #[serde(rename = "apply_q")]
    apply_q: Option<f64>,
    #[serde(rename = "apply_p")]
    apply_p: Option<f64>,
    #[serde(rename = "apply_eta")]
    apply_eta: Option<f64>,
    #[serde(rename = "apply_n_th")]
    apply_n_th: Option<f64>,
    #[serde(rename = "apply_n")]
    apply_n: Option<i64>,
    #[serde(rename = "apply_alpha")]
    apply_alpha: Option<f64>,
    #[serde(rename = "apply_delta")]
    apply_delta: Option<f64>,
    #[serde(rename = "source_value_index")]
    source_value_index: Option<i64>,
    #[serde(rename = "gain_q")]
    gain_q: Option<f64>,
    #[serde(rename = "gain_p")]
    gain_p: Option<f64>,
    #[serde(rename = "bias_q")]
    bias_q: Option<f64>,
    #[serde(rename = "bias_p")]
    bias_p: Option<f64>,
    decoder: Option<String>,
    #[serde(rename = "lattice_spacing")]
    lattice_spacing: Option<f64>,
    #[serde(rename = "target_lattice_index")]
    target_lattice_index: Option<i64>,
}

#[derive(Debug, Clone, Copy)]
enum ClassicalComparator {
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
}

impl ClassicalComparator {
    fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "lt" | "<" => Some(Self::Lt),
            "le" | "<=" => Some(Self::Le),
            "gt" | ">" => Some(Self::Gt),
            "ge" | ">=" => Some(Self::Ge),
            "eq" | "==" => Some(Self::Eq),
            "ne" | "!=" => Some(Self::Ne),
            _ => None,
        }
    }

    fn eval(self, value: f64, threshold: f64) -> bool {
        const EPS: f64 = 1e-12;
        match self {
            Self::Lt => value < threshold,
            Self::Le => value <= threshold,
            Self::Gt => value > threshold,
            Self::Ge => value >= threshold,
            Self::Eq => (value - threshold).abs() <= EPS,
            Self::Ne => (value - threshold).abs() > EPS,
        }
    }
}

#[derive(Debug, Clone)]
struct ClassicalCondition {
    value_index: usize,
    comparator: ClassicalComparator,
    threshold: f64,
}

#[derive(Debug, Clone)]
struct ParsedCircuit {
    modes: usize,
    gates: Vec<Gate>,
}

#[derive(Debug, Clone)]
enum Gate {
    Phase {
        theta: f64,
        mode: usize,
    },
    Squeeze {
        r: f64,
        mode: usize,
    },
    BeamSplitter {
        theta: f64,
        mode_a: usize,
        mode_b: usize,
    },
    Displace {
        q: f64,
        p: f64,
        mode: usize,
    },
    Loss {
        eta: f64,
        mode: usize,
    },
    ThermalLoss {
        eta: f64,
        n_th: f64,
        mode: usize,
    },
    MeasureHomodyne {
        mode: usize,
        theta: f64,
    },
    MeasureHeterodyne {
        mode: usize,
    },
    InjectFock {
        n: usize,
        mode: usize,
    },
    InjectCat {
        alpha: f64,
        mode: usize,
    },
    InjectGkp {
        delta: f64,
        mode: usize,
    },
    FeedbackDisplace {
        on: usize,
        source_value_index: usize,
        gain_q: f64,
        gain_p: f64,
        bias_q: f64,
        bias_p: f64,
        mode: usize,
    },
    GkpDecodeDisplace {
        on: usize,
        source_value_index: usize,
        lattice_spacing: f64,
        target_lattice_index: i64,
        gain_q: f64,
        gain_p: f64,
        bias_q: f64,
        bias_p: f64,
        mode: usize,
    },
    ClassicalControl {
        on: usize,
        condition: Option<ClassicalCondition>,
        apply: Box<Gate>,
    },
    NoisePlaceholder {
        label: String,
    },
}

#[derive(Debug, Clone)]
struct TraceFrame {
    frame_index: usize,
    gate_index: Option<usize>,
    gate_type: String,
    mean_photon_number: f64,
    measurement_count: i64,
    frame_latency_ms: f64,
}

#[derive(Debug, Clone)]
struct QecRoundRecord {
    round: usize,
    gate_index: usize,
    measurement_index: usize,
    source_value_index: usize,
    mode: usize,
    syndrome_value: f64,
    decoder: String,
    lattice_spacing: f64,
    target_lattice_index: i64,
    nearest_lattice_index: i64,
    nearest_lattice_value: f64,
    residual: f64,
    correction_value: f64,
    applied_q: f64,
    applied_p: f64,
    logical_pass: bool,
}

#[derive(Debug, Clone)]
struct QecSummary {
    rounds_executed: usize,
    logical_pass_count: usize,
    logical_fail_count: usize,
    logical_pass: bool,
}

#[derive(Debug, Serialize)]
struct JsonTraceFrame {
    #[serde(rename = "frame_index")]
    frame_index: usize,
    #[serde(rename = "gate_index")]
    gate_index: Option<usize>,
    #[serde(rename = "gate_type")]
    gate_type: String,
    #[serde(rename = "mean_photon_number")]
    mean_photon_number: f64,
    #[serde(rename = "measurement_count")]
    measurement_count: i64,
    #[serde(rename = "frame_latency_ms")]
    frame_latency_ms: f64,
}

#[derive(Debug, Clone)]
struct ExecutionResult {
    backend_used: String,
    mean_photon_number: f64,
    measurement_count: i64,
    frames: Vec<TraceFrame>,
    trace_total_ms: f64,
    final_state: Value,
    qec_rounds: Vec<QecRoundRecord>,
    qec_summary: Option<QecSummary>,
}

#[derive(Debug, Clone)]
struct MeasurementRecord {
    values: Vec<f64>,
}

#[derive(Debug, Clone)]
struct ResolvedFoundryRuntime {
    spec: FoundrySpec,
    source: &'static str,
}

#[derive(Debug, Clone)]
struct TraceFrameCollectionResult {
    frames: Vec<TraceFrame>,
    original_count: usize,
    dropped_count: usize,
    downsampling_applied: bool,
    ring_buffer_applied: bool,
    max_frame_latency_ms: f64,
}

#[derive(Debug)]
struct RuntimePrepared {
    input: CircuitInput,
    source_circuit: ParsedCircuit,
    compiled_circuit: ParsedCircuit,
    foundry_spec: FoundrySpec,
    foundry_source: &'static str,
    execution: ExecutionResult,
    cutoff: usize,
    backend_requested: String,
    schema_version: i64,
}

type VecF = Vec<f64>;

#[derive(Debug, Clone)]
struct MatF {
    rows: usize,
    cols: usize,
    data: Vec<f64>,
}

impl MatF {
    fn zeros(rows: usize, cols: usize) -> Self {
        Self {
            rows,
            cols,
            data: vec![0.0; rows.saturating_mul(cols)],
        }
    }

    fn eye(size: usize) -> Self {
        let mut matrix = Self::zeros(size, size);
        for i in 0..size {
            matrix[(i, i)] = 1.0;
        }
        matrix
    }

    fn len(&self) -> usize {
        self.rows
    }
}

impl Index<usize> for MatF {
    type Output = [f64];

    fn index(&self, row: usize) -> &Self::Output {
        let start = row * self.cols;
        &self.data[start..start + self.cols]
    }
}

impl IndexMut<usize> for MatF {
    fn index_mut(&mut self, row: usize) -> &mut Self::Output {
        let start = row * self.cols;
        &mut self.data[start..start + self.cols]
    }
}

impl Index<(usize, usize)> for MatF {
    type Output = f64;

    fn index(&self, index: (usize, usize)) -> &Self::Output {
        let (row, col) = index;
        let pos = row * self.cols + col;
        &self.data[pos]
    }
}

impl IndexMut<(usize, usize)> for MatF {
    fn index_mut(&mut self, index: (usize, usize)) -> &mut Self::Output {
        let (row, col) = index;
        let pos = row * self.cols + col;
        &mut self.data[pos]
    }
}

#[derive(Debug, Clone)]
struct GaussianState {
    modes: usize,
    mean: VecF,
    cov: MatF,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Complex64 {
    re: f64,
    im: f64,
}

#[derive(Debug, Clone)]
struct FockState {
    cutoff: usize,
    psi: Vec<Complex64>,
}

#[derive(Debug, Clone)]
struct SeededRng {
    state: u64,
}

#[derive(Debug, Clone, Copy)]
struct GkpNearestLatticeDecode {
    lattice_spacing: f64,
    target_lattice_index: i64,
    nearest_lattice_index: i64,
    nearest_lattice_value: f64,
    residual: f64,
    correction: f64,
    logical_pass: bool,
}

struct GkpNearestLatticeDecoder;

impl GkpNearestLatticeDecoder {
    fn decode(
        syndrome_value: f64,
        lattice_spacing: f64,
        target_lattice_index: i64,
    ) -> GkpNearestLatticeDecode {
        let nearest_lattice_index = (syndrome_value / lattice_spacing).round() as i64;
        let nearest_lattice_value = nearest_lattice_index as f64 * lattice_spacing;
        let residual = syndrome_value - nearest_lattice_value;
        let correction = -nearest_lattice_value;
        let logical_pass = nearest_lattice_index == target_lattice_index;
        GkpNearestLatticeDecode {
            lattice_spacing,
            target_lattice_index,
            nearest_lattice_index,
            nearest_lattice_value,
            residual,
            correction,
            logical_pass,
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        emit_json(&usage_payload());
        process::exit(1);
    }

    let command = match args.first().map(String::as_str) {
        Some("version") => CliCommand::Version,
        Some("info") => CliCommand::Info,
        Some("run") => CliCommand::Run,
        Some("trace") => CliCommand::Trace,
        Some("bench") => CliCommand::Bench,
        Some("parity") => CliCommand::Parity,
        _ => {
            emit_json(&usage_payload());
            process::exit(1);
        }
    };
    let command_args = &args[1..];

    let exit_code = match command {
        CliCommand::Version => handle_version(),
        CliCommand::Info => handle_info(),
        CliCommand::Run => handle_run(command_args),
        CliCommand::Trace => handle_trace(command_args),
        CliCommand::Bench => handle_bench(command_args),
        CliCommand::Parity => handle_parity(command_args),
    };
    process::exit(exit_code);
}

fn handle_version() -> i32 {
    emit_json(&json!({
        "command": "version",
        "status": "success",
        "version": CLI_VERSION
    }));
    0
}

fn handle_info() -> i32 {
    emit_json(&json!({
        "command": "info",
        "status": "success",
        "version": CLI_VERSION,
        "schema": {
            "min_supported_version": SCHEMA_MIN_VERSION,
            "max_supported_version": SCHEMA_MAX_VERSION
        },
        "backends": {
            "gaussian": true,
            "fock": true,
            "hybrid": true
        },
        "features": {
            "trace": true,
            "bench": true,
            "parity": PARITY_ENABLED,
            "rust_core": true,
            "feedforward": true
        }
    }));
    0
}

fn handle_run(arguments: &[String]) -> i32 {
    let options = match parse_run_options(arguments) {
        Ok(options) => options,
        Err(error) => {
            emit_json(&json!({
                "command": "run",
                "status": "error",
                "error": error
            }));
            return 1;
        }
    };

    match run_internal(&options, false, "viewer", None, None) {
        Ok(runtime) => {
            let foundry_injected_gate_count = runtime
                .compiled_circuit
                .gates
                .len()
                .saturating_sub(runtime.source_circuit.gates.len());
            emit_json(&json!({
                "command": "run",
                "input": options.path,
                "schema_version": runtime.schema_version,
                "backend": runtime.execution.backend_used,
                "backend_requested": runtime.backend_requested,
                "compiler": COMPILER_NAME,
                "contraction_type": contraction_type(&runtime.execution.backend_used),
                "contraction_policy": CONTRACTION_POLICY,
                "modes": runtime.source_circuit.modes,
                "gate_count": runtime.compiled_circuit.gates.len(),
                "source_gate_count": runtime.source_circuit.gates.len(),
                "foundry": runtime.foundry_spec.name,
                "foundry_source": runtime.foundry_source,
                "foundry_injected_gate_count": foundry_injected_gate_count,
                "mean_photon_number": runtime.execution.mean_photon_number,
                "measurement_count": runtime.execution.measurement_count,
                "final_state": runtime.execution.final_state.clone(),
                "qec": qec_payload(&runtime.execution),
                "cutoff": runtime.cutoff,
                "provenance": {
                    "backend_version": format!("{}-rust", CLI_VERSION),
                    "seed": resolved_seed(&options, &runtime.input).map(|v| v.to_string()).unwrap_or_else(|| "none".to_string())
                },
                "status": "success"
            }));
            0
        }
        Err(error) => {
            emit_json(&json!({
                "command": "run",
                "input": options.path,
                "status": "error",
                "error": error
            }));
            1
        }
    }
}

fn handle_trace(arguments: &[String]) -> i32 {
    let options = match parse_trace_options(arguments) {
        Ok(options) => options,
        Err(error) => {
            emit_json(&json!({
                "command": "trace",
                "status": "error",
                "error": error
            }));
            return 1;
        }
    };

    match run_internal(
        &options.run,
        true,
        &options.role,
        options.max_frames,
        options.ring_buffer,
    ) {
        Ok(runtime) => {
            let foundry_injected_gate_count = runtime
                .compiled_circuit
                .gates
                .len()
                .saturating_sub(runtime.source_circuit.gates.len());
            let qec = qec_payload(&runtime.execution);
            let collection = collect_trace_frames(
                runtime.execution.frames,
                options.max_frames,
                options.ring_buffer,
            );
            let json_frames: Vec<JsonTraceFrame> = collection
                .frames
                .iter()
                .map(|frame| JsonTraceFrame {
                    frame_index: frame.frame_index,
                    gate_index: frame.gate_index,
                    gate_type: frame.gate_type.clone(),
                    mean_photon_number: frame.mean_photon_number,
                    measurement_count: frame.measurement_count,
                    frame_latency_ms: frame.frame_latency_ms,
                })
                .collect();

            emit_json(&json!({
                "command": "trace",
                "input": options.run.path,
                "schema_version": runtime.schema_version,
                "backend": runtime.execution.backend_used,
                "backend_requested": runtime.backend_requested,
                "compiler": COMPILER_NAME,
                "contraction_type": contraction_type(&runtime.execution.backend_used),
                "contraction_policy": CONTRACTION_POLICY,
                "modes": runtime.source_circuit.modes,
                "gate_count": runtime.compiled_circuit.gates.len(),
                "source_gate_count": runtime.source_circuit.gates.len(),
                "foundry": runtime.foundry_spec.name,
                "foundry_source": runtime.foundry_source,
                "foundry_injected_gate_count": foundry_injected_gate_count,
                "mean_photon_number": runtime.execution.mean_photon_number,
                "measurement_count": runtime.execution.measurement_count,
                "final_state": runtime.execution.final_state.clone(),
                "qec": qec,
                "cutoff": runtime.cutoff,
                "playback_suggested_frame_ms": 120,
                "trace_frame_count": json_frames.len(),
                "trace_original_frame_count": collection.original_count,
                "trace_dropped_frame_count": collection.dropped_count,
                "trace_downsampling_applied": collection.downsampling_applied,
                "trace_ring_buffer_applied": collection.ring_buffer_applied,
                "trace_total_ms": runtime.execution.trace_total_ms,
                "trace_max_frame_latency_ms": collection.max_frame_latency_ms,
                "frames": json_frames,
                "provenance": {
                    "backend_version": format!("{}-rust", CLI_VERSION),
                    "seed": resolved_seed(&options.run, &runtime.input).map(|v| v.to_string()).unwrap_or_else(|| "none".to_string())
                },
                "trace_role": options.role,
                "status": "success"
            }));
            0
        }
        Err(error) => {
            emit_json(&json!({
                "command": "trace",
                "input": options.run.path,
                "status": "error",
                "error": error
            }));
            1
        }
    }
}

fn handle_bench(arguments: &[String]) -> i32 {
    let options = match parse_bench_options(arguments) {
        Ok(options) => options,
        Err(error) => {
            emit_json(&json!({
                "command": "bench",
                "status": "error",
                "error": error
            }));
            return 1;
        }
    };

    let results = match run_benchmarks(&options) {
        Ok(results) => results,
        Err(error) => {
            emit_json(&json!({
                "command": "bench",
                "status": "error",
                "error": error
            }));
            return 1;
        }
    };

    if let Some(path) = options.write_baseline_path.as_deref() {
        if let Err(error) = write_bench_baseline(path, &results, options.suite) {
            emit_json(&json!({
                "command": "bench",
                "status": "error",
                "error": error
            }));
            return 1;
        }
    }

    let regressions = if let Some(path) = options.baseline_path.as_deref() {
        match load_bench_baseline(path).and_then(|baseline| {
            validate_bench_baseline_suite(&baseline, options.suite)?;
            find_benchmark_regressions(&results, &baseline, options.max_regression_pct)
        }) {
            Ok(regressions) => regressions,
            Err(error) => {
                emit_json(&json!({
                    "command": "bench",
                    "status": "error",
                    "error": error
                }));
                return 1;
            }
        }
    } else {
        Vec::new()
    };

    let summary: Vec<Value> = results
        .iter()
        .map(|result| {
            json!({
                "name": result.name,
                "path": result.path,
                "backend_requested": result.backend_requested,
                "backend_used": result.backend_used,
                "median_wall_ms": round4(result.median_wall_ms),
                "median_exec_ms": round4(result.median_exec_ms),
                "min_wall_ms": round4(result.min_wall_ms),
                "max_wall_ms": round4(result.max_wall_ms),
                "min_exec_ms": round4(result.min_exec_ms),
                "max_exec_ms": round4(result.max_exec_ms),
            })
        })
        .collect();

    let ok = regressions.is_empty();
    emit_json(&json!({
        "command": "bench",
        "status": if ok { "success" } else { "error" },
        "suite": options.suite.as_str(),
        "build_profile": if cfg!(debug_assertions) { "debug" } else { "release" },
        "iterations": options.iterations,
        "warmup": options.warmup,
        "max_regression_pct": options.max_regression_pct,
        "baseline_path": options.baseline_path,
        "write_baseline_path": options.write_baseline_path,
        "cases": summary,
        "regressions": regressions,
    }));

    if ok {
        0
    } else {
        1
    }
}

fn run_benchmarks(options: &BenchOptions) -> Result<Vec<BenchCaseResult>, String> {
    let cases = benchmark_cases_for_suite(options.suite);
    let mut results: Vec<BenchCaseResult> = Vec::with_capacity(cases.len());

    for case in cases {
        let mut wall_samples: Vec<f64> = Vec::with_capacity(options.iterations);
        let mut exec_samples: Vec<f64> = Vec::with_capacity(options.iterations);

        let (input_path, cleanup_path) = prepare_benchmark_case_input(case)?;
        let run_options = RunOptions {
            path: input_path.clone(),
            backend_override: Some(case.requested_backend.to_string()),
            cutoff_override: None,
            seed_override: None,
            prod_mode: false,
            foundry_registry_path: None,
            foundry_key: None,
        };

        let case_result = (|| -> Result<BenchCaseResult, String> {
            for idx in 0..(options.warmup + options.iterations) {
                let started = Instant::now();
                let runtime = run_internal(&run_options, false, "viewer", None, None)
                    .map_err(|error| format!("Benchmark case '{}' failed: {}", case.name, error))?;
                if runtime.execution.backend_used != case.expected_backend {
                    return Err(format!(
                        "Benchmark case '{}' expected backend_used '{}' but got '{}'",
                        case.name, case.expected_backend, runtime.execution.backend_used
                    ));
                }
                let wall_ms = started.elapsed().as_secs_f64() * 1000.0;

                if idx >= options.warmup {
                    wall_samples.push(wall_ms);
                    exec_samples.push(runtime.execution.trace_total_ms);
                }
            }

            if wall_samples.is_empty() || exec_samples.is_empty() {
                return Err(format!(
                    "Benchmark case '{}' did not collect any samples",
                    case.name
                ));
            }

            let min_wall_ms = wall_samples
                .iter()
                .copied()
                .fold(f64::INFINITY, |acc, value| acc.min(value));
            let max_wall_ms = wall_samples
                .iter()
                .copied()
                .fold(f64::NEG_INFINITY, |acc, value| acc.max(value));
            let min_exec_ms = exec_samples
                .iter()
                .copied()
                .fold(f64::INFINITY, |acc, value| acc.min(value));
            let max_exec_ms = exec_samples
                .iter()
                .copied()
                .fold(f64::NEG_INFINITY, |acc, value| acc.max(value));

            Ok(BenchCaseResult {
                name: case.name.to_string(),
                path: benchmark_case_display_path(case, &input_path),
                backend_requested: case.requested_backend.to_string(),
                backend_used: case.expected_backend.to_string(),
                median_wall_ms: median(&wall_samples),
                median_exec_ms: median(&exec_samples),
                min_wall_ms,
                max_wall_ms,
                min_exec_ms,
                max_exec_ms,
            })
        })();

        if let Some(path) = cleanup_path {
            let _ = fs::remove_file(path);
        }
        results.push(case_result?);
    }

    Ok(results)
}

fn benchmark_cases_for_suite(suite: BenchSuite) -> Vec<BenchCaseDefinition> {
    match suite {
        BenchSuite::Core => BENCHMARK_CORE_CASES.to_vec(),
        BenchSuite::Scaling => BENCHMARK_SCALING_CASES.to_vec(),
        BenchSuite::All => {
            let mut cases =
                Vec::with_capacity(BENCHMARK_CORE_CASES.len() + BENCHMARK_SCALING_CASES.len());
            cases.extend_from_slice(&BENCHMARK_CORE_CASES);
            cases.extend_from_slice(&BENCHMARK_SCALING_CASES);
            cases
        }
    }
}

fn benchmark_case_display_path(case: BenchCaseDefinition, resolved_path: &str) -> String {
    match case.input {
        BenchInputSource::File(path) => path.to_string(),
        BenchInputSource::GeneratedScaling { modes, layers } => {
            format!("generated://scaling?modes={modes}&layers={layers}&path={resolved_path}")
        }
    }
}

fn prepare_benchmark_case_input(
    case: BenchCaseDefinition,
) -> Result<(String, Option<String>), String> {
    match case.input {
        BenchInputSource::File(path) => Ok((path.to_string(), None)),
        BenchInputSource::GeneratedScaling { modes, layers } => {
            let unique_suffix = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|value| value.as_nanos())
                .unwrap_or(0);
            let path = format!(
                "/tmp/schrosim-core-bench-{}-m{}-l{}-p{}-t{}.json",
                case.name,
                modes,
                layers,
                process::id(),
                unique_suffix
            );
            let payload = build_scaling_benchmark_input(modes, layers);
            let encoded = serde_json::to_string_pretty(&payload)
                .map_err(|error| format!("Failed to encode scaling benchmark input: {}", error))?;
            fs::write(&path, format!("{}\n", encoded)).map_err(|error| {
                format!(
                    "Failed to write scaling benchmark input '{}': {}",
                    path, error
                )
            })?;
            Ok((path.clone(), Some(path)))
        }
    }
}

fn build_scaling_benchmark_input(modes: usize, layers: usize) -> Value {
    let mut gates: Vec<Value> = Vec::new();
    gates.reserve(layers.saturating_mul(modes.saturating_mul(5)));

    for layer in 0..layers {
        let pair_start = layer % 2;
        for mode in 0..modes {
            let theta = 0.011 + 0.001 * (layer % 13) as f64 + 0.0007 * (mode % 11) as f64;
            let r = 0.06 + 0.003 * ((layer + mode) % 7) as f64;
            let q = 0.03 * (((layer + mode) % 5) as f64 - 2.0);
            let p = 0.03 * (((layer + 2 * mode) % 5) as f64 - 2.0);
            let eta = 0.992 + 0.001 * ((layer + mode) % 4) as f64;

            gates.push(json!({ "type": "phase", "theta": theta, "mode": mode }));
            gates.push(json!({ "type": "squeeze", "r": r, "mode": mode }));
            gates.push(json!({ "type": "displace", "q": q, "p": p, "mode": mode }));
            gates.push(json!({ "type": "loss", "eta": eta, "mode": mode }));
        }

        if modes > 1 {
            let mut mode = pair_start;
            while mode + 1 < modes {
                let theta = 0.08 + 0.004 * ((layer + mode) % 9) as f64;
                gates.push(json!({
                    "type": "beam_splitter",
                    "theta": theta,
                    "mode_a": mode,
                    "mode_b": mode + 1
                }));
                mode += 2;
            }
        }
    }

    json!({
        "schema_version": 1,
        "seed": 4242,
        "modes": modes,
        "backend": "hybrid",
        "cutoff": 20,
        "foundry": {
            "name": format!("scaling-bench-m{}-l{}", modes, layers),
            "max_modes": modes,
            "max_squeezing_r": 1.5,
            "allow_non_gaussian": true,
            "allow_measurements": true,
            "inject_mode_loss": false,
            "mode_loss_eta": vec![1.0; modes]
        },
        "gates": gates
    })
}

fn median(values: &[f64]) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_by(|lhs, rhs| lhs.partial_cmp(rhs).unwrap_or(std::cmp::Ordering::Equal));
    let mid = sorted.len() / 2;
    if sorted.len() % 2 == 1 {
        sorted[mid]
    } else {
        (sorted[mid - 1] + sorted[mid]) * 0.5
    }
}

fn load_bench_baseline(path: &str) -> Result<BenchBaselineDocument, String> {
    let raw = fs::read_to_string(path)
        .map_err(|error| format!("Failed to read benchmark baseline '{}': {}", path, error))?;
    let doc: BenchBaselineDocument = serde_json::from_str(&raw)
        .map_err(|error| format!("Invalid benchmark baseline JSON '{}': {}", path, error))?;
    if doc.schema_version != 1 {
        return Err(format!(
            "Unsupported benchmark baseline schema_version '{}'; expected 1",
            doc.schema_version
        ));
    }
    Ok(doc)
}

fn validate_bench_baseline_suite(
    baseline: &BenchBaselineDocument,
    expected_suite: BenchSuite,
) -> Result<(), String> {
    if let Some(actual_suite) = baseline.suite.as_deref() {
        if actual_suite != expected_suite.as_str() {
            return Err(format!(
                "Benchmark baseline suite mismatch: baseline is '{}', requested suite is '{}'",
                actual_suite,
                expected_suite.as_str()
            ));
        }
    }
    Ok(())
}

fn write_bench_baseline(
    path: &str,
    results: &[BenchCaseResult],
    suite: BenchSuite,
) -> Result<(), String> {
    let baseline = BenchBaselineDocument {
        schema_version: 1,
        suite: Some(suite.as_str().to_string()),
        cases: results
            .iter()
            .map(|result| BenchBaselineCase {
                name: result.name.clone(),
                median_wall_ms: round4(result.median_wall_ms),
                median_exec_ms: round4(result.median_exec_ms),
            })
            .collect(),
    };

    let encoded = serde_json::to_string_pretty(&baseline)
        .map_err(|error| format!("Failed to encode benchmark baseline: {}", error))?;
    fs::write(path, format!("{}\n", encoded))
        .map_err(|error| format!("Failed to write benchmark baseline '{}': {}", path, error))
}

fn find_benchmark_regressions(
    results: &[BenchCaseResult],
    baseline: &BenchBaselineDocument,
    max_regression_pct: f64,
) -> Result<Vec<Value>, String> {
    let allowed_factor = 1.0 + max_regression_pct / 100.0;
    let mut regressions: Vec<Value> = Vec::new();

    for result in results {
        let baseline_case = baseline
            .cases
            .iter()
            .find(|entry| entry.name == result.name)
            .ok_or_else(|| {
                format!(
                    "Missing baseline entry for benchmark case '{}'",
                    result.name
                )
            })?;

        let wall_limit = baseline_case.median_wall_ms * allowed_factor;
        let wall_limit = wall_limit.max(baseline_case.median_wall_ms + BENCH_MIN_WALL_DELTA_MS);
        if result.median_wall_ms > wall_limit {
            regressions.push(json!({
                "name": result.name,
                "metric": "median_wall_ms",
                "baseline": round4(baseline_case.median_wall_ms),
                "current": round4(result.median_wall_ms),
                "limit": round4(wall_limit),
            }));
        }

        let exec_limit = baseline_case.median_exec_ms * allowed_factor;
        let exec_limit = exec_limit.max(baseline_case.median_exec_ms + BENCH_MIN_EXEC_DELTA_MS);
        if result.median_exec_ms > exec_limit {
            regressions.push(json!({
                "name": result.name,
                "metric": "median_exec_ms",
                "baseline": round4(baseline_case.median_exec_ms),
                "current": round4(result.median_exec_ms),
                "limit": round4(exec_limit),
            }));
        }
    }

    Ok(regressions)
}

#[cfg(debug_assertions)]
fn handle_parity(arguments: &[String]) -> i32 {
    let options = match parse_parity_options(arguments) {
        Ok(options) => options,
        Err(error) => {
            emit_json(&json!({
                "command": "parity",
                "status": "error",
                "error": error
            }));
            return 1;
        }
    };

    let rust_run = match run_internal(&options.run, true, &options.role, None, None) {
        Ok(run) => run,
        Err(error) => {
            emit_json(&json!({
                "command": "parity",
                "input": options.run.path,
                "status": "error",
                "error": format!("Rust execution failed: {}", error)
            }));
            return 1;
        }
    };

    let rust_trace_frames = rust_run.execution.frames.len();

    let mut swift_run_args = vec![
        "run".to_string(),
        "schrosim-cli".to_string(),
        "run".to_string(),
        options.run.path.clone(),
        "--backend".to_string(),
        rust_run.backend_requested.clone(),
    ];
    if let Some(cutoff) = options.run.cutoff_override {
        swift_run_args.push("--cutoff".to_string());
        swift_run_args.push(cutoff.to_string());
    }
    if let Some(seed) = options.run.seed_override {
        swift_run_args.push("--seed".to_string());
        swift_run_args.push(seed.to_string());
    }
    if options.run.prod_mode {
        swift_run_args.push("--prod".to_string());
    }
    if let Some(path) = &options.run.foundry_registry_path {
        swift_run_args.push("--foundry-registry".to_string());
        swift_run_args.push(path.clone());
    }
    if let Some(key) = &options.run.foundry_key {
        swift_run_args.push("--foundry-key".to_string());
        swift_run_args.push(key.clone());
    }

    let swift_run_value = match invoke_swift_cli_json(&options.swift_exec, &swift_run_args) {
        Ok(value) => value,
        Err(error) => {
            emit_json(&json!({
                "command": "parity",
                "input": options.run.path,
                "status": "error",
                "error": format!("Swift run failed: {}", error)
            }));
            return 1;
        }
    };
    if swift_run_value.get("status").and_then(Value::as_str) != Some("success") {
        emit_json(&json!({
            "command": "parity",
            "input": options.run.path,
            "status": "error",
            "error": format!("Swift run returned non-success: {}", swift_run_value)
        }));
        return 1;
    }

    let mut swift_trace_args = vec![
        "run".to_string(),
        "schrosim-cli".to_string(),
        "trace".to_string(),
        options.run.path.clone(),
        "--backend".to_string(),
        rust_run.backend_requested.clone(),
        "--trace-role".to_string(),
        options.role.clone(),
    ];
    if let Some(cutoff) = options.run.cutoff_override {
        swift_trace_args.push("--cutoff".to_string());
        swift_trace_args.push(cutoff.to_string());
    }
    if let Some(seed) = options.run.seed_override {
        swift_trace_args.push("--seed".to_string());
        swift_trace_args.push(seed.to_string());
    }
    if options.run.prod_mode {
        swift_trace_args.push("--prod".to_string());
    }
    if let Some(path) = &options.run.foundry_registry_path {
        swift_trace_args.push("--foundry-registry".to_string());
        swift_trace_args.push(path.clone());
    }
    if let Some(key) = &options.run.foundry_key {
        swift_trace_args.push("--foundry-key".to_string());
        swift_trace_args.push(key.clone());
    }

    let swift_trace_value = match invoke_swift_cli_json(&options.swift_exec, &swift_trace_args) {
        Ok(value) => value,
        Err(error) => {
            emit_json(&json!({
                "command": "parity",
                "input": options.run.path,
                "status": "error",
                "error": format!("Swift trace failed: {}", error)
            }));
            return 1;
        }
    };
    if swift_trace_value.get("status").and_then(Value::as_str) != Some("success") {
        emit_json(&json!({
            "command": "parity",
            "input": options.run.path,
            "status": "error",
            "error": format!("Swift trace returned non-success: {}", swift_trace_value)
        }));
        return 1;
    }

    let swift_mean = swift_run_value
        .get("mean_photon_number")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let swift_measurements = swift_run_value
        .get("measurement_count")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let swift_trace_frame_count = swift_trace_value
        .get("trace_frame_count")
        .and_then(Value::as_u64)
        .unwrap_or(0) as usize;

    let rust_mean = rust_run.execution.mean_photon_number;
    let rust_measurements = rust_run.execution.measurement_count;

    emit_json(&json!({
        "command": "parity",
        "input": options.run.path,
        "backend_requested": rust_run.backend_requested,
        "status": "success",
        "rust": {
            "mean_photon_number": round4(rust_mean),
            "measurement_count": rust_measurements,
            "trace_frame_count": rust_trace_frames
        },
        "swift": {
            "mean_photon_number": round4(swift_mean),
            "measurement_count": swift_measurements,
            "trace_frame_count": swift_trace_frame_count
        },
        "delta": {
            "mean_photon_number": round6(rust_mean - swift_mean),
            "measurement_count": rust_measurements - swift_measurements,
            "trace_frame_count": rust_trace_frames as i64 - swift_trace_frame_count as i64
        }
    }));
    0
}

#[cfg(not(debug_assertions))]
fn handle_parity(_arguments: &[String]) -> i32 {
    emit_json(&json!({
        "command": "parity",
        "status": "error",
        "error": "Parity command is disabled in production builds"
    }));
    1
}

fn run_internal(
    options: &RunOptions,
    include_trace: bool,
    trace_role: &str,
    max_frames: Option<usize>,
    ring_buffer: Option<usize>,
) -> Result<RuntimePrepared, String> {
    let input = load_input(&options.path)?;
    let schema_version = resolve_schema_version(input.schema_version)?;
    let source_circuit = parse_circuit(&input)?;
    let foundry_runtime = resolve_foundry_spec(&input, options, source_circuit.modes)?;
    let foundry_spec = foundry_runtime.spec.clone();
    let compiled_circuit = compile_with_foundry(&source_circuit, &foundry_spec)?;

    let backend_requested = normalize_backend(
        options
            .backend_override
            .as_ref()
            .or(input.backend.as_ref())
            .map(String::as_str)
            .unwrap_or("auto"),
    );
    if !is_supported_backend(&backend_requested) {
        return Err(format!("Unsupported backend '{}'", backend_requested));
    }

    let cutoff = options.cutoff_override.or(input.cutoff).unwrap_or(20);
    if cutoff == 0 {
        return Err("Cutoff must be a positive integer".to_string());
    }
    let resolved_seed = resolved_seed(options, &input);
    let backend_used = resolve_execution_backend(&backend_requested, &compiled_circuit)?;

    let execution = if backend_used == "fock" {
        execute_fock(
            &compiled_circuit,
            cutoff,
            include_trace,
            resolved_seed,
            trace_role,
            max_frames,
            ring_buffer,
        )?
    } else {
        execute_gaussian(
            &compiled_circuit,
            include_trace,
            resolved_seed,
            trace_role,
            max_frames,
            ring_buffer,
        )?
    };

    Ok(RuntimePrepared {
        input,
        source_circuit,
        compiled_circuit,
        foundry_spec,
        foundry_source: foundry_runtime.source,
        execution,
        cutoff,
        backend_requested,
        schema_version,
    })
}

fn resolve_schema_version(version: Option<i64>) -> Result<i64, String> {
    let version =
        version.ok_or_else(|| "Missing required top-level field 'schema_version'".to_string())?;
    if !(SCHEMA_MIN_VERSION..=SCHEMA_MAX_VERSION).contains(&version) {
        return Err(format!(
            "Unsupported schema_version '{}'. Supported range: {}...{}",
            version, SCHEMA_MIN_VERSION, SCHEMA_MAX_VERSION
        ));
    }
    Ok(version)
}

fn resolved_seed(options: &RunOptions, input: &CircuitInput) -> Option<u64> {
    options.seed_override.or(input.seed)
}

fn normalize_backend(raw: &str) -> String {
    raw.trim().to_ascii_lowercase()
}

fn is_supported_backend(backend: &str) -> bool {
    matches!(backend, "auto" | "gaussian" | "fock" | "hybrid")
}

fn resolve_execution_backend(
    requested_backend: &str,
    circuit: &ParsedCircuit,
) -> Result<String, String> {
    match requested_backend {
        "gaussian" => Ok("gaussian".to_string()),
        "fock" => {
            assert_fock_compatible(circuit)?;
            Ok("fock".to_string())
        }
        "auto" | "hybrid" => {
            if requires_fock_path(circuit) {
                assert_fock_compatible(circuit)?;
                Ok("fock".to_string())
            } else {
                Ok("gaussian".to_string())
            }
        }
        other => Err(format!("Unsupported backend '{}'", other)),
    }
}

fn requires_fock_path(circuit: &ParsedCircuit) -> bool {
    circuit
        .gates
        .iter()
        .any(|gate| matches!(gate, Gate::InjectFock { .. } | Gate::InjectCat { .. }))
}

fn assert_fock_compatible(circuit: &ParsedCircuit) -> Result<(), String> {
    let mut reasons: Vec<String> = Vec::new();
    if circuit.modes != 1 {
        reasons.push(format!(
            "Fock path supports only single-mode circuits (got {} modes).",
            circuit.modes
        ));
    }

    let mut unsupported: BTreeSet<String> = BTreeSet::new();
    for gate in &circuit.gates {
        if !is_gate_supported_by_fock_path(gate) {
            unsupported.insert(gate_type_name(gate));
        }
    }
    if !unsupported.is_empty() {
        reasons.push(format!(
            "Unsupported gates for Fock path: {}. Supported: phase, displace, inject_fock, inject_cat.",
            unsupported.into_iter().collect::<Vec<_>>().join(", ")
        ));
    }

    if reasons.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "Fock execution path is incompatible. {}",
            reasons.join(" ")
        ))
    }
}

fn is_gate_supported_by_fock_path(gate: &Gate) -> bool {
    matches!(
        gate,
        Gate::Phase { .. }
            | Gate::Displace { .. }
            | Gate::InjectFock { .. }
            | Gate::InjectCat { .. }
    )
}

fn parse_circuit(input: &CircuitInput) -> Result<ParsedCircuit, String> {
    if input.modes == 0 {
        return Err("Circuit modes must be > 0".to_string());
    }

    let mut gates = Vec::with_capacity(input.gates.len());
    for gate in &input.gates {
        gates.push(parse_gate(input.modes, gate)?);
    }
    Ok(ParsedCircuit {
        modes: input.modes,
        gates,
    })
}

fn parse_gate(modes: usize, gate: &GateInput) -> Result<Gate, String> {
    let kind = normalize_gate_type(&gate.gate_type);
    let parsed = match kind.as_str() {
        "phase" | "rz" => Gate::Phase {
            theta: require_f64(gate.theta, &kind, "theta")?,
            mode: require_mode(gate.mode, modes, &kind, "mode")?,
        },
        "squeeze" => Gate::Squeeze {
            r: require_f64(gate.r, &kind, "r")?,
            mode: require_mode(gate.mode, modes, &kind, "mode")?,
        },
        "beam_splitter" | "beamsplitter" => {
            let mode_a = require_mode(gate.mode_a, modes, &kind, "mode_a")?;
            let mode_b = require_mode(gate.mode_b, modes, &kind, "mode_b")?;
            if mode_a == mode_b {
                return Err(format!(
                    "Gate '{}' must target two different modes (mode_a != mode_b)",
                    kind
                ));
            }
            Gate::BeamSplitter {
                theta: require_f64(gate.theta, &kind, "theta")?,
                mode_a,
                mode_b,
            }
        }
        "displace" => Gate::Displace {
            q: require_f64(gate.q, &kind, "q")?,
            p: require_f64(gate.p, &kind, "p")?,
            mode: require_mode(gate.mode, modes, &kind, "mode")?,
        },
        "loss" => {
            let eta = require_f64(gate.eta, &kind, "eta")?;
            validate_eta(eta)?;
            Gate::Loss {
                eta,
                mode: require_mode(gate.mode, modes, &kind, "mode")?,
            }
        }
        "thermal_loss" | "thermalloss" => {
            let eta = require_f64(gate.eta, &kind, "eta")?;
            validate_eta(eta)?;
            let n_th = require_f64(gate.n_th, &kind, "n_th")?;
            if n_th < 0.0 {
                return Err("Thermal n_th must be >= 0".to_string());
            }
            Gate::ThermalLoss {
                eta,
                n_th,
                mode: require_mode(gate.mode, modes, &kind, "mode")?,
            }
        }
        "measure_homodyne" | "homodyne" => Gate::MeasureHomodyne {
            mode: require_mode(gate.mode, modes, &kind, "mode")?,
            theta: require_f64(gate.theta, &kind, "theta")?,
        },
        "measure_heterodyne" | "heterodyne" => Gate::MeasureHeterodyne {
            mode: require_mode(gate.mode, modes, &kind, "mode")?,
        },
        "inject_fock" => {
            let n = require_i64(gate.n, &kind, "n")?;
            if n < 0 {
                return Err("inject_fock n must be >= 0".to_string());
            }
            Gate::InjectFock {
                n: n as usize,
                mode: require_mode(gate.mode, modes, &kind, "mode")?,
            }
        }
        "inject_cat" => Gate::InjectCat {
            alpha: require_f64(gate.alpha, &kind, "alpha")?,
            mode: require_mode(gate.mode, modes, &kind, "mode")?,
        },
        "inject_gkp" => {
            let delta = require_f64(gate.delta, &kind, "delta")?;
            if delta <= 0.0 {
                return Err("inject_gkp delta must be > 0".to_string());
            }
            Gate::InjectGkp {
                delta,
                mode: require_mode(gate.mode, modes, &kind, "mode")?,
            }
        }
        "feedback_displace" => {
            let on = require_i64(gate.on, &kind, "on")?;
            if on < 0 {
                return Err("feedback_displace on must be >= 0".to_string());
            }
            let source_value_index = gate.source_value_index.unwrap_or(0);
            if source_value_index < 0 {
                return Err("feedback_displace source_value_index must be >= 0".to_string());
            }
            let gain_q = require_f64(gate.gain_q, &kind, "gain_q")?;
            let gain_p = require_f64(gate.gain_p, &kind, "gain_p")?;
            let bias_q = gate.bias_q.unwrap_or(0.0);
            let bias_p = gate.bias_p.unwrap_or(0.0);
            if let Some(decoder_raw) = gate.decoder.as_deref() {
                let decoder = decoder_raw.trim().to_ascii_lowercase();
                if decoder == "gkp_nearest_lattice" || decoder == "gkp_rounding" {
                    let lattice_spacing = gate.lattice_spacing.unwrap_or(std::f64::consts::PI.sqrt());
                    if !lattice_spacing.is_finite() || lattice_spacing <= 0.0 {
                        return Err(
                            "feedback_displace decoder requires lattice_spacing > 0 and finite"
                                .to_string(),
                        );
                    }
                    let target_lattice_index = gate.target_lattice_index.unwrap_or(0);
                    if !gain_q.is_finite()
                        || !gain_p.is_finite()
                        || !bias_q.is_finite()
                        || !bias_p.is_finite()
                    {
                        return Err(
                            "feedback_displace requires finite gain_q, gain_p, bias_q, and bias_p"
                                .to_string(),
                        );
                    }
                    return Ok(Gate::GkpDecodeDisplace {
                        on: on as usize,
                        source_value_index: source_value_index as usize,
                        lattice_spacing,
                        target_lattice_index,
                        gain_q,
                        gain_p,
                        bias_q,
                        bias_p,
                        mode: require_mode(gate.mode, modes, &kind, "mode")?,
                    });
                }
                return Err(format!(
                    "Unsupported decoder '{}' for feedback_displace. Supported: gkp_nearest_lattice, gkp_rounding.",
                    decoder_raw
                ));
            }
            if !gain_q.is_finite() || !gain_p.is_finite() || !bias_q.is_finite() || !bias_p.is_finite()
            {
                return Err(
                    "feedback_displace requires finite gain_q, gain_p, bias_q, and bias_p"
                        .to_string(),
                );
            }
            Gate::FeedbackDisplace {
                on: on as usize,
                source_value_index: source_value_index as usize,
                gain_q,
                gain_p,
                bias_q,
                bias_p,
                mode: require_mode(gate.mode, modes, &kind, "mode")?,
            }
        }
        "gkp_decode_displace" => {
            let on = require_i64(gate.on, &kind, "on")?;
            if on < 0 {
                return Err("gkp_decode_displace on must be >= 0".to_string());
            }
            let source_value_index = gate.source_value_index.unwrap_or(0);
            if source_value_index < 0 {
                return Err("gkp_decode_displace source_value_index must be >= 0".to_string());
            }
            let lattice_spacing = gate.lattice_spacing.unwrap_or(std::f64::consts::PI.sqrt());
            if !lattice_spacing.is_finite() || lattice_spacing <= 0.0 {
                return Err("gkp_decode_displace lattice_spacing must be > 0 and finite".to_string());
            }
            let target_lattice_index = gate.target_lattice_index.unwrap_or(0);
            let gain_q = gate.gain_q.unwrap_or(1.0);
            let gain_p = gate.gain_p.unwrap_or(0.0);
            let bias_q = gate.bias_q.unwrap_or(0.0);
            let bias_p = gate.bias_p.unwrap_or(0.0);
            if !gain_q.is_finite() || !gain_p.is_finite() || !bias_q.is_finite() || !bias_p.is_finite()
            {
                return Err(
                    "gkp_decode_displace requires finite gain_q, gain_p, bias_q, and bias_p"
                        .to_string(),
                );
            }
            Gate::GkpDecodeDisplace {
                on: on as usize,
                source_value_index: source_value_index as usize,
                lattice_spacing,
                target_lattice_index,
                gain_q,
                gain_p,
                bias_q,
                bias_p,
                mode: require_mode(gate.mode, modes, &kind, "mode")?,
            }
        }
        "inject_non_gaussian" | "inject_nongaussian" | "inject" => {
            let label = gate
                .state
                .as_ref()
                .map(|v| v.trim().to_ascii_lowercase())
                .ok_or_else(|| "inject_non_gaussian requires 'state' field".to_string())?;
            match label.as_str() {
                "fock" => {
                    let n = require_i64(gate.n, &kind, "n")?;
                    if n < 0 {
                        return Err("inject_fock n must be >= 0".to_string());
                    }
                    Gate::InjectFock {
                        n: n as usize,
                        mode: require_mode(gate.mode, modes, &kind, "mode")?,
                    }
                }
                "cat" => Gate::InjectCat {
                    alpha: require_f64(gate.alpha, &kind, "alpha")?,
                    mode: require_mode(gate.mode, modes, &kind, "mode")?,
                },
                "gkp" => {
                    let delta = require_f64(gate.delta, &kind, "delta")?;
                    if delta <= 0.0 {
                        return Err("inject_gkp delta must be > 0".to_string());
                    }
                    Gate::InjectGkp {
                        delta,
                        mode: require_mode(gate.mode, modes, &kind, "mode")?,
                    }
                }
                _ => {
                    return Err(format!("Unsupported non-Gaussian state '{}'", label));
                }
            }
        }
        "if_then" | "classical_control" => {
            let on = require_i64(gate.on, &kind, "on")?;
            if on < 0 {
                return Err("Classical control 'on' must be >= 0".to_string());
            }
            let apply = parse_classical_apply(modes, gate)?;
            let condition = parse_classical_condition(gate)?;
            Gate::ClassicalControl {
                on: on as usize,
                condition,
                apply: Box::new(apply),
            }
        }
        "noise_placeholder" => Gate::NoisePlaceholder {
            label: gate
                .label
                .clone()
                .unwrap_or_else(|| "placeholder".to_string()),
        },
        _ => return Err(format!("Unsupported gate type '{}'", gate.gate_type)),
    };

    Ok(parsed)
}

fn parse_classical_condition(gate: &GateInput) -> Result<Option<ClassicalCondition>, String> {
    let has_any = gate.on_value_index.is_some()
        || gate.on_comparator.is_some()
        || gate.on_threshold.is_some();

    if !has_any {
        return Ok(None);
    }

    let value_index = require_i64(gate.on_value_index, "if_then", "on_value_index")?;
    if value_index < 0 {
        return Err("Classical control 'on_value_index' must be >= 0".to_string());
    }

    let comparator_raw = gate
        .on_comparator
        .as_ref()
        .ok_or_else(|| "Classical control requires 'on_comparator'".to_string())?;
    let comparator = ClassicalComparator::parse(comparator_raw).ok_or_else(|| {
        format!(
            "Unsupported classical comparator '{}'. Supported: lt, le, gt, ge, eq, ne.",
            comparator_raw
        )
    })?;

    let threshold = require_f64(gate.on_threshold, "if_then", "on_threshold")?;
    if !threshold.is_finite() {
        return Err("Classical control 'on_threshold' must be finite".to_string());
    }

    Ok(Some(ClassicalCondition {
        value_index: value_index as usize,
        comparator,
        threshold,
    }))
}

fn parse_classical_apply(modes: usize, gate: &GateInput) -> Result<Gate, String> {
    let apply_type = gate
        .apply_type
        .as_ref()
        .map(|v| v.trim().to_ascii_lowercase())
        .ok_or_else(|| "classical control requires apply_type".to_string())?;

    let parsed = match apply_type.as_str() {
        "phase" | "rz" => Gate::Phase {
            theta: require_f64(gate.apply_theta, &apply_type, "apply_theta")?,
            mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
        },
        "squeeze" => Gate::Squeeze {
            r: require_f64(gate.apply_r, &apply_type, "apply_r")?,
            mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
        },
        "beam_splitter" | "beamsplitter" => {
            let mode_a = require_mode(gate.apply_mode_a, modes, &apply_type, "apply_mode_a")?;
            let mode_b = require_mode(gate.apply_mode_b, modes, &apply_type, "apply_mode_b")?;
            if mode_a == mode_b {
                return Err("classical control beam_splitter requires apply_mode_a != apply_mode_b".to_string());
            }
            Gate::BeamSplitter {
                theta: require_f64(gate.apply_theta, &apply_type, "apply_theta")?,
                mode_a,
                mode_b,
            }
        }
        "displace" => Gate::Displace {
            q: require_f64(gate.apply_q, &apply_type, "apply_q")?,
            p: require_f64(gate.apply_p, &apply_type, "apply_p")?,
            mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
        },
        "loss" => {
            let eta = require_f64(gate.apply_eta, &apply_type, "apply_eta")?;
            validate_eta(eta)?;
            Gate::Loss {
                eta,
                mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
            }
        }
        "thermal_loss" | "thermalloss" => {
            let eta = require_f64(gate.apply_eta, &apply_type, "apply_eta")?;
            validate_eta(eta)?;
            let n_th = require_f64(gate.apply_n_th, &apply_type, "apply_n_th")?;
            if n_th < 0.0 {
                return Err("apply_n_th must be >= 0".to_string());
            }
            Gate::ThermalLoss {
                eta,
                n_th,
                mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
            }
        }
        "inject_fock" => {
            let n = require_i64(gate.apply_n, &apply_type, "apply_n")?;
            if n < 0 {
                return Err("apply_n must be >= 0".to_string());
            }
            Gate::InjectFock {
                n: n as usize,
                mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
            }
        }
        "inject_cat" => Gate::InjectCat {
            alpha: require_f64(gate.apply_alpha, &apply_type, "apply_alpha")?,
            mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
        },
        "inject_gkp" => {
            let delta = require_f64(gate.apply_delta, &apply_type, "apply_delta")?;
            if delta <= 0.0 {
                return Err("apply_delta must be > 0".to_string());
            }
            Gate::InjectGkp {
                delta,
                mode: require_mode(gate.apply_mode, modes, &apply_type, "apply_mode")?,
            }
        }
        other => {
            return Err(format!(
                "Unsupported if_then apply_type '{}'. Supported: phase, squeeze, beam_splitter, displace, loss, thermal_loss, inject_fock, inject_cat, inject_gkp.",
                other
            ))
        }
    };
    Ok(parsed)
}

fn execute_gaussian(
    circuit: &ParsedCircuit,
    include_trace: bool,
    seed: Option<u64>,
    _trace_role: &str,
    _max_frames: Option<usize>,
    _ring_buffer: Option<usize>,
) -> Result<ExecutionResult, String> {
    let mut state = GaussianState::vacuum(circuit.modes);
    let mut measurement_count: i64 = 0;
    let mut measurements: Vec<MeasurementRecord> = Vec::new();
    let mut qec_rounds: Vec<QecRoundRecord> = Vec::new();
    let mut frames: Vec<TraceFrame> = Vec::with_capacity(circuit.gates.len() + 1);
    if include_trace {
        frames.push(TraceFrame {
            frame_index: 0,
            gate_index: None,
            gate_type: "initial".to_string(),
            mean_photon_number: 0.0,
            measurement_count: 0,
            frame_latency_ms: 0.0,
        });
    }

    let mut rng = SeededRng::new(seed.unwrap_or_else(fallback_seed));
    let run_start = Instant::now();
    let mut max_latency_ms = 0.0;

    for (index, gate) in circuit.gates.iter().enumerate() {
        let gate_start = Instant::now();
        apply_gate_gaussian(
            &mut state,
            gate,
            index,
            &mut measurements,
            &mut measurement_count,
            &mut rng,
            &mut qec_rounds,
        )?;
        let latency_ms = gate_start.elapsed().as_secs_f64() * 1000.0;
        if latency_ms > max_latency_ms {
            max_latency_ms = latency_ms;
        }

        if include_trace {
            frames.push(TraceFrame {
                frame_index: index + 1,
                gate_index: Some(index),
                gate_type: gate_type_name(gate),
                mean_photon_number: mean_photon_number(&state),
                measurement_count,
                frame_latency_ms: latency_ms,
            });
        }
    }

    let trace_total_ms = run_start.elapsed().as_secs_f64() * 1000.0;
    Ok(ExecutionResult {
        backend_used: "gaussian".to_string(),
        mean_photon_number: mean_photon_number(&state),
        measurement_count,
        frames,
        trace_total_ms,
        final_state: gaussian_state_payload(&state),
        qec_summary: summarize_qec_rounds(&qec_rounds),
        qec_rounds,
    })
}

fn summarize_qec_rounds(rounds: &[QecRoundRecord]) -> Option<QecSummary> {
    if rounds.is_empty() {
        return None;
    }
    let logical_pass_count = rounds.iter().filter(|record| record.logical_pass).count();
    let logical_fail_count = rounds.len().saturating_sub(logical_pass_count);
    Some(QecSummary {
        rounds_executed: rounds.len(),
        logical_pass_count,
        logical_fail_count,
        logical_pass: logical_fail_count == 0,
    })
}

fn apply_gate_gaussian(
    state: &mut GaussianState,
    gate: &Gate,
    gate_index: usize,
    measurements: &mut Vec<MeasurementRecord>,
    measurement_count: &mut i64,
    rng: &mut SeededRng,
    qec_rounds: &mut Vec<QecRoundRecord>,
) -> Result<(), String> {
    match gate {
        Gate::Phase { theta, mode } => {
            apply_phase_shift_gaussian(state, *theta, *mode)?;
        }
        Gate::Squeeze { r, mode } => {
            apply_squeeze_gaussian(state, *r, *mode)?;
        }
        Gate::BeamSplitter {
            theta,
            mode_a,
            mode_b,
        } => {
            apply_beam_splitter_gaussian(state, *theta, *mode_a, *mode_b)?;
        }
        Gate::Displace { q, p, mode } => {
            apply_displace_gaussian(state, *q, *p, *mode)?;
        }
        Gate::Loss { eta, mode } => {
            *state = gaussian_apply_loss(state, *mode, *eta)?;
        }
        Gate::ThermalLoss { eta, n_th, mode } => {
            *state = gaussian_apply_thermal_loss(state, *mode, *eta, *n_th)?;
        }
        Gate::MeasureHomodyne { mode, theta } => {
            let (sample, post) = gaussian_sample_homodyne(state, *mode, *theta, 0.0, rng)?;
            *state = post;
            measurements.push(MeasurementRecord {
                values: vec![sample],
            });
            *measurement_count = measurements.len() as i64;
        }
        Gate::MeasureHeterodyne { mode } => {
            let (sample, post) = gaussian_sample_heterodyne(state, *mode, rng)?;
            *state = post;
            measurements.push(MeasurementRecord {
                values: vec![sample.0, sample.1],
            });
            *measurement_count = measurements.len() as i64;
        }
        Gate::InjectFock { .. } | Gate::InjectCat { .. } => {
            return Err(format!(
                "Unsupported gate in Gaussian backend: {}",
                gate_type_name(gate)
            ));
        }
        Gate::InjectGkp { delta, mode } => {
            let v = delta * delta;
            *state = gaussian_additive_noise(state, *mode, v, v)?;
        }
        Gate::FeedbackDisplace {
            on,
            source_value_index,
            gain_q,
            gain_p,
            bias_q,
            bias_p,
            mode,
        } => {
            if *on >= measurements.len() {
                return Err(format!(
                    "feedback_displace refers to non-existent measurement {}",
                    on
                ));
            }
            let measurement = &measurements[*on];
            let Some(value) = measurement.values.get(*source_value_index).copied() else {
                return Err(format!(
                    "feedback_displace measurement {} does not have value index {}",
                    on, source_value_index
                ));
            };
            let q = (*gain_q * value) + *bias_q;
            let p = (*gain_p * value) + *bias_p;
            apply_displace_gaussian(state, q, p, *mode)?;
        }
        Gate::GkpDecodeDisplace {
            on,
            source_value_index,
            lattice_spacing,
            target_lattice_index,
            gain_q,
            gain_p,
            bias_q,
            bias_p,
            mode,
        } => {
            if *on >= measurements.len() {
                return Err(format!(
                    "gkp_decode_displace refers to non-existent measurement {}",
                    on
                ));
            }
            let measurement = &measurements[*on];
            let Some(value) = measurement.values.get(*source_value_index).copied() else {
                return Err(format!(
                    "gkp_decode_displace measurement {} does not have value index {}",
                    on, source_value_index
                ));
            };
            let decoded = GkpNearestLatticeDecoder::decode(
                value,
                *lattice_spacing,
                *target_lattice_index,
            );
            let q = (*gain_q * decoded.correction) + *bias_q;
            let p = (*gain_p * decoded.correction) + *bias_p;
            apply_displace_gaussian(state, q, p, *mode)?;

            qec_rounds.push(QecRoundRecord {
                round: qec_rounds.len() + 1,
                gate_index,
                measurement_index: *on,
                source_value_index: *source_value_index,
                mode: *mode,
                syndrome_value: value,
                decoder: "gkp_nearest_lattice_rounding".to_string(),
                lattice_spacing: decoded.lattice_spacing,
                target_lattice_index: decoded.target_lattice_index,
                nearest_lattice_index: decoded.nearest_lattice_index,
                nearest_lattice_value: decoded.nearest_lattice_value,
                residual: decoded.residual,
                correction_value: decoded.correction,
                applied_q: q,
                applied_p: p,
                logical_pass: decoded.logical_pass,
            });
        }
        Gate::ClassicalControl {
            on,
            condition,
            apply,
        } => {
            if *on >= measurements.len() {
                return Err(format!(
                    "Classical control refers to non-existent measurement {}",
                    on
                ));
            }

            if let Some(condition) = condition {
                let measurement = &measurements[*on];
                let Some(value) = measurement.values.get(condition.value_index).copied() else {
                    return Err(format!(
                        "Classical control measurement {} does not have value index {}",
                        on, condition.value_index
                    ));
                };
                if !condition.comparator.eval(value, condition.threshold) {
                    return Ok(());
                }
            }

            apply_classical_gate_gaussian(state, apply)?;
        }
        Gate::NoisePlaceholder { label } => {
            return Err(format!("Unsupported gate: noise_placeholder({})", label));
        }
    }
    Ok(())
}

fn apply_classical_gate_gaussian(state: &mut GaussianState, gate: &Gate) -> Result<(), String> {
    match gate {
        Gate::Phase { theta, mode } => {
            apply_phase_shift_gaussian(state, *theta, *mode)?;
        }
        Gate::Squeeze { r, mode } => {
            apply_squeeze_gaussian(state, *r, *mode)?;
        }
        Gate::BeamSplitter {
            theta,
            mode_a,
            mode_b,
        } => {
            apply_beam_splitter_gaussian(state, *theta, *mode_a, *mode_b)?;
        }
        Gate::Displace { q, p, mode } => {
            apply_displace_gaussian(state, *q, *p, *mode)?;
        }
        Gate::Loss { eta, mode } => {
            *state = gaussian_apply_loss(state, *mode, *eta)?;
        }
        Gate::ThermalLoss { eta, n_th, mode } => {
            *state = gaussian_apply_thermal_loss(state, *mode, *eta, *n_th)?;
        }
        Gate::InjectGkp { delta, mode } => {
            let v = delta * delta;
            *state = gaussian_additive_noise(state, *mode, v, v)?;
        }
        Gate::InjectFock { .. } | Gate::InjectCat { .. } => {
            return Err(format!(
                "Unsupported classical control apply gate for Gaussian backend: {}",
                gate_type_name(gate)
            ));
        }
        Gate::MeasureHomodyne { .. }
        | Gate::MeasureHeterodyne { .. }
        | Gate::FeedbackDisplace { .. }
        | Gate::GkpDecodeDisplace { .. }
        | Gate::ClassicalControl { .. }
        | Gate::NoisePlaceholder { .. } => {
            return Err(format!(
                "Unsupported classical control apply gate: {}",
                gate_type_name(gate)
            ));
        }
    }
    Ok(())
}

fn execute_fock(
    circuit: &ParsedCircuit,
    cutoff: usize,
    include_trace: bool,
    _seed: Option<u64>,
    _trace_role: &str,
    _max_frames: Option<usize>,
    _ring_buffer: Option<usize>,
) -> Result<ExecutionResult, String> {
    assert_fock_compatible(circuit)?;

    let mut state = FockState::vacuum(cutoff);
    let mut frames: Vec<TraceFrame> = Vec::with_capacity(circuit.gates.len() + 1);
    if include_trace {
        frames.push(TraceFrame {
            frame_index: 0,
            gate_index: None,
            gate_type: "initial".to_string(),
            mean_photon_number: 0.0,
            measurement_count: 0,
            frame_latency_ms: 0.0,
        });
    }

    let run_start = Instant::now();
    let mut max_latency_ms = 0.0;

    for (index, gate) in circuit.gates.iter().enumerate() {
        let gate_start = Instant::now();
        match gate {
            Gate::Phase { theta, .. } => {
                fock_apply_phase(&mut state, *theta);
            }
            Gate::Displace { q, p, .. } => {
                let alpha = Complex64 {
                    re: q / 2_f64.sqrt(),
                    im: p / 2_f64.sqrt(),
                };
                let unitary = fock_displacement_operator(alpha, cutoff, FOCK_DISPLACE_TAYLOR_TERMS);
                state = fock_apply_unitary(&unitary, &state);
            }
            Gate::InjectFock { n, mode } => {
                if *mode != 0 {
                    return Err(format!(
                        "Fock injection mode {} is invalid for single-mode Fock backend",
                        mode
                    ));
                }
                state = fock_state_fock(*n, cutoff)?;
            }
            Gate::InjectCat { alpha, mode } => {
                if *mode != 0 {
                    return Err(format!(
                        "Cat injection mode {} is invalid for single-mode Fock backend",
                        mode
                    ));
                }
                state = fock_state_cat(*alpha, cutoff, true);
            }
            _ => {
                return Err(format!(
                    "Unsupported gate in Fock backend: {}",
                    gate_type_name(gate)
                ));
            }
        }

        let latency_ms = gate_start.elapsed().as_secs_f64() * 1000.0;
        if latency_ms > max_latency_ms {
            max_latency_ms = latency_ms;
        }
        if include_trace {
            frames.push(TraceFrame {
                frame_index: index + 1,
                gate_index: Some(index),
                gate_type: gate_type_name(gate),
                mean_photon_number: state.expected_photon_number(),
                measurement_count: 0,
                frame_latency_ms: latency_ms,
            });
        }
    }

    let trace_total_ms = run_start.elapsed().as_secs_f64() * 1000.0;
    Ok(ExecutionResult {
        backend_used: "fock".to_string(),
        mean_photon_number: state.expected_photon_number(),
        measurement_count: 0,
        frames,
        trace_total_ms,
        final_state: fock_state_payload(&state, 12),
        qec_rounds: Vec::new(),
        qec_summary: None,
    })
}

fn gaussian_state_payload(state: &GaussianState) -> Value {
    let mut covariance: Vec<Vec<f64>> = Vec::with_capacity(state.cov.len());
    for row in 0..state.cov.len() {
        covariance.push(state.cov[row].to_vec());
    }

    json!({
        "backend": "gaussian",
        "representation": "gaussian_phase_space",
        "modes": state.modes,
        "mean": state.mean,
        "covariance": covariance
    })
}

fn fock_state_payload(state: &FockState, top_limit: usize) -> Value {
    let probabilities: Vec<f64> = state.psi.iter().map(|value| value.abs2()).collect();
    let mut ranked: Vec<(usize, f64)> = probabilities.iter().copied().enumerate().collect();
    ranked.sort_by(|lhs, rhs| rhs.1.total_cmp(&lhs.1).then_with(|| lhs.0.cmp(&rhs.0)));

    let top_probabilities: Vec<Value> = ranked
        .into_iter()
        .take(top_limit.max(1))
        .map(|(n, probability)| {
            let amplitude = state.psi[n];
            json!({
                "n": n,
                "probability": probability,
                "re": amplitude.re,
                "im": amplitude.im
            })
        })
        .collect();

    json!({
        "backend": "fock",
        "representation": "fock_number_basis",
        "modes": 1,
        "cutoff": state.cutoff,
        "probabilities": probabilities,
        "top_probabilities": top_probabilities
    })
}

fn collect_trace_frames(
    frames: Vec<TraceFrame>,
    max_frames: Option<usize>,
    ring_buffer: Option<usize>,
) -> TraceFrameCollectionResult {
    let original_count = frames.len();
    let mut working = frames;
    let mut dropped_count = 0usize;
    let mut downsampling_applied = false;
    let mut ring_buffer_applied = false;

    if let Some(limit) = max_frames {
        if limit > 0 && working.len() > limit {
            downsampling_applied = true;
            let prev = working.len();
            if limit == 1 {
                working = vec![working[prev - 1].clone()];
            } else {
                let mut sampled = Vec::with_capacity(limit);
                for idx in 0..limit {
                    let source = idx * (prev - 1) / (limit - 1);
                    sampled.push(working[source].clone());
                }
                working = sampled;
            }
            dropped_count += prev.saturating_sub(working.len());
        }
    }

    if let Some(limit) = ring_buffer {
        if limit > 0 && working.len() > limit {
            ring_buffer_applied = true;
            let prev = working.len();
            let start = prev - limit;
            working = working[start..].to_vec();
            dropped_count += prev.saturating_sub(working.len());
        }
    }

    let max_latency = working
        .iter()
        .map(|frame| frame.frame_latency_ms)
        .fold(0.0_f64, f64::max);

    TraceFrameCollectionResult {
        frames: working,
        original_count,
        dropped_count,
        downsampling_applied,
        ring_buffer_applied,
        max_frame_latency_ms: max_latency,
    }
}

fn parse_run_options(arguments: &[String]) -> Result<RunOptions, String> {
    let mut idx = 0usize;
    let mut path: Option<String> = None;
    let mut backend_override: Option<String> = None;
    let mut cutoff_override: Option<usize> = None;
    let mut seed_override: Option<u64> = None;
    let mut prod_mode = false;
    let mut foundry_registry_path: Option<String> = None;
    let mut foundry_key: Option<String> = None;

    while idx < arguments.len() {
        let token = arguments[idx].as_str();
        match token {
            "--backend" => {
                backend_override = Some(read_option_value(arguments, idx, token)?.to_string());
                idx += 2;
            }
            "--cutoff" => {
                let value = read_option_value(arguments, idx, token)?;
                cutoff_override = Some(parse_positive_usize(value, token)?);
                idx += 2;
            }
            "--seed" => {
                let value = read_option_value(arguments, idx, token)?;
                seed_override = Some(parse_u64(value, token)?);
                idx += 2;
            }
            "--prod" => {
                prod_mode = true;
                idx += 1;
            }
            "--foundry-registry" => {
                foundry_registry_path = Some(read_option_value(arguments, idx, token)?.to_string());
                idx += 2;
            }
            "--foundry-key" => {
                foundry_key = Some(read_option_value(arguments, idx, token)?.to_string());
                idx += 2;
            }
            "--compute-backend" => {
                let _ = read_option_value(arguments, idx, token)?;
                idx += 2;
            }
            _ => {
                if token.starts_with("--") {
                    return Err(format!("Unknown option '{}'", token));
                }
                if path.is_some() {
                    return Err("Only one input file is allowed".to_string());
                }
                path = Some(arguments[idx].clone());
                idx += 1;
            }
        }
    }

    let path = path.ok_or_else(|| "Missing input file".to_string())?;
    Ok(RunOptions {
        path,
        backend_override,
        cutoff_override,
        seed_override,
        prod_mode,
        foundry_registry_path,
        foundry_key,
    })
}

fn parse_trace_options(arguments: &[String]) -> Result<TraceOptions, String> {
    let mut idx = 0usize;
    let mut run_args: Vec<String> = Vec::new();
    let mut role = "viewer".to_string();
    let mut max_frames: Option<usize> = None;
    let mut ring_buffer: Option<usize> = None;

    while idx < arguments.len() {
        let token = arguments[idx].as_str();
        match token {
            "--trace-role" => {
                role = read_option_value(arguments, idx, token)?.to_string();
                idx += 2;
            }
            "--max-frames" => {
                max_frames = Some(parse_positive_usize(
                    read_option_value(arguments, idx, token)?,
                    token,
                )?);
                idx += 2;
            }
            "--ring-buffer" => {
                ring_buffer = Some(parse_positive_usize(
                    read_option_value(arguments, idx, token)?,
                    token,
                )?);
                idx += 2;
            }
            "--trace-rbac" | "--trace-artifact" | "--trace-key" => {
                let _ = read_option_value(arguments, idx, token)?;
                idx += 2;
            }
            _ => {
                run_args.push(arguments[idx].clone());
                idx += 1;
            }
        }
    }

    let run = parse_run_options(&run_args)?;
    Ok(TraceOptions {
        run,
        role,
        max_frames,
        ring_buffer,
    })
}

fn parse_bench_options(arguments: &[String]) -> Result<BenchOptions, String> {
    let mut idx = 0usize;
    let mut suite = BenchSuite::Core;
    let mut iterations = 7usize;
    let mut warmup = 2usize;
    let mut max_regression_pct = 10.0_f64;
    let mut baseline_path: Option<String> = None;
    let mut write_baseline_path: Option<String> = None;

    while idx < arguments.len() {
        let token = arguments[idx].as_str();
        match token {
            "--suite" => {
                suite = parse_bench_suite(read_option_value(arguments, idx, token)?)?;
                idx += 2;
            }
            "--iterations" => {
                let value = read_option_value(arguments, idx, token)?;
                iterations = parse_positive_usize(value, token)?;
                idx += 2;
            }
            "--warmup" => {
                let value = read_option_value(arguments, idx, token)?;
                warmup = parse_non_negative_usize(value, token)?;
                idx += 2;
            }
            "--max-regression-pct" => {
                let value = read_option_value(arguments, idx, token)?;
                max_regression_pct = parse_non_negative_f64(value, token)?;
                idx += 2;
            }
            "--baseline" => {
                baseline_path = Some(read_option_value(arguments, idx, token)?.to_string());
                idx += 2;
            }
            "--write-baseline" => {
                write_baseline_path = Some(read_option_value(arguments, idx, token)?.to_string());
                idx += 2;
            }
            _ => {
                if token.starts_with("--") {
                    return Err(format!("Unknown option '{}'", token));
                }
                return Err(format!(
                    "Unexpected positional argument '{}'; bench takes only options",
                    token
                ));
            }
        }
    }

    Ok(BenchOptions {
        suite,
        iterations,
        warmup,
        max_regression_pct,
        baseline_path,
        write_baseline_path,
    })
}

fn parse_bench_suite(raw: &str) -> Result<BenchSuite, String> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "core" => Ok(BenchSuite::Core),
        "scaling" => Ok(BenchSuite::Scaling),
        "all" => Ok(BenchSuite::All),
        _ => Err(format!(
            "Invalid --suite '{}'. Expected one of: core, scaling, all",
            raw
        )),
    }
}

#[cfg(debug_assertions)]
fn parse_parity_options(arguments: &[String]) -> Result<ParityOptions, String> {
    let mut idx = 0usize;
    let mut run_args: Vec<String> = Vec::new();
    let mut role = "viewer".to_string();
    let mut swift_exec = "swift".to_string();

    while idx < arguments.len() {
        let token = arguments[idx].as_str();
        match token {
            "--trace-role" => {
                role = read_option_value(arguments, idx, token)?.to_string();
                idx += 2;
            }
            "--swift-exec" => {
                swift_exec = read_option_value(arguments, idx, token)?.to_string();
                idx += 2;
            }
            _ => {
                run_args.push(arguments[idx].clone());
                idx += 1;
            }
        }
    }

    let run = parse_run_options(&run_args)?;
    Ok(ParityOptions {
        run,
        role,
        swift_exec,
    })
}

fn read_option_value<'a>(
    arguments: &'a [String],
    idx: usize,
    option: &str,
) -> Result<&'a str, String> {
    let next = idx + 1;
    if next >= arguments.len() {
        return Err(format!("Missing value for {}", option));
    }
    Ok(arguments[next].as_str())
}

fn parse_positive_usize(value: &str, option: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("{} must be a positive integer", option))?;
    if parsed == 0 {
        return Err(format!("{} must be a positive integer", option));
    }
    Ok(parsed)
}

fn parse_non_negative_usize(value: &str, option: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|_| format!("{} must be a non-negative integer", option))
}

fn parse_u64(value: &str, option: &str) -> Result<u64, String> {
    value
        .parse::<u64>()
        .map_err(|_| format!("{} must be an unsigned 64-bit integer", option))
}

fn parse_non_negative_f64(value: &str, option: &str) -> Result<f64, String> {
    let parsed = value
        .parse::<f64>()
        .map_err(|_| format!("{} must be a non-negative number", option))?;
    if !parsed.is_finite() || parsed < 0.0 {
        return Err(format!("{} must be a non-negative number", option));
    }
    Ok(parsed)
}

fn require_f64(value: Option<f64>, gate: &str, field: &str) -> Result<f64, String> {
    value.ok_or_else(|| format!("Gate '{}' is missing required field '{}'", gate, field))
}

fn require_i64(value: Option<i64>, gate: &str, field: &str) -> Result<i64, String> {
    value.ok_or_else(|| format!("Gate '{}' is missing required field '{}'", gate, field))
}

fn require_mode(
    value: Option<i64>,
    modes: usize,
    gate: &str,
    field: &str,
) -> Result<usize, String> {
    let mode = require_i64(value, gate, field)?;
    if mode < 0 {
        return Err(format!("Gate '{}' field '{}' must be >= 0", gate, field));
    }
    let mode = mode as usize;
    if mode >= modes {
        return Err(format!(
            "Gate '{}' field '{}' is out of bounds: {} not in 0..{}",
            gate, field, mode, modes
        ));
    }
    Ok(mode)
}

fn validate_eta(eta: f64) -> Result<(), String> {
    if (0.0..=1.0).contains(&eta) {
        Ok(())
    } else {
        Err(format!("Loss eta must be in [0,1], got {}", eta))
    }
}

fn load_input(path: &str) -> Result<CircuitInput, String> {
    let data = fs::read_to_string(path)
        .map_err(|error| format!("Failed to read input file: {}", error))?;
    serde_json::from_str::<CircuitInput>(&data)
        .map_err(|error| format!("Invalid JSON input: {}", error))
}

fn resolve_foundry_spec(
    input: &CircuitInput,
    options: &RunOptions,
    _modes: usize,
) -> Result<ResolvedFoundryRuntime, String> {
    if input.foundry.is_some() && input.foundry_profile.is_some() {
        return Err("Only one of 'foundry' or 'foundry_profile' may be provided".to_string());
    }

    if options.prod_mode && input.foundry.is_some() {
        return Err(
            "Inline 'foundry' block is not allowed in --prod mode; use 'foundry_profile'"
                .to_string(),
        );
    }

    if let Some(foundry) = &input.foundry {
        return Ok(ResolvedFoundryRuntime {
            spec: foundry_spec_from_input(foundry)?,
            source: "input",
        });
    }

    if let Some(profile) = &input.foundry_profile {
        let profile_id = profile.profile_id.trim();
        if profile_id.is_empty() {
            return Err("'foundry_profile.profile_id' must not be empty".to_string());
        }
        if profile.version <= 0 {
            return Err("'foundry_profile.version' must be a positive integer".to_string());
        }

        let registry_path = options
            .foundry_registry_path
            .as_deref()
            .unwrap_or("config/foundry_registry.json");
        let signing_key = resolve_foundry_signing_key(options).ok_or_else(|| {
            "Missing foundry signing key. Provide --foundry-key or SCHROSIM_FOUNDRY_HMAC_KEY"
                .to_string()
        })?;
        let spec = resolve_foundry_spec_from_registry(
            registry_path,
            profile_id,
            profile.version,
            &signing_key,
            Utc::now(),
        )?;
        return Ok(ResolvedFoundryRuntime {
            spec,
            source: "registry",
        });
    }

    Err("Missing required top-level field 'foundry' or 'foundry_profile'".to_string())
}

fn foundry_spec_from_input(foundry: &FoundryInput) -> Result<FoundrySpec, String> {
    let name = foundry
        .name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("runtime-input")
        .to_string();

    let max_modes = match foundry.max_modes {
        Some(value) => {
            if value <= 0 {
                return Err(format!("Foundry maxModes must be > 0, got {}", value));
            }
            Some(value as usize)
        }
        None => None,
    };

    let max_squeezing_r = match foundry.max_squeezing_r {
        Some(value) => {
            if !value.is_finite() || value < 0.0 {
                return Err(format!(
                    "Foundry maxSqueezingR must be finite and >= 0, got {}",
                    value
                ));
            }
            Some(value)
        }
        None => None,
    };

    let mode_loss_eta = foundry.mode_loss_eta.clone().unwrap_or_default();

    Ok(FoundrySpec {
        name,
        max_modes,
        max_squeezing_r,
        allow_non_gaussian: foundry.allow_non_gaussian.unwrap_or(true),
        allow_measurements: foundry.allow_measurements.unwrap_or(true),
        mode_loss_eta,
        inject_mode_loss: foundry.inject_mode_loss.unwrap_or(true),
    })
}

fn resolve_foundry_signing_key(options: &RunOptions) -> Option<String> {
    if let Some(key) = &options.foundry_key {
        if key.is_empty() {
            return None;
        }
        return Some(key.clone());
    }

    match env::var("SCHROSIM_FOUNDRY_HMAC_KEY") {
        Ok(key) if !key.is_empty() => Some(key),
        _ => None,
    }
}

fn parse_iso8601_timestamp(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|parsed| parsed.with_timezone(&Utc))
}

fn current_iso8601_timestamp(now: DateTime<Utc>) -> String {
    now.to_rfc3339_opts(SecondsFormat::Millis, true)
}

fn foundry_spec_signing_json(spec: &FoundryRegistrySpec) -> Value {
    let mode_loss_eta: &[f64] = spec.mode_loss_eta.as_deref().unwrap_or(&[]);
    json!({
        "name": spec.name.as_deref(),
        "max_modes": spec.max_modes,
        "max_squeezing_r": spec.max_squeezing_r,
        "allow_non_gaussian": spec.allow_non_gaussian.unwrap_or(true),
        "allow_measurements": spec.allow_measurements.unwrap_or(true),
        "mode_loss_eta": mode_loss_eta,
        "inject_mode_loss": spec.inject_mode_loss.unwrap_or(true)
    })
}

fn foundry_profile_signing_data(profile: &FoundryRegistryProfile) -> Result<Vec<u8>, String> {
    let payload = json!({
        "profile_id": profile.profile_id.as_str(),
        "version": profile.version,
        "status": profile.status.as_str(),
        "valid_from": profile.valid_from.as_str(),
        "valid_to": profile.valid_to.as_deref(),
        "approvers": &profile.approvers,
        "change_ticket": profile.change_ticket.as_deref(),
        "spec": foundry_spec_signing_json(&profile.spec)
    });

    serde_json::to_vec(&payload).map_err(|error| format!("Malformed foundry registry: {}", error))
}

fn hex_encode_lower(bytes: &[u8]) -> String {
    let mut result = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        result.push_str(&format!("{:02x}", byte));
    }
    result
}

fn sign_foundry_profile(
    profile: &FoundryRegistryProfile,
    signing_key: &str,
) -> Result<String, String> {
    let payload = foundry_profile_signing_data(profile)?;
    let key = hmac::Key::new(hmac::HMAC_SHA256, signing_key.as_bytes());
    let signature = hmac::sign(&key, &payload);
    Ok(hex_encode_lower(signature.as_ref()))
}

fn verify_foundry_profile_signature(
    profile: &FoundryRegistryProfile,
    signing_key: &str,
) -> Result<bool, String> {
    let Some(signature) = profile.signature.as_deref() else {
        return Ok(false);
    };
    if signature.is_empty() {
        return Ok(false);
    }

    let expected = sign_foundry_profile(profile, signing_key)?;
    Ok(expected == signature.to_ascii_lowercase())
}

fn resolve_foundry_spec_from_registry(
    registry_path: &str,
    profile_id: &str,
    version: i64,
    signing_key: &str,
    now: DateTime<Utc>,
) -> Result<FoundrySpec, String> {
    let data = fs::read_to_string(registry_path).map_err(|error| {
        format!(
            "Failed to read foundry registry '{}': {}",
            registry_path, error
        )
    })?;
    let registry: FoundryRegistry = serde_json::from_str(&data).map_err(|error| {
        format!(
            "Invalid foundry registry JSON '{}': {}",
            registry_path, error
        )
    })?;

    if registry.schema_version != FOUNDRY_REGISTRY_CURRENT_SCHEMA_VERSION {
        return Err(format!(
            "Unsupported foundry registry schema_version '{}'; expected {}",
            registry.schema_version, FOUNDRY_REGISTRY_CURRENT_SCHEMA_VERSION
        ));
    }

    let mut seen: BTreeSet<(String, i64)> = BTreeSet::new();
    for entry in &registry.profiles {
        let key = (entry.profile_id.clone(), entry.version);
        if !seen.insert(key) {
            return Err(format!(
                "Duplicate foundry profile entry: profile_id='{}', version={}",
                entry.profile_id, entry.version
            ));
        }
    }

    let profile = registry
        .profiles
        .iter()
        .find(|entry| entry.profile_id == profile_id && entry.version == version)
        .ok_or_else(|| {
            format!(
                "Foundry profile not found: profile_id='{}', version={}",
                profile_id, version
            )
        })?;

    if profile.status != FoundryRegistryStatus::Approved {
        return Err(format!(
            "Foundry profile '{}' version {} is not approved (status={})",
            profile.profile_id,
            profile.version,
            profile.status.as_str()
        ));
    }

    let from_date = parse_iso8601_timestamp(&profile.valid_from).ok_or_else(|| {
        format!(
            "Foundry profile '{}' version {} has invalid validity window: valid_from must be ISO-8601",
            profile.profile_id, profile.version
        )
    })?;
    if now < from_date {
        return Err(format!(
            "Foundry profile '{}' version {} is expired/not-yet-valid at {}",
            profile.profile_id,
            profile.version,
            current_iso8601_timestamp(now)
        ));
    }

    if let Some(valid_to) = profile.valid_to.as_deref() {
        let to_date = parse_iso8601_timestamp(valid_to).ok_or_else(|| {
            format!(
                "Foundry profile '{}' version {} has invalid validity window: valid_to must be ISO-8601",
                profile.profile_id, profile.version
            )
        })?;
        if now > to_date {
            return Err(format!(
                "Foundry profile '{}' version {} is expired/not-yet-valid at {}",
                profile.profile_id,
                profile.version,
                current_iso8601_timestamp(now)
            ));
        }
    }

    if profile.signature.is_none() {
        return Err(format!(
            "Foundry profile '{}' version {} is missing a signature",
            profile.profile_id, profile.version
        ));
    }
    if !verify_foundry_profile_signature(profile, signing_key)? {
        return Err(format!(
            "Foundry signature verification failed for '{}' version {}",
            profile.profile_id, profile.version
        ));
    }

    foundry_spec_from_registry_profile(profile)
}

fn foundry_spec_from_registry_profile(
    profile: &FoundryRegistryProfile,
) -> Result<FoundrySpec, String> {
    let name = profile
        .spec
        .name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(profile.profile_id.as_str())
        .to_string();

    let max_modes = match profile.spec.max_modes {
        Some(value) => {
            if value <= 0 {
                return Err(format!("Foundry maxModes must be > 0, got {}", value));
            }
            Some(value as usize)
        }
        None => None,
    };
    let max_squeezing_r = match profile.spec.max_squeezing_r {
        Some(value) => {
            if !value.is_finite() || value < 0.0 {
                return Err(format!(
                    "Foundry maxSqueezingR must be finite and >= 0, got {}",
                    value
                ));
            }
            Some(value)
        }
        None => None,
    };

    let mode_loss_eta = profile.spec.mode_loss_eta.clone().unwrap_or_default();

    Ok(FoundrySpec {
        name,
        max_modes,
        max_squeezing_r,
        allow_non_gaussian: profile.spec.allow_non_gaussian.unwrap_or(true),
        allow_measurements: profile.spec.allow_measurements.unwrap_or(true),
        mode_loss_eta,
        inject_mode_loss: profile.spec.inject_mode_loss.unwrap_or(true),
    })
}

fn compile_with_foundry(
    circuit: &ParsedCircuit,
    spec: &FoundrySpec,
) -> Result<ParsedCircuit, String> {
    validate_foundry(circuit, spec)?;
    let mut gates = circuit.gates.clone();
    if spec.inject_mode_loss {
        for (mode, eta) in spec.mode_loss_eta.iter().enumerate() {
            if *eta < 1.0 {
                gates.push(Gate::Loss { eta: *eta, mode });
            }
        }
    }
    Ok(ParsedCircuit {
        modes: circuit.modes,
        gates,
    })
}

fn validate_foundry(circuit: &ParsedCircuit, spec: &FoundrySpec) -> Result<(), String> {
    if let Some(max_modes) = spec.max_modes {
        if circuit.modes > max_modes {
            return Err(format!(
                "Circuit modes {} exceed foundry limit {}",
                circuit.modes, max_modes
            ));
        }
    }

    if !spec.mode_loss_eta.is_empty() && spec.mode_loss_eta.len() != circuit.modes {
        return Err(format!(
            "Foundry modeLossEta must have {} values, got {}",
            circuit.modes,
            spec.mode_loss_eta.len()
        ));
    }

    for (mode, eta) in spec.mode_loss_eta.iter().enumerate() {
        if !eta.is_finite() || *eta < 0.0 || *eta > 1.0 {
            return Err(format!(
                "Foundry modeLossEta[{}] must be finite in [0,1], got {}",
                mode, eta
            ));
        }
    }

    for gate in &circuit.gates {
        match gate {
            Gate::Squeeze { r, mode } => {
                if let Some(max_r) = spec.max_squeezing_r {
                    if r.abs() > max_r {
                        return Err(format!(
                            "Squeezing on mode {} exceeds foundry maxSqueezingR {}: got {}",
                            mode, max_r, r
                        ));
                    }
                }
            }
            Gate::InjectFock { .. } | Gate::InjectCat { .. } | Gate::InjectGkp { .. } => {
                if !spec.allow_non_gaussian {
                    return Err(format!(
                        "Foundry disallows non-Gaussian injection: {}",
                        gate_type_name(gate)
                    ));
                }
            }
            Gate::MeasureHomodyne { .. }
            | Gate::MeasureHeterodyne { .. }
            | Gate::FeedbackDisplace { .. } => {
                if !spec.allow_measurements {
                    return Err("Foundry disallows measurement gates".to_string());
                }
            }
            Gate::GkpDecodeDisplace { .. } => {
                if !spec.allow_measurements {
                    return Err("Foundry disallows measurement gates".to_string());
                }
            }
            Gate::NoisePlaceholder { label } => {
                return Err(format!("Foundry rejects placeholder gate '{}'", label));
            }
            _ => {}
        }
    }

    Ok(())
}

#[cfg(debug_assertions)]
fn invoke_swift_cli_json(swift_exec: &str, args: &[String]) -> Result<Value, String> {
    let output = Command::new(swift_exec)
        .args(args)
        .output()
        .map_err(|error| format!("Failed to launch '{}': {}", swift_exec, error))?;

    let stdout = String::from_utf8(output.stdout)
        .map_err(|error| format!("Invalid UTF-8 stdout: {}", error))?;
    let stderr = String::from_utf8(output.stderr)
        .map_err(|error| format!("Invalid UTF-8 stderr: {}", error))?;

    let decoded = decode_json_from_mixed_output(&stdout)
        .or_else(|_| decode_json_from_mixed_output(&stderr))
        .map_err(|error| {
            format!(
                "Could not decode JSON from Swift CLI output (status: {}). {}",
                output.status.code().unwrap_or(-1),
                error
            )
        })?;

    Ok(decoded)
}

#[cfg(debug_assertions)]
fn decode_json_from_mixed_output(output: &str) -> Result<Value, String> {
    let start = output
        .find('{')
        .ok_or_else(|| "missing '{' in output".to_string())?;
    let end = output
        .rfind('}')
        .ok_or_else(|| "missing '}' in output".to_string())?;
    if end < start {
        return Err("malformed JSON boundaries".to_string());
    }
    let candidate = &output[start..=end];
    serde_json::from_str::<Value>(candidate).map_err(|error| format!("JSON parse error: {}", error))
}

fn round4(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
}

fn qec_payload(execution: &ExecutionResult) -> Value {
    let Some(summary) = execution.qec_summary.as_ref() else {
        return Value::Null;
    };
    let metrics = derive_qec_quality_metrics(&execution.qec_rounds, summary);
    let rounds: Vec<Value> = execution
        .qec_rounds
        .iter()
        .map(|record| {
            json!({
                "round": record.round,
                "gate_index": record.gate_index,
                "measurement_index": record.measurement_index,
                "source_value_index": record.source_value_index,
                "mode": record.mode,
                "syndrome_value": record.syndrome_value,
                "decoder": record.decoder,
                "lattice_spacing": record.lattice_spacing,
                "target_lattice_index": record.target_lattice_index,
                "nearest_lattice_index": record.nearest_lattice_index,
                "nearest_lattice_value": record.nearest_lattice_value,
                "residual": record.residual,
                "correction_value": record.correction_value,
                "applied_q": record.applied_q,
                "applied_p": record.applied_p,
                "logical_pass": record.logical_pass
            })
        })
        .collect();

    json!({
        "decoder": "gkp_nearest_lattice_rounding",
        "rounds_executed": summary.rounds_executed,
        "logical_pass_count": summary.logical_pass_count,
        "logical_fail_count": summary.logical_fail_count,
        "logical_pass": summary.logical_pass,
        "logical_error_rate": metrics.logical_error_rate,
        "physical_error_rate_proxy": metrics.physical_error_rate_proxy,
        "suppression_factor": metrics.suppression_factor,
        "break_even_gain": metrics.break_even_gain,
        "break_even_pass": metrics.break_even_pass,
        "rounds": rounds
    })
}

#[derive(Debug, Clone, Copy)]
struct QecQualityMetrics {
    logical_error_rate: f64,
    physical_error_rate_proxy: Option<f64>,
    suppression_factor: Option<f64>,
    break_even_gain: Option<f64>,
    break_even_pass: bool,
}

fn derive_qec_quality_metrics(rounds: &[QecRoundRecord], summary: &QecSummary) -> QecQualityMetrics {
    let logical_error_rate = if summary.rounds_executed == 0 {
        0.0
    } else {
        summary.logical_fail_count as f64 / summary.rounds_executed as f64
    };
    let physical_error_rate_proxy = qec_physical_error_rate_proxy(rounds);
    let suppression_factor = qec_suppression_factor(physical_error_rate_proxy, logical_error_rate);
    let break_even_gain = qec_break_even_gain(physical_error_rate_proxy, logical_error_rate);

    QecQualityMetrics {
        logical_error_rate,
        physical_error_rate_proxy,
        suppression_factor,
        break_even_gain,
        break_even_pass: break_even_gain.map(|value| value >= 0.0).unwrap_or(false),
    }
}

fn qec_physical_error_rate_proxy(rounds: &[QecRoundRecord]) -> Option<f64> {
    let mut valid_count: usize = 0;
    let mut flagged_count: usize = 0;

    for round in rounds {
        if !round.lattice_spacing.is_finite() || round.lattice_spacing <= 0.0 {
            continue;
        }
        if !round.syndrome_value.is_finite() {
            continue;
        }

        valid_count += 1;
        let target_center = round.target_lattice_index as f64 * round.lattice_spacing;
        let threshold = 0.25 * round.lattice_spacing;
        if (round.syndrome_value - target_center).abs() >= threshold {
            flagged_count += 1;
        }
    }

    if valid_count == 0 {
        None
    } else {
        Some(flagged_count as f64 / valid_count as f64)
    }
}

fn qec_suppression_factor(
    physical_error_rate_proxy: Option<f64>,
    logical_error_rate: f64,
) -> Option<f64> {
    let physical = physical_error_rate_proxy?;
    if !physical.is_finite() || physical < 0.0 {
        return None;
    }
    if !logical_error_rate.is_finite() || logical_error_rate < 0.0 {
        return None;
    }
    if logical_error_rate == 0.0 {
        return if physical > 0.0 { Some(1_000_000.0) } else { None };
    }
    Some(physical / logical_error_rate)
}

fn qec_break_even_gain(
    physical_error_rate_proxy: Option<f64>,
    logical_error_rate: f64,
) -> Option<f64> {
    let physical = physical_error_rate_proxy?;
    if !physical.is_finite() || !logical_error_rate.is_finite() {
        return None;
    }
    Some(physical - logical_error_rate)
}

#[cfg(debug_assertions)]
fn round6(value: f64) -> f64 {
    (value * 1_000_000.0).round() / 1_000_000.0
}

fn normalize_gate_type(raw: &str) -> String {
    raw.trim().to_ascii_lowercase()
}

fn gate_type_name(gate: &Gate) -> String {
    match gate {
        Gate::Phase { .. } => "phase".to_string(),
        Gate::Squeeze { .. } => "squeeze".to_string(),
        Gate::BeamSplitter { .. } => "beam_splitter".to_string(),
        Gate::Displace { .. } => "displace".to_string(),
        Gate::Loss { .. } => "loss".to_string(),
        Gate::ThermalLoss { .. } => "thermal_loss".to_string(),
        Gate::MeasureHomodyne { .. } => "measure_homodyne".to_string(),
        Gate::MeasureHeterodyne { .. } => "measure_heterodyne".to_string(),
        Gate::InjectFock { .. } => "inject_fock".to_string(),
        Gate::InjectCat { .. } => "inject_cat".to_string(),
        Gate::InjectGkp { .. } => "inject_gkp".to_string(),
        Gate::FeedbackDisplace { .. } => "feedback_displace".to_string(),
        Gate::GkpDecodeDisplace { .. } => "gkp_decode_displace".to_string(),
        Gate::ClassicalControl { .. } => "classical_control".to_string(),
        Gate::NoisePlaceholder { .. } => "noise_placeholder".to_string(),
    }
}

fn contraction_type(backend: &str) -> &'static str {
    match backend {
        "gaussian" => "symplectic_covariance",
        "fock" => "state_vector_left_to_right",
        _ => CONTRACTION_POLICY,
    }
}

fn fallback_seed() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_nanos() as u64)
        .unwrap_or(0xC0FFEE_u64)
}

fn usage_payload() -> Value {
    let mut usage = vec![
        "schrosim-core version",
        "schrosim-core info",
        "schrosim-core run <file> [--backend <auto|gaussian|fock|hybrid>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>]",
        "schrosim-core trace <file> [--backend <auto|gaussian|fock|hybrid>] [--cutoff <n>] [--seed <uint64>] [--trace-role <role>] [--max-frames <n>] [--ring-buffer <n>]",
        "schrosim-core bench [--suite <core|scaling|all>] [--iterations <n>] [--warmup <n>] [--max-regression-pct <f64>] [--baseline <file>] [--write-baseline <file>]",
    ];
    if PARITY_ENABLED {
        usage.push(
            "schrosim-core parity <file> [--backend <auto|gaussian|fock|hybrid>] [--cutoff <n>] [--seed <uint64>] [--trace-role <role>] [--swift-exec <swift_bin>]",
        );
    }

    json!({
        "status": "error",
        "error": "Missing or invalid command",
        "usage": usage
    })
}

fn emit_json(payload: &Value) {
    match serde_json::to_string_pretty(payload) {
        Ok(encoded) => println!("{encoded}"),
        Err(_) => println!("{{\"status\":\"error\",\"error\":\"Failed to encode JSON output\"}}"),
    }
}

impl GaussianState {
    fn vacuum(modes: usize) -> Self {
        let dim = 2 * modes;
        let mut cov = la_eye(dim);
        for i in 0..dim {
            cov[i][i] *= 0.5;
        }
        Self {
            modes,
            mean: vec![0.0; dim],
            cov,
        }
    }
}

fn mean_photon_number(state: &GaussianState) -> f64 {
    let mut total = 0.0;
    for mode in 0..state.modes {
        let iq = 2 * mode;
        let ip = iq + 1;
        let q = state.mean[iq];
        let p = state.mean[ip];
        let vq = state.cov[iq][iq];
        let vp = state.cov[ip][ip];
        total += 0.5 * (q * q + p * p + vq + vp - 1.0);
    }
    total.max(0.0)
}

fn rotate_mean_pair(mean: &mut VecF, i: usize, j: usize, c: f64, s: f64) {
    let vi = mean[i];
    let vj = mean[j];
    mean[i] = c * vi - s * vj;
    mean[j] = s * vi + c * vj;
}

fn rotate_cov_pair(cov: &mut MatF, i: usize, j: usize, c: f64, s: f64) {
    let dim = cov.len();

    for col in 0..dim {
        let vi = cov[i][col];
        let vj = cov[j][col];
        cov[i][col] = c * vi - s * vj;
        cov[j][col] = s * vi + c * vj;
    }

    for row in 0..dim {
        let vi = cov[row][i];
        let vj = cov[row][j];
        cov[row][i] = c * vi - s * vj;
        cov[row][j] = s * vi + c * vj;
    }
}

fn scale_mean_index(mean: &mut VecF, idx: usize, scale: f64) {
    mean[idx] *= scale;
}

fn scale_cov_index(cov: &mut MatF, idx: usize, scale: f64) {
    let dim = cov.len();
    for col in 0..dim {
        cov[idx][col] *= scale;
    }
    for row in 0..dim {
        cov[row][idx] *= scale;
    }
}

fn apply_phase_shift_gaussian(
    state: &mut GaussianState,
    theta: f64,
    mode: usize,
) -> Result<(), String> {
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let c = theta.cos();
    let s = theta.sin();
    let iq = 2 * mode;
    let ip = iq + 1;
    rotate_mean_pair(&mut state.mean, iq, ip, c, s);
    rotate_cov_pair(&mut state.cov, iq, ip, c, s);
    Ok(())
}

fn apply_squeeze_gaussian(state: &mut GaussianState, r: f64, mode: usize) -> Result<(), String> {
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let sq = (-r).exp();
    let sp = r.exp();
    let iq = 2 * mode;
    let ip = iq + 1;

    scale_mean_index(&mut state.mean, iq, sq);
    scale_mean_index(&mut state.mean, ip, sp);
    scale_cov_index(&mut state.cov, iq, sq);
    scale_cov_index(&mut state.cov, ip, sp);
    Ok(())
}

fn apply_beam_splitter_gaussian(
    state: &mut GaussianState,
    theta: f64,
    mode_a: usize,
    mode_b: usize,
) -> Result<(), String> {
    if mode_a >= state.modes || mode_b >= state.modes || mode_a == mode_b {
        return Err("invalid beam splitter mode pair".to_string());
    }
    let c = theta.cos();
    let s = theta.sin();

    let qa = 2 * mode_a;
    let pa = qa + 1;
    let qb = 2 * mode_b;
    let pb = qb + 1;

    rotate_mean_pair(&mut state.mean, qa, qb, c, s);
    rotate_mean_pair(&mut state.mean, pa, pb, c, s);
    rotate_cov_pair(&mut state.cov, qa, qb, c, s);
    rotate_cov_pair(&mut state.cov, pa, pb, c, s);
    Ok(())
}

fn apply_displace_gaussian(
    state: &mut GaussianState,
    q: f64,
    p: f64,
    mode: usize,
) -> Result<(), String> {
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let iq = 2 * mode;
    state.mean[iq] += q;
    state.mean[iq + 1] += p;
    Ok(())
}

fn gaussian_apply_loss(
    state: &GaussianState,
    mode: usize,
    eta: f64,
) -> Result<GaussianState, String> {
    validate_eta(eta)?;
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let i = 2 * mode;
    let s = eta.sqrt();
    let mut mean = state.mean.clone();
    let mut cov = state.cov.clone();

    scale_mean_index(&mut mean, i, s);
    scale_mean_index(&mut mean, i + 1, s);
    scale_cov_index(&mut cov, i, s);
    scale_cov_index(&mut cov, i + 1, s);

    let noise = (1.0 - eta) * 0.5;
    cov[i][i] += noise;
    cov[i + 1][i + 1] += noise;

    Ok(GaussianState {
        modes: state.modes,
        mean,
        cov,
    })
}

fn gaussian_apply_thermal_loss(
    state: &GaussianState,
    mode: usize,
    eta: f64,
    n_th: f64,
) -> Result<GaussianState, String> {
    validate_eta(eta)?;
    if n_th < 0.0 {
        return Err("n_th must be >= 0".to_string());
    }
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let i = 2 * mode;
    let s = eta.sqrt();
    let mut mean = state.mean.clone();
    let mut cov = state.cov.clone();

    scale_mean_index(&mut mean, i, s);
    scale_mean_index(&mut mean, i + 1, s);
    scale_cov_index(&mut cov, i, s);
    scale_cov_index(&mut cov, i + 1, s);

    let noise = (1.0 - eta) * (2.0 * n_th + 1.0) * 0.5;
    cov[i][i] += noise;
    cov[i + 1][i + 1] += noise;

    Ok(GaussianState {
        modes: state.modes,
        mean,
        cov,
    })
}

fn gaussian_additive_noise(
    state: &GaussianState,
    mode: usize,
    vq: f64,
    vp: f64,
) -> Result<GaussianState, String> {
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let mut cov = state.cov.clone();
    let iq = 2 * mode;
    let ip = iq + 1;
    cov[iq][iq] += vq;
    cov[ip][ip] += vp;
    Ok(GaussianState {
        modes: state.modes,
        mean: state.mean.clone(),
        cov,
    })
}

fn gaussian_sample_homodyne(
    state: &GaussianState,
    mode: usize,
    theta: f64,
    v_meas: f64,
    rng: &mut SeededRng,
) -> Result<(f64, GaussianState), String> {
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let dim = 2 * state.modes;
    let mut h = vec![0.0; dim];
    let i = 2 * mode;
    h[i] = theta.cos();
    h[i + 1] = theta.sin();

    let mu = la_dot(&h, &state.mean);
    let vh = la_matvec(&state.cov, &h);
    let s2 = la_dot(&h, &vh) + v_meas;
    if s2 <= 0.0 {
        return Err(format!(
            "Measurement failed: non-positive homodyne variance {}",
            s2
        ));
    }

    let y = mu + s2.sqrt() * rng.standard_normal();
    let gain = (y - mu) / s2;
    let mut new_mean = state.mean.clone();
    for k in 0..dim {
        new_mean[k] += vh[k] * gain;
    }

    let inv_s2 = 1.0 / s2;
    let mut new_cov = state.cov.clone();
    for row in 0..dim {
        let vr = vh[row];
        for col in 0..dim {
            new_cov[row][col] -= vr * vh[col] * inv_s2;
        }
    }

    Ok((
        y,
        GaussianState {
            modes: state.modes,
            mean: new_mean,
            cov: new_cov,
        },
    ))
}

fn gaussian_sample_heterodyne(
    state: &GaussianState,
    mode: usize,
    rng: &mut SeededRng,
) -> Result<((f64, f64), GaussianState), String> {
    if mode >= state.modes {
        return Err(format!("invalid mode {}", mode));
    }
    let dim = 2 * state.modes;
    let i = 2 * mode;
    let mu0 = state.mean[i];
    let mu1 = state.mean[i + 1];

    let s00 = state.cov[i][i] + 0.5;
    let s01 = state.cov[i][i + 1];
    let s10 = state.cov[i + 1][i];
    let s11 = state.cov[i + 1][i + 1] + 0.5;

    let det = s00 * s11 - s01 * s10;
    if det.abs() < 1e-14 {
        return Err("Could not invert heterodyne innovation matrix".to_string());
    }
    let inv_det = 1.0 / det;
    let inv00 = s11 * inv_det;
    let inv01 = -s01 * inv_det;
    let inv10 = -s10 * inv_det;
    let inv11 = s00 * inv_det;

    let b = 0.5 * (s01 + s10);
    if s00 <= 1e-14 {
        return Err("Heterodyne sampling failed: innovation covariance is not SPD".to_string());
    }
    let l00 = s00.sqrt();
    let l10 = b / l00;
    let t = s11 - l10 * l10;
    if t <= 1e-14 {
        return Err("Heterodyne sampling failed: innovation covariance is not SPD".to_string());
    }
    let l11 = t.sqrt();

    let z0 = rng.standard_normal();
    let z1 = rng.standard_normal();
    let e0 = l00 * z0;
    let e1 = l10 * z0 + l11 * z1;
    let y0 = mu0 + e0;
    let y1 = mu1 + e1;

    let residual0 = y0 - mu0;
    let residual1 = y1 - mu1;

    let mut new_mean = state.mean.clone();
    let mut new_cov = state.cov.clone();
    let h_row0 = &state.cov[i];
    let h_row1 = &state.cov[i + 1];

    for row in 0..dim {
        let v0 = state.cov[row][i];
        let v1 = state.cov[row][i + 1];
        let k0 = v0 * inv00 + v1 * inv10;
        let k1 = v0 * inv01 + v1 * inv11;

        new_mean[row] += k0 * residual0 + k1 * residual1;

        for col in 0..dim {
            new_cov[row][col] -= k0 * h_row0[col] + k1 * h_row1[col];
        }
    }

    Ok((
        (y0, y1),
        GaussianState {
            modes: state.modes,
            mean: new_mean,
            cov: new_cov,
        },
    ))
}

impl Complex64 {
    const ZERO: Complex64 = Complex64 { re: 0.0, im: 0.0 };
    const ONE: Complex64 = Complex64 { re: 1.0, im: 0.0 };

    fn conj(self) -> Complex64 {
        Complex64 {
            re: self.re,
            im: -self.im,
        }
    }

    fn abs2(self) -> f64 {
        self.re * self.re + self.im * self.im
    }
}

impl std::ops::Add for Complex64 {
    type Output = Complex64;
    fn add(self, rhs: Complex64) -> Complex64 {
        Complex64 {
            re: self.re + rhs.re,
            im: self.im + rhs.im,
        }
    }
}

impl std::ops::Sub for Complex64 {
    type Output = Complex64;
    fn sub(self, rhs: Complex64) -> Complex64 {
        Complex64 {
            re: self.re - rhs.re,
            im: self.im - rhs.im,
        }
    }
}

impl std::ops::Mul for Complex64 {
    type Output = Complex64;
    fn mul(self, rhs: Complex64) -> Complex64 {
        Complex64 {
            re: self.re * rhs.re - self.im * rhs.im,
            im: self.re * rhs.im + self.im * rhs.re,
        }
    }
}

impl std::ops::Mul<f64> for Complex64 {
    type Output = Complex64;
    fn mul(self, rhs: f64) -> Complex64 {
        Complex64 {
            re: self.re * rhs,
            im: self.im * rhs,
        }
    }
}

impl std::ops::Div<f64> for Complex64 {
    type Output = Complex64;
    fn div(self, rhs: f64) -> Complex64 {
        Complex64 {
            re: self.re / rhs,
            im: self.im / rhs,
        }
    }
}

impl FockState {
    fn vacuum(cutoff: usize) -> Self {
        let mut psi = vec![Complex64::ZERO; cutoff];
        psi[0] = Complex64::ONE;
        Self { cutoff, psi }
    }

    fn normalize(&mut self) {
        let norm2 = self.psi.iter().fold(0.0, |acc, value| acc + value.abs2());
        let norm = norm2.max(1e-300).sqrt();
        self.psi.iter_mut().for_each(|value| *value = *value / norm);
    }

    fn expected_photon_number(&self) -> f64 {
        let mut total = 0.0;
        for (n, amplitude) in self.psi.iter().enumerate() {
            total += n as f64 * amplitude.abs2();
        }
        total
    }
}

fn fock_state_fock(n: usize, cutoff: usize) -> Result<FockState, String> {
    if n >= cutoff {
        return Err(format!(
            "Fock state index n={} exceeds cutoff {}",
            n, cutoff
        ));
    }
    let mut psi = vec![Complex64::ZERO; cutoff];
    psi[n] = Complex64::ONE;
    Ok(FockState { cutoff, psi })
}

fn fock_state_coherent(alpha: Complex64, cutoff: usize) -> FockState {
    let a2 = alpha.abs2();
    let pref = (-0.5 * a2).exp();
    let mut psi = vec![Complex64::ZERO; cutoff];
    for (n, slot) in psi.iter_mut().enumerate().take(cutoff) {
        let mut pow = Complex64::ONE;
        for _ in 0..n {
            pow = pow * alpha;
        }
        let coeff = pref / factorial_sqrt(n);
        *slot = pow * coeff;
    }
    let mut state = FockState { cutoff, psi };
    state.normalize();
    state
}

fn fock_state_cat(alpha: f64, cutoff: usize, even: bool) -> FockState {
    let plus = fock_state_coherent(Complex64 { re: alpha, im: 0.0 }, cutoff);
    let minus = fock_state_coherent(
        Complex64 {
            re: -alpha,
            im: 0.0,
        },
        cutoff,
    );
    let mut psi = vec![Complex64::ZERO; cutoff];
    for (n, slot) in psi.iter_mut().enumerate().take(cutoff) {
        *slot = if even {
            plus.psi[n] + minus.psi[n]
        } else {
            plus.psi[n] - minus.psi[n]
        };
    }
    let mut state = FockState { cutoff, psi };
    state.normalize();
    state
}

fn factorial_sqrt(n: usize) -> f64 {
    if n < 2 {
        return 1.0;
    }
    let mut value = 1.0;
    for k in 2..=n {
        value *= k as f64;
    }
    value.sqrt()
}

type CMat = Vec<Vec<Complex64>>;
type CVec = Vec<Complex64>;

fn c_zeros(rows: usize, cols: usize) -> CMat {
    vec![vec![Complex64::ZERO; cols]; rows]
}

fn c_eye(size: usize) -> CMat {
    let mut matrix = c_zeros(size, size);
    for (i, row) in matrix.iter_mut().enumerate().take(size) {
        row[i] = Complex64::ONE;
    }
    matrix
}

fn c_add(a: &CMat, b: &CMat) -> CMat {
    let rows = a.len();
    let cols = a[0].len();
    let mut out = c_zeros(rows, cols);
    for i in 0..rows {
        for j in 0..cols {
            out[i][j] = a[i][j] + b[i][j];
        }
    }
    out
}

fn c_scale(a: &CMat, alpha: Complex64) -> CMat {
    let rows = a.len();
    let cols = a[0].len();
    let mut out = c_zeros(rows, cols);
    for i in 0..rows {
        for j in 0..cols {
            out[i][j] = a[i][j] * alpha;
        }
    }
    out
}

fn c_matmul(a: &CMat, b: &CMat) -> CMat {
    let rows = a.len();
    let inner = a[0].len();
    let cols = b[0].len();
    let mut out = c_zeros(rows, cols);
    for i in 0..rows {
        for j in 0..cols {
            let mut sum = Complex64::ZERO;
            for k in 0..inner {
                sum = sum + a[i][k] * b[k][j];
            }
            out[i][j] = sum;
        }
    }
    out
}

fn c_matvec(a: &CMat, x: &CVec) -> CVec {
    let rows = a.len();
    let cols = a[0].len();
    let mut out = vec![Complex64::ZERO; rows];
    for i in 0..rows {
        let mut sum = Complex64::ZERO;
        for (j, value) in x.iter().enumerate().take(cols) {
            sum = sum + a[i][j] * *value;
        }
        out[i] = sum;
    }
    out
}

fn fock_annihilation(cutoff: usize) -> CMat {
    let mut op = c_zeros(cutoff, cutoff);
    for n in 1..cutoff {
        op[n - 1][n] = Complex64 {
            re: (n as f64).sqrt(),
            im: 0.0,
        };
    }
    op
}

fn fock_creation(cutoff: usize) -> CMat {
    let mut op = c_zeros(cutoff, cutoff);
    for n in 0..(cutoff - 1) {
        op[n + 1][n] = Complex64 {
            re: ((n + 1) as f64).sqrt(),
            im: 0.0,
        };
    }
    op
}

fn fock_displacement_operator(alpha: Complex64, cutoff: usize, terms: usize) -> CMat {
    let a = fock_annihilation(cutoff);
    let ad = fock_creation(cutoff);
    let g1 = c_scale(&ad, alpha);
    let g2 = c_scale(
        &a,
        Complex64 {
            re: -alpha.conj().re,
            im: -alpha.conj().im,
        },
    );
    let g = c_add(&g1, &g2);
    c_expm(&g, terms)
}

fn c_expm(a: &CMat, terms: usize) -> CMat {
    let size = a.len();
    let mut result = c_eye(size);
    let mut term = c_eye(size);
    for k in 1..=terms {
        term = c_matmul(&term, a);
        let inv = 1.0 / k as f64;
        term = c_scale(&term, Complex64 { re: inv, im: 0.0 });
        result = c_add(&result, &term);
    }
    result
}

fn fock_apply_phase(state: &mut FockState, theta: f64) {
    for n in 0..state.cutoff {
        let angle = -theta * n as f64;
        let ph = Complex64 {
            re: angle.cos(),
            im: angle.sin(),
        };
        state.psi[n] = state.psi[n] * ph;
    }
    state.normalize();
}

fn fock_apply_unitary(unitary: &CMat, state: &FockState) -> FockState {
    let out = c_matvec(unitary, &state.psi);
    let mut result = FockState {
        cutoff: state.cutoff,
        psi: out,
    };
    result.normalize();
    result
}

impl SeededRng {
    fn new(seed: u64) -> Self {
        Self {
            state: seed.wrapping_add(0x9E37_79B9_7F4A_7C15),
        }
    }

    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    fn uniform_open01(&mut self) -> f64 {
        let value = self.next_u64() >> 11;
        let mut unit = (value as f64) * (1.0 / ((1_u64 << 53) as f64));
        if unit <= 0.0 {
            unit = f64::MIN_POSITIVE;
        }
        if unit >= 1.0 {
            unit = 1.0 - f64::EPSILON;
        }
        unit
    }

    fn standard_normal(&mut self) -> f64 {
        let u1 = self.uniform_open01();
        let u2 = self.uniform_open01();
        (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()
    }
}

fn la_eye(size: usize) -> MatF {
    MatF::eye(size)
}

fn la_matvec(a: &MatF, x: &VecF) -> VecF {
    let rows = a.len();
    let cols = a[0].len();
    let mut out = vec![0.0; rows];
    for i in 0..rows {
        let mut sum = 0.0;
        for (j, value) in x.iter().enumerate().take(cols) {
            sum += a[i][j] * *value;
        }
        out[i] = sum;
    }
    out
}

fn la_dot(a: &VecF, b: &VecF) -> f64 {
    a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_round(syndrome_value: f64, lattice_spacing: f64, logical_pass: bool) -> QecRoundRecord {
        QecRoundRecord {
            round: 1,
            gate_index: 0,
            measurement_index: 0,
            source_value_index: 0,
            mode: 0,
            syndrome_value,
            decoder: "gkp_nearest_lattice_rounding".to_string(),
            lattice_spacing,
            target_lattice_index: 0,
            nearest_lattice_index: if logical_pass { 0 } else { 1 },
            nearest_lattice_value: if logical_pass { 0.0 } else { lattice_spacing },
            residual: syndrome_value,
            correction_value: 0.0,
            applied_q: 0.0,
            applied_p: 0.0,
            logical_pass,
        }
    }

    #[test]
    fn qec_quality_metrics_include_suppression_and_break_even() {
        let rounds = vec![sample_round(0.60, 2.0, true), sample_round(1.20, 2.0, false)];
        let summary = QecSummary {
            rounds_executed: rounds.len(),
            logical_pass_count: 1,
            logical_fail_count: 1,
            logical_pass: false,
        };

        let metrics = derive_qec_quality_metrics(&rounds, &summary);

        assert!((metrics.logical_error_rate - 0.5).abs() < 1e-12);
        assert!((metrics.physical_error_rate_proxy.unwrap_or(-1.0) - 1.0).abs() < 1e-12);
        assert!((metrics.suppression_factor.unwrap_or(-1.0) - 2.0).abs() < 1e-12);
        assert!((metrics.break_even_gain.unwrap_or(-1.0) - 0.5).abs() < 1e-12);
        assert!(metrics.break_even_pass);
    }

    #[test]
    fn qec_payload_exposes_quality_metrics() {
        let round = sample_round(0.75, 2.0, true);
        let execution = ExecutionResult {
            backend_used: "gaussian".to_string(),
            mean_photon_number: 0.0,
            measurement_count: 1,
            frames: Vec::new(),
            trace_total_ms: 0.0,
            final_state: json!({}),
            qec_rounds: vec![round],
            qec_summary: Some(QecSummary {
                rounds_executed: 1,
                logical_pass_count: 1,
                logical_fail_count: 0,
                logical_pass: true,
            }),
        };

        let payload = qec_payload(&execution);
        assert_eq!(
            payload
                .get("logical_error_rate")
                .and_then(Value::as_f64)
                .unwrap_or(-1.0),
            0.0
        );
        assert!(payload
            .get("suppression_factor")
            .and_then(Value::as_f64)
            .unwrap_or(0.0)
            >= 1_000_000.0);
        assert!(payload
            .get("break_even_pass")
            .and_then(Value::as_bool)
            .unwrap_or(false));
    }
}
