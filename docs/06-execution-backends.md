# Execution Backends

## Backend Options

- `gaussian`
- `fock`
- `hybrid`
- `auto` (routing decision)

## Gaussian Path

Gaussian simulation uses phase-space state (`mean`, `cov`) and applies:

- affine symplectic transforms,
- Gaussian channel updates (loss/thermal),
- Gaussian conditioning for measurements.

## Fock Path

Current Fock implementation constraints:

- single-mode only,
- supported gates: `phase`, `displace`, `inject_fock`, `inject_cat`.

## Hybrid Routing

Routing resolves runtime backend from requested mode and circuit content:

- non-Gaussian Fock/cat injections trigger Fock path,
- otherwise Gaussian path is selected (subject to compatibility checks).

Routing source:

- `core-swift/Sources/SchroSIM/src/core/backend_routing.swift`

## Compute Backend (CPU/Metal)

Compute backend selection for linear algebra:

- `auto`, `cpu`, `metal`
- heuristic candidate selection with fallback handling.

References:

- `backends/compute/compute_backend.swift`
- `backends/compute/compute_execution_context.swift`
- `backends/compute/metal_linear_algebra.swift`
