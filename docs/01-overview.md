# Overview

## What SchroSIM Is

SchroSIM is a continuous-variable photonic quantum simulation stack with:

- a Swift core simulation SDK,
- a Swift CLI (`schrosim-cli`) for execution and tracing,
- a Rust runtime (`schrosim-core`) for parity/benchmark workflows and runtime operations.

## Who It Is For

- Students: learning CV photonic circuits and simulation workflows.
- Researchers: rapid experimentation across Gaussian/Fock/Hybrid paths.
- Quantum foundry engineers: policy-aware pre-hardware validation.

## Product Boundary

- Public repo: CLI/core/docs.
- Enterprise-specific materials: isolated under `enterprise/`.

## Why This Exists

Photonic and CV workflows require one place for design, compile, execution, diagnostics, and reproducibility.

## Document Conventions

- Quadrature ordering: `(q1, p1, q2, p2, ...)`.
- `modes = n` implies phase-space dimension `2n`.
- JSON examples in this docs set use `schema_version: 1`.
