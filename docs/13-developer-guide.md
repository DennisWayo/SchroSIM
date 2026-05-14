# Developer Guide

## Repository Layout

- Swift package manifest: `Package.swift`
- Rust workspace manifest: `Cargo.toml`
- Swift core and CLI: `core-swift/Sources/*`
- Rust runtime: `core-rust/schrosim-core/*`
- Scripts and baselines: `scripts/*`, `benchmarks/*`

## Build and Test

```bash
swift build
bash scripts/swift-test.sh
cargo test -p schrosim-core
```

## Validation and Performance Gates

```bash
bash scripts/cv-validation-suite.sh --runtime both
bash scripts/trace-slo-check.sh --max-gates 512 --max-frame-ms 50
```

## Debugging

See detailed guide:

- [DEBUGGING.md](DEBUGGING.md)

## Contribution and Security Policies

- [../CONTRIBUTING.md](../CONTRIBUTING.md)
- [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md)
- [../SECURITY.md](../SECURITY.md)

## Public Release Process (Current)

Until full automation is added, use this manual flow for public releases:

1. Preflight checks:
   - `bash scripts/swift-test.sh`
   - `cargo test -p schrosim-core`
   - `bash scripts/cv-validation-suite.sh --runtime both`
2. Benchmark gates:
   - `bash scripts/trace-slo-check.sh --max-gates 512 --max-frame-ms 50`
   - `bash scripts/compute-benchmark.sh --backend gaussian --modes 2 --layers 16 --iterations 2 --compute-backends auto,cpu,metal --max-p95-ms 500`
3. Version updates (if releasing):
   - Swift CLI version constant in `core-swift/Sources/schrosim-cli/main.swift`
   - Rust CLI version constant in `core-rust/schrosim-core/src/main.rs`
4. Public-scope hygiene:
   - ensure `enterprise/` private material remains ignored,
   - ensure README/docs do not depend on enterprise-only assets.
5. Tag and publish:
   - create release tag (`vX.Y.Z`),
   - publish release notes summarizing API/CLI changes, validation coverage, and known limitations.

When CI/release automation is introduced, this section should be replaced by the workflow file references and required status checks.
