# Circuit IR and Schema

## Core Circuit Object

Circuit data includes:

- `schema_version`
- `modes`
- `backend`
- `seed`
- optional `cutoff`
- foundry block (`foundry` or `foundry_profile`)
- ordered `gates`

## Gate Taxonomy

1. Gaussian unitary gates:
   - `phase`, `squeeze`, `beam_splitter`, `displace`
2. Channels:
   - `loss`, `thermal_loss`
3. Measurements:
   - `measure_homodyne`, `measure_heterodyne`
4. Feed-forward / decoding:
   - `feedback_displace`, `gkp_decode_displace`
5. Non-Gaussian injections:
   - `inject_fock`, `inject_cat`, `inject_gkp`

## Validation Model

Validation checks enforce:

- valid mode index ranges,
- parameter domain constraints (e.g., `eta in [0,1]`, finite values),
- measurement reference consistency for conditional gates.

Primary IR sources:

- `core-swift/Sources/SchroSIM/src/compiler/ir/circuit_ir.swift`
- `core-swift/Sources/SchroSIM/src/compiler/ir/gate_ir.swift`
- `core-swift/Sources/SchroSIM/src/compiler/ir/ir_validation_error.swift`

## Example Inputs

- `examples/runtime_default_foundry.json`
- `examples/fock_injection_smoke.json`
- `examples/cv/qec_single_logical_gkp_memory_mvp.json`
