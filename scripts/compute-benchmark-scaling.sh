#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SIM_BACKEND="gaussian"
COMPUTE_BACKENDS_CSV="auto,cpu,metal"
MODES_CSV="2,8,16"
LAYERS_CSV="8,24,64"
ITERATIONS=2
CUTOFF=20
SEED=7
MAX_P95_MS=""
OUTPUT_PATH=""
BASELINE_PATH=""
WRITE_BASELINE_PATH=""
MAX_REGRESSION_PCT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      SIM_BACKEND="$2"
      shift 2
      ;;
    --compute-backends)
      COMPUTE_BACKENDS_CSV="$2"
      shift 2
      ;;
    --modes-list)
      MODES_CSV="$2"
      shift 2
      ;;
    --layers-list)
      LAYERS_CSV="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --cutoff)
      CUTOFF="$2"
      shift 2
      ;;
    --seed)
      SEED="$2"
      shift 2
      ;;
    --max-p95-ms)
      MAX_P95_MS="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --baseline)
      BASELINE_PATH="$2"
      shift 2
      ;;
    --write-baseline)
      WRITE_BASELINE_PATH="$2"
      shift 2
      ;;
    --max-regression-pct)
      MAX_REGRESSION_PCT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

python3 - "${ROOT_DIR}" "${SIM_BACKEND}" "${COMPUTE_BACKENDS_CSV}" "${MODES_CSV}" "${LAYERS_CSV}" "${ITERATIONS}" "${CUTOFF}" "${SEED}" "${MAX_P95_MS}" "${OUTPUT_PATH}" "${BASELINE_PATH}" "${WRITE_BASELINE_PATH}" "${MAX_REGRESSION_PCT}" <<'PY'
import json
import subprocess
import sys
from itertools import product

(
    root_dir,
    sim_backend,
    compute_backends_csv,
    modes_csv,
    layers_csv,
    iterations_raw,
    cutoff_raw,
    seed_raw,
    max_p95_raw,
    output_path,
    baseline_path,
    write_baseline_path,
    max_regression_pct_raw,
) = sys.argv[1:]

compute_backends = [item.strip() for item in compute_backends_csv.split(",") if item.strip()]
modes = [int(item.strip()) for item in modes_csv.split(",") if item.strip()]
layers = [int(item.strip()) for item in layers_csv.split(",") if item.strip()]
iterations = int(iterations_raw)
cutoff = int(cutoff_raw)
seed = int(seed_raw)
max_p95 = float(max_p95_raw) if max_p95_raw else None
max_regression_pct = float(max_regression_pct_raw) if max_regression_pct_raw else 180.0
min_p95_delta_ms = 25.0
min_avg_delta_ms = 15.0

rows = []
print("backend,modes,layers,gate_count,candidate,used,p95_ms,avg_ms,fallback")

for backend, mode_count, layer_count in product(compute_backends, modes, layers):
    cmd = [
        "swift", "run", "schrosim-cli", "benchmark",
        "--backend", sim_backend,
        "--compute-backend", backend,
        "--modes", str(mode_count),
        "--layers", str(layer_count),
        "--iterations", str(iterations),
        "--cutoff", str(cutoff),
        "--seed", str(seed),
    ]
    result = subprocess.run(
        cmd,
        cwd=root_dir,
        capture_output=True,
        text=True,
        check=False,
    )

    raw_stdout = result.stdout
    start = raw_stdout.find("{")
    if start < 0:
        raise SystemExit(
            f"benchmark output for backend={backend}, modes={mode_count}, layers={layer_count} "
            f"did not contain JSON.\nSTDOUT:\n{raw_stdout}\nSTDERR:\n{result.stderr}"
        )

    payload = json.loads(raw_stdout[start:])
    if payload.get("status") != "success":
        raise SystemExit(
            f"benchmark failed for backend={backend}, modes={mode_count}, layers={layer_count}: {payload}"
        )

    latency = payload.get("latency_ms") or {}
    p95_ms = float(latency.get("p95", 0.0))
    avg_ms = float(latency.get("avg", 0.0))

    if max_p95 is not None and p95_ms > max_p95:
        raise SystemExit(
            f"p95 latency SLO violation backend={backend} modes={mode_count} layers={layer_count}: "
            f"{p95_ms:.6f} ms > {max_p95:.6f} ms"
        )

    row = {
        "backend": backend,
        "modes": mode_count,
        "layers": layer_count,
        "gate_count": int(payload.get("gate_count", 0)),
        "compute_backend_candidate": payload.get("compute_backend_candidate"),
        "compute_backend_used": payload.get("compute_backend_used"),
        "compute_backend_fallback_reason": payload.get("compute_backend_fallback_reason"),
        "latency_ms": {
            "p95": p95_ms,
            "avg": avg_ms,
        },
    }
    rows.append(row)

    print(",".join([
        backend,
        str(mode_count),
        str(layer_count),
        str(row["gate_count"]),
        str(row["compute_backend_candidate"]),
        str(row["compute_backend_used"]),
        f"{p95_ms:.6f}",
        f"{avg_ms:.6f}",
        str(row["compute_backend_fallback_reason"]),
    ]))

