#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAX_GATES=512
MAX_FRAME_MS=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-gates)
      MAX_GATES="$2"
      shift 2
      ;;
    --max-frame-ms)
      MAX_FRAME_MS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

TMP_INPUT="$(mktemp "${TMPDIR:-/tmp}/schrosim-trace-slo-input.XXXXXX.json")"
TMP_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/schrosim-trace-slo-output.XXXXXX.json")"
trap 'rm -f "${TMP_INPUT}" "${TMP_OUTPUT}"' EXIT

{
  echo "{"
  echo "  \"schema_version\": 1,"
  echo "  \"modes\": 1,"
  echo "  \"backend\": \"gaussian\","
  echo "  \"seed\": 7,"
  echo "  \"foundry\": {\"name\":\"trace_slo\",\"inject_mode_loss\":false},"
  echo "  \"gates\": ["
  for ((i=0; i<MAX_GATES; i++)); do
    SUFFIX=","
    if [[ $i -eq $((MAX_GATES - 1)) ]]; then
      SUFFIX=""
    fi
    echo "    {\"type\":\"phase\",\"theta\":0.015625,\"mode\":0}${SUFFIX}"
  done
  echo "  ]"
  echo "}"
} > "${TMP_INPUT}"

cd "${ROOT_DIR}"

TRACE_OUTPUT="$(swift run schrosim-cli trace "${TMP_INPUT}" --backend gaussian --max-frames 2048)"
printf '%s\n' "${TRACE_OUTPUT}" > "${TMP_OUTPUT}"

python3 - "$MAX_GATES" "$MAX_FRAME_MS" "${TMP_OUTPUT}" <<'PY'
import json
import sys

expected_gates = int(sys.argv[1])
max_frame_ms = float(sys.argv[2])
payload_path = sys.argv[3]

with open(payload_path, "r", encoding="utf-8") as f:
    payload = json.load(f)

if payload.get("status") != "success":
    raise SystemExit(f"trace command failed: {payload}")

gate_count = int(payload["gate_count"])
if gate_count != expected_gates:
    raise SystemExit(f"SLO gate-count mismatch: expected {expected_gates}, got {gate_count}")

frame_latency = float(payload.get("trace_max_frame_latency_ms", 0.0))
if frame_latency > max_frame_ms:
    raise SystemExit(
        f"SLO frame-latency violation: {frame_latency:.6f} ms > {max_frame_ms:.6f} ms"
    )

print(
    f"Trace SLO check passed: gate_count={gate_count}, max_frame_latency_ms={frame_latency:.6f}"
)
PY
