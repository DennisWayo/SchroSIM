#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="both"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      RUNTIME="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$RUNTIME" != "swift" && "$RUNTIME" != "rust" && "$RUNTIME" != "both" ]]; then
  echo "--runtime must be one of: swift, rust, both" >&2
  exit 2
fi

CASES=(
  "examples/cv/foundry_validation_single_mode_squeezing.json"
  "examples/cv/foundry_validation_two_mode_epr_loss.json"
  "examples/cv/foundry_validation_thermal_heterodyne.json"
  "examples/cv/foundry_validation_single_mode_fock_response.json"
)

extract_summary() {
  python3 -c '
import json
import sys

raw = sys.stdin.read()
start = raw.find("{")
if start < 0:
    raise SystemExit("command output did not contain JSON payload")

payload = json.loads(raw[start:])
if payload.get("status") != "success":
    raise SystemExit(f"execution failed: {payload}")

print(
    "backend_used={backend} backend_requested={requested} gates={gates} measurements={measurements} mean_photon={mean}".format(
        backend=payload.get("backend"),
        requested=payload.get("backend_requested"),
        gates=payload.get("gate_count"),
        measurements=payload.get("measurement_count"),
        mean=payload.get("mean_photon_number"),
    )
)
'
}

cd "$ROOT_DIR"

for case_path in "${CASES[@]}"; do
  echo
  echo "case=${case_path}"
  if [[ "$RUNTIME" == "swift" || "$RUNTIME" == "both" ]]; then
    echo "  swift:"
    swift run schrosim-cli run "$case_path" | extract_summary | sed 's/^/    /'
  fi
  if [[ "$RUNTIME" == "rust" || "$RUNTIME" == "both" ]]; then
    echo "  rust:"
    cargo run -p schrosim-core -- run "$case_path" | extract_summary | sed 's/^/    /'
  fi
done
