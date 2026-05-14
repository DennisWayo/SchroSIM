# Contributing to SchroSIM

Thanks for contributing to SchroSIM. This project spans CV photonic simulation, backend-aware compilation, and runtime tooling across Swift and Rust, so clear change scopes and reproducible validation are important.

## Ground Rules
1. Be respectful and professional in all interactions. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
2. Keep pull requests focused on one logical change.
3. Add or update tests when behavior changes.
4. Update docs/examples when user-facing behavior changes.
5. For security-sensitive issues, follow [SECURITY.md](SECURITY.md) instead of opening a public bug.

## Public/Private Boundary
This public repository is for CLI/core/docs workflows.

Enterprise GUI implementation is intentionally kept private and is excluded from public contributions. Enterprise-only files must live under `enterprise/`.
If a change depends on enterprise GUI internals, capture the interface need in public (API/contracts/docs) and implement the GUI side in the private repository.
Public integration should occur through stable interfaces so the GUI can later be consumed as a private dependency.

## Where Contributions Help Most
1. CV simulation accuracy and performance.
2. Compiler and backend-policy validation.
3. Runtime diagnostics and failure explainability.
4. Example circuits, benchmark baselines, and documentation quality.

## Development Prerequisites
- macOS 13+ (current repo workflow target)
- Xcode with command-line tools (for Swift build/tests)
- Swift 5.9+
- Rust stable toolchain + Cargo
- Python 3 (used by validation scripts)

## Local Setup
```bash
swift build
cargo test -p schrosim-core
bash scripts/swift-test.sh
```

## Validation Commands
Use the commands below based on the area you changed.

Core functionality:
```bash
bash scripts/cv-validation-suite.sh --runtime both
```

Trace/runtime SLO checks:
```bash
bash scripts/trace-slo-check.sh --max-gates 512 --max-frame-ms 50
```

Compute benchmark smoke:
```bash
bash scripts/compute-benchmark.sh --backend gaussian --modes 2 --layers 16 --iterations 2 --compute-backends auto,cpu,metal --max-p95-ms 500
```

## Branch and Pull Request Workflow
1. Create a feature branch from `main`.
2. Implement the change in the smallest practical scope.
3. Run relevant tests/validation commands.
4. Commit with clear messages.
5. Open a PR with a concise summary, motivation/impact, validation commands run, and any follow-up work not included.

## Commit Message Guidance
Use short, explicit subjects. Format:

`<area>: <imperative summary>`

Examples:
- `core-rust: add backend validation for thermal loss bounds`
- `core-swift: fix trace frame ordering for hybrid runtime`
- `docs: clarify exact-solution scope in README`

## Review Expectations
- New behavior should have tests or a clear justification for test gaps.
- Changes that affect both runtimes should keep semantics aligned.
- Performance-sensitive changes should include at least one benchmark or regression check.
- PRs should avoid unrelated refactors.

## Reporting Bugs and Requesting Features
Open a GitHub issue with:
1. Expected behavior.
2. Observed behavior.
3. Minimal reproduction input (JSON/config).
4. Command used and backend mode.
5. Platform details (macOS version, Swift/Rust toolchain versions).