doc = {
    "schema_version": 1,
    "suite": "compute_scaling",
    "backend": sim_backend,
    "compute_backends": compute_backends,
    "modes": modes,
    "layers": layers,
    "iterations": iterations,
    "cutoff": cutoff,
    "seed": seed,
    "rows": rows,
}

if output_path:
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")

if write_baseline_path:
    with open(write_baseline_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")

if baseline_path:
    with open(baseline_path, "r", encoding="utf-8") as f:
        baseline = json.load(f)

    if baseline.get("suite") != "compute_scaling":
        raise SystemExit(
            f"baseline suite mismatch: expected 'compute_scaling', got {baseline.get('suite')!r}"
        )
    if baseline.get("backend") != sim_backend:
        raise SystemExit(
            f"baseline backend mismatch: expected {sim_backend!r}, got {baseline.get('backend')!r}"
        )
    baseline_backends = baseline.get("compute_backends") or []
    if baseline_backends != compute_backends:
        raise SystemExit(
            f"baseline compute_backends mismatch: expected {compute_backends!r}, got {baseline_backends!r}"
        )
    baseline_modes = baseline.get("modes") or []
    if baseline_modes != modes:
        raise SystemExit(
            f"baseline modes mismatch: expected {modes!r}, got {baseline_modes!r}"
        )
    baseline_layers = baseline.get("layers") or []
    if baseline_layers != layers:
        raise SystemExit(
            f"baseline layers mismatch: expected {layers!r}, got {baseline_layers!r}"
        )

    baseline_rows = baseline.get("rows") or []
    baseline_map = {}
    for entry in baseline_rows:
        key = (str(entry.get("backend")), int(entry.get("modes")), int(entry.get("layers")))
        baseline_map[key] = entry

    regressions = []
    factor = 1.0 + (max_regression_pct / 100.0)

    for row in rows:
        key = (row["backend"], row["modes"], row["layers"])
        base = baseline_map.get(key)
        if base is None:
            raise SystemExit(
                f"baseline missing row for backend={row['backend']} modes={row['modes']} layers={row['layers']}"
            )

        base_lat = base.get("latency_ms") or {}
        base_p95 = float(base_lat.get("p95", 0.0))
        base_avg = float(base_lat.get("avg", 0.0))
        base_candidate = base.get("compute_backend_candidate")
        base_used = base.get("compute_backend_used")

        if base_candidate != row["compute_backend_candidate"]:
            regressions.append({
                "backend": row["backend"],
                "modes": row["modes"],
                "layers": row["layers"],
                "metric": "compute_backend_candidate",
                "baseline": base_candidate,
                "current": row["compute_backend_candidate"],
                "limit": "exact_match",
            })
        if base_used != row["compute_backend_used"]:
            regressions.append({
                "backend": row["backend"],
                "modes": row["modes"],
                "layers": row["layers"],
                "metric": "compute_backend_used",
                "baseline": base_used,
                "current": row["compute_backend_used"],
                "limit": "exact_match",
            })

        p95_limit = max(base_p95 * factor, base_p95 + min_p95_delta_ms)
        avg_limit = max(base_avg * factor, base_avg + min_avg_delta_ms)

        current_p95 = float(row["latency_ms"]["p95"])
        current_avg = float(row["latency_ms"]["avg"])

        if current_p95 > p95_limit:
            regressions.append({
                "backend": row["backend"],
                "modes": row["modes"],
                "layers": row["layers"],
                "metric": "p95_ms",
                "baseline": base_p95,
                "current": current_p95,
                "limit": p95_limit,
            })
        if current_avg > avg_limit:
            regressions.append({
                "backend": row["backend"],
                "modes": row["modes"],
                "layers": row["layers"],
                "metric": "avg_ms",
                "baseline": base_avg,
                "current": current_avg,
                "limit": avg_limit,
            })

    if regressions:
        print("\nREGRESSIONS")
        for item in regressions:
            if item["metric"] in ("compute_backend_candidate", "compute_backend_used"):
                print(
                    "backend={backend} modes={modes} layers={layers} metric={metric} "
                    "baseline={baseline} current={current} limit={limit}".format(**item)
                )
            else:
                print(
                    "backend={backend} modes={modes} layers={layers} metric={metric} "
                    "baseline={baseline:.6f} current={current:.6f} limit={limit:.6f}".format(**item)
                )
        raise SystemExit(
            f"{len(regressions)} scaling benchmark regression(s) exceeded max-regression-pct={max_regression_pct}"
        )

auto_rows = [row for row in rows if row["backend"] == "auto"]
if auto_rows:
    print("\nAUTO CANDIDATE MAP")
    for row in auto_rows:
        print(
            f"m={row['modes']:>2} l={row['layers']:>3} gates={row['gate_count']:>4} "
            f"candidate={row['compute_backend_candidate']} used={row['compute_backend_used']} "
            f"p95={row['latency_ms']['p95']:.3f}ms"
        )
PY
