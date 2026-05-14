# Quick Start

## Prerequisites

Install and verify:

```bash
python3 --version
pip --version
swift --version
rustc --version
cargo --version
```

## Run From Source

```bash
swift run schrosim-cli --help
```

Python is required for helper scripts, but there are currently no third-party Python package requirements in this repo.

## First Demo Runs

```bash
schrosim run examples/runtime_default_foundry.json --backend hybrid
schrosim run examples/cv/qec_single_logical_gkp_memory_mvp.json --backend hybrid
```

## Optional Contributor Workflow (CLion)

CLion is useful for debugging and stepping through code paths. CLI commands remain the primary reproducible path for docs and CI.
