# Architecture

## High-Level Runtime Architecture

```text
JSON Circuit Input
  -> IR Parse + Validation
  -> Foundry Compile/Policy Checks
  -> Backend Routing (gaussian/fock/hybrid)
  -> Execution (Swift or Rust runtime path)
  -> Outputs (result JSON, trace frames, metrics, artifacts)
```

## Main Components

- Swift core SDK: `core-swift/Sources/SchroSIM`
- Swift CLI: `core-swift/Sources/schrosim-cli`
- Rust runtime CLI: `core-rust/schrosim-core`
- Config and governance:
  - `config/foundry_registry.json`
  - `config/trace_rbac_policy.json`
  - `config/kpi_policies.json`

## Public Module Map

- Core state/evolution/channels:
  - `core/state/*`
  - `core/evolution/*`
  - `core/operators/*`
- Compiler and IR:
  - `src/compiler/ir/*`
  - `src/compiler/foundry/*`
- Runtime orchestration:
  - `src/core/simulator.swift`
  - `src/core/backend_routing.swift`
  - `src/core/gkp_decoder.swift`

## Execution Paths

- Swift CLI path: direct compile/run/trace/stream/share.
- Rust CLI path: run/trace/bench/parity and foundry validation parity.

## Architecture Guarantees (Current)

- Deterministic seed support.
- Explicit backend routing decisions.
- Foundry policy and signature checks in production profile flows.
