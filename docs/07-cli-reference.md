# CLI Reference

## Swift CLI (`schrosim-cli`)

Primary commands:

1. `version`
2. `info`
3. `run <file>`
4. `trace <file>`
5. `trace-stream <file>`
6. `trace-share <artifact_file>`
7. `benchmark`
8. `foundry-admin <add-draft|promote>`

For full usage strings, see:

- `core-swift/Sources/schrosim-cli/main.swift`

## Rust CLI (`schrosim-core`)

Primary commands:

1. `version`
2. `info`
3. `run <file>`
4. `trace <file>`
5. `bench`
6. `parity` (debug-enabled builds)

For full usage strings, see:

- `core-rust/schrosim-core/src/main.rs`

## Common Runtime Options

- `--backend <auto|gaussian|fock|hybrid>`
- `--cutoff <n>`
- `--seed <uint64>`
- foundry and production options
- trace and RBAC options
