# SchroSIM Debugging Guide

## 1) Debug Rust GUI in CLion

### Prerequisites
- Open the repo root (`SchroSIM`) in CLion.
- Use the Cargo project at `Cargo.toml` (workspace root).

### Run configuration
1. Create a new `Cargo` run configuration:
   - `Command`: `run`
   - `Package`: `schrosim-gui`
   - `Working directory`: `$ProjectFileDir$`
2. Add environment variables:
   - `RUST_BACKTRACE=1` (also enforced via `.cargo/config.toml`)
   - Optional for Swift attach flow: `SCHROSIM_WAIT_SWIFT_DEBUGGER=1`
3. Start with `Debug` (not `Run`).

### Breakpoints to set
- `core-rust/schrosim-gui/src/main.rs` at `fn run_cli(...)`
- `core-rust/schrosim-gui/src/main.rs` at `fn parse_cli_output(...)` (JSON parsing logic)
- `core-rust/schrosim-gui/src/main.rs` inside `impl eframe::App for SchroSimApp` -> `fn update(...)`

### Verify breakpoints are hit
1. Launch debugger in CLion.
2. In GUI, click `Run circuit`.
3. Confirm debugger stops in `update`, then in `run_cli`, then in `parse_cli_output`.

## 2) Attach Xcode Debugger to Swift CLI Spawned by Rust GUI

### Enable wait mode
- Start Rust GUI from CLion with:
  - `SCHROSIM_WAIT_SWIFT_DEBUGGER=1`

When GUI invokes CLI, `schrosim-cli` is launched with `--wait-debugger` and pauses itself via `SIGSTOP`.

### Attach from Xcode
1. Open Xcode.
2. Choose `Debug` -> `Attach to Process by PID or Name...`.
3. Enter `schrosim-cli` and attach.
4. Press `Continue` in Xcode to resume the paused CLI process.

### Swift breakpoints
- `core-swift/Sources/schrosim-cli/main.swift` at `waitForDebuggerIfRequested(...)`
- `core-swift/Sources/schrosim-cli/main.swift` at JSON decode line in `handleRun(...)`
- `core-swift/Sources/schrosim-cli/main.swift` at `emitJSON(...)`

### Verify
1. With Rust GUI running under CLion debug, click `Run circuit`.
2. Attach Xcode to `schrosim-cli`.
3. Confirm Swift breakpoints trigger, then Rust returns to `parse_cli_output`.

## 3) Rust Workspace Layout

Rust is configured as a workspace at repo root, with crates in `core-rust/`:

```text
Cargo.toml                  # workspace + dev profile (debug symbols on)
core-rust/schrosim-gui/     # member crate
```

To add more Rust crates later, create a crate directory and add it to `members` in root `Cargo.toml`.

## 4) Fix `swift test` / XCTest in CLion

If `swift test` fails with `no such module 'XCTest'`, CLion is typically using only Command Line Tools (`/Library/Developer/CommandLineTools`).

### Required setup

1. Install full Xcode (App Store or Developer download).
2. In CLion, use the shared run config: `Swift Test (core-swift)`.
3. If your Xcode path differs, edit `DEVELOPER_DIR` in that run config.

Shared assets in repo:
- Script: `scripts/swift-test.sh`
- Run config: `.run/Swift Test (core-swift).run.xml`

The script auto-selects `Xcode.app` or `Xcode-beta.app`, sets `SDKROOT=macosx`, and runs `swift test`.
