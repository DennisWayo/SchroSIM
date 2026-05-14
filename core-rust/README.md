# core-rust

This folder contains Rust crates for SchroSIM.

Current crate:

- `schrosim-gui` — egui desktop app that invokes the Swift CLI
- `schrosim-core` — Rust CLI runtime (`run`, `trace`) used by SwiftUI runtime-engine selection
- `schrosim-core` now includes:
  - Gaussian simulation kernels (phase/squeeze/beam-splitter/displace/loss/thermal/measurement)
  - Measurement-driven feedback displacement (`feedback_displace`) for syndrome-based correction loops
  - GKP nearest-lattice decode correction gate (`gkp_decode_displace`) with per-round QEC logs and summary metrics (`logical_error_rate`, `suppression_factor`, `break_even_gain`)
  - Fock single-mode path (`phase`, `displace`, `inject_fock`, `inject_cat`)
  - Foundry compile step parity (validation + optional injected mode-loss)
  - `parity` command to compare Rust output against `schrosim-cli`
- GUI default backend is `hybrid` (recommended enterprise routing policy)
- Compiler/contraction recommendation is sourced from CLI policy:
  - compiler: `foundry-aware-ir-v1`
  - contraction policy: `hybrid_auto`
- GUI includes trace-driven live playback:
  - `Load trace` calls `schrosim-cli trace ...`
  - `Play/Pause/Stop` animates per-gate propagation frames continuously

Build/test from repo root with:

```bash
cargo test -p schrosim-gui
cargo run -p schrosim-gui
cargo run -p schrosim-core -- run exports/swiftui_runtime_input.json --backend hybrid
cargo run -p schrosim-core -- trace exports/swiftui_runtime_input.json --backend hybrid --trace-role editor
cargo run -p schrosim-core -- parity exports/swiftui_runtime_input.json --backend hybrid --trace-role editor
```
