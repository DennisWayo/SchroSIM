#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SIM_BACKEND="gaussian"
MODES=4
LAYERS=48
ITERATIONS=5
CUTOFF=20
SEED=7
COMPUTE_BACKENDS_CSV="auto,cpu,metal"
MAX_P95_MS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      SIM_BACKEND="$2"
      shift 2
      ;;
    --modes)
      MODES="$2"
      shift 2
      ;;
    --layers)
      LAYERS="$2"
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
    --compute-backends)
      COMPUTE_BACKENDS_CSV="$2"
      shift 2
      ;;
    --max-p95-ms)
      MAX_P95_MS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

IFS=',' read -r -a COMPUTE_BACKENDS <<<"${COMPUTE_BACKENDS_CSV}"

cd "${ROOT_DIR}"

for compute_backend in "${COMPUTE_BACKENDS[@]}"; do
  tmp_output="$(mktemp "${TMPDIR:-/tmp}/schrosim-compute-benchmark.XXXXXX.json")"
  swift run schrosim-cli benchmark \
    --backend "${SIM_BACKEND}" \
    --compute-backend "${compute_backend}" \
    --modes "${MODES}" \
    --layers "${LAYERS}" \
    --iterations "${ITERATIONS}" \
    --cutoff "${CUTOFF}" \
    --seed "${SEED}" > "${tmp_output}"

  if ! python3 - "${compute_backend}" "${MAX_P95_MS}" "${tmp_output}" <<'PY'
import json
import sys

requested_compute_backend = sys.argv[1]
max_p95_arg = sys.argv[2]
payload_path = sys.argv[3]

with open(payload_path, "r", encoding="utf-8") as f:
    raw = f.read()

start = raw.find("{")
if start < 0:
    raise SystemExit(f"benchmark output for {requested_compute_backend} did not contain JSON")

payload = json.loads(raw[start:])

if payload.get("status") != "success":
    raise SystemExit(f"benchmark failed for {requested_compute_backend}: {payload}")

reported_requested = payload.get("compute_backend_requested")
if reported_requested != requested_compute_backend:
    raise SystemExit(
        "compute backend mismatch: requested "
        f"{requested_compute_backend}, payload has {reported_requested}"
    )

latency = payload.get("latency_ms") or {}
p95 = float(latency.get("p95", 0.0))
avg = float(latency.get("avg", 0.0))
used = payload.get("compute_backend_used", "unknown")
fallback = payload.get("compute_backend_fallback_reason")

if max_p95_arg:
    max_p95 = float(max_p95_arg)
    if p95 > max_p95:
        raise SystemExit(
            f"p95 latency SLO violation for {requested_compute_backend}: "
            f"{p95:.6f} ms > {max_p95:.6f} ms"
        )

print(
    "benchmark "
    f"requested={requested_compute_backend} used={used} "
    f"avg_ms={avg:.6f} p95_ms={p95:.6f} fallback={fallback}"
)
PY
  then
    rm -f "${tmp_output}"
    exit 1
  fi
  rm -f "${tmp_output}"
done
