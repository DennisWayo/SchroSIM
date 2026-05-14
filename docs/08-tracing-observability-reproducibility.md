# Tracing, Observability, and Reproducibility

## Trace Modes

- `trace` for complete trace result payloads
- `trace-stream` for incremental transport:
  - `ndjson`
  - `sse`

## Trace Artifact and Share

Trace flows support:

- artifact generation,
- signature attachment and verification,
- share tickets,
- RBAC checks (`view`, `export`, `share`).

Policies:

- `config/trace_rbac_policy.json`

## Determinism Contract

Reproducibility target is based on:

- same circuit payload,
- same seed,
- same foundry profile/config,
- same backend and compatible runtime path.

## Trace Frame Schema

Each frame entry in trace payloads follows:

| Field | Type | Meaning |
|---|---|---|
| `frame_index` | integer | Monotonic frame index; `0` is synthetic initial frame. |
| `gate_index` | integer or `null` | Gate index in compiled circuit; `null` for initial frame. |
| `gate_type` | string | Gate label (`phase`, `loss`, `measure_homodyne`, etc.). |
| `mean_photon_number` | number | Mean photon estimate after this step. |
| `measurement_count` | integer | Number of measurements emitted so far. |
| `frame_latency_ms` | number | Per-frame compute latency in milliseconds. |

`trace` returns these frames under `frames[]`; `trace-stream` emits them as `frame` events.

## Trace Stream Event Contract

`trace-stream` uses:

- `ndjson`: one compact JSON object per line with an added top-level `event` field.
- `sse`: `event: <name>` and `data: <json>` blocks.

Event sequence:

1. `meta` with run metadata (`backend_requested`, `compute_backend_*`, `foundry_source`, counts).
2. one or more `frame` events.
3. terminal `done` event on success, or `error` event on failure.

## Artifact Envelope Schema

When `trace --trace-artifact <file>` is used, SchroSIM writes an envelope:

```json
{
  "schema_version": 1,
  "artifact_type": "schrosim.trace.artifact",
  "generated_at": "ISO-8601 timestamp",
  "payload": { "... trace command payload ..." },
  "signature": "hex-hmac-or-null"
}
```

The payload contains `replay_checksum` plus execution metadata and `frames`.

## Signature and Replay Verification Semantics

`trace-share` verification logic is:

1. parse envelope and payload,
2. recompute replay checksum from payload (`schema_version`, backend/compiler/contraction metadata, foundry hash, seed, compute backend fields, normalized frames),
3. compare to provided `replay_checksum`,
4. if `signature` is present, require key and verify HMAC over the envelope without `signature`,
5. emit `signature_verified=true|false` in successful share response.

## Deterministic Replay Caveats

- Omitted seed means runtime RNG is non-deterministic; replay checksum stability is not guaranteed across runs.
- Changing `backend`, `compute_backend_used`, or fallback routing changes replay checksum even with the same circuit.
- Frame downsampling (`--max-frames`) and ring buffering (`--ring-buffer`) change the retained frame set and therefore checksum.
- Foundry profile edits (even with same profile ID) change `foundry_profile_hash` and invalidate previous checksums.
