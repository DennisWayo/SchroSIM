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

- [CONTRIBUTING.md](https://github.com/DennisWayo/SchroSIM/blob/master/CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](https://github.com/DennisWayo/SchroSIM/blob/master/CODE_OF_CONDUCT.md)
- [SECURITY.md](https://github.com/DennisWayo/SchroSIM/blob/master/SECURITY.md)

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

## Python Package Publishing (PyPI)

- Python package metadata lives in `pyproject.toml`.
- Package source is in `src/schrosim/`.
- Local build checks:
  - `python3 -m pip install --upgrade build twine`
  - `python3 -m build --sdist`
  - `python3 -m twine check dist/*`
- Publish via GitHub Actions:
  - workflow: `.github/workflows/pypi-publish.yml`
  - run manually with `repository=testpypi` first, then `repository=pypi`.
  - workflow builds:
    - one source distribution (`sdist`),
    - macOS wheels (`macos-15-intel` + `macos-14`) with bundled `schrosim-cli` backend.
