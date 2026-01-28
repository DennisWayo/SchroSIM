<p align="center">
  <!-- Core Languages & Platform -->
  <img src="https://img.shields.io/badge/Rust-black?logo=rust&logoColor=white" />
  <img src="https://img.shields.io/badge/Python-black?logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-black?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Metal-GPU-black?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-black" />
</p>

# SchroSIM

**SchroSIM** is an **architecture-level, physics-aware simulator** for **exploring, validating, and mapping photonic quantum circuits** under realistic constraints (loss, finite squeezing, non-Gaussian resources).

It targets the “missing middle layer” between:
- **high-level algorithmic abstractions** (e.g., PennyLane), and
- **state-level continuous-variable simulation** (e.g., Strawberry Fields).

SchroSIM is designed to help researchers and educators reason about how abstract photonic programs map onto physical device layers and architectural trade-offs.

## Why SchroSIM?

Photonic quantum tooling often forces a choice:

1. **Algorithm-first** frameworks that hide device physics (great for QML and prototyping, weaker for architectural reasoning), or  
2. **Physics-first** simulators that are powerful but heavy for rapid architecture exploration.

**SchroSIM bridges the gap** with a modular approach for:

- **Architecture exploration:** phase boundaries for loss/squeezing/non-Gaussian resources  
- **Hardware-aware mapping:** logical → device → physical interpretation layers  
- **Education:** intuitive visualizations (phase space, quadratures, Wigner functions)  
- **Rapid “what-if” studies:** design rules without full wavefunction simulation


## What SchroSIM is (and is not)

 **SchroSIM is:**
- an architecture reasoning tool for photonic quantum circuits
- a platform for hardware-aware circuit exploration
- a modular simulator with Gaussian + non-Gaussian pathways

 **SchroSIM is not intended to replace:**
- **PennyLane** (algorithmic abstraction + QML workflows)
- **Strawberry Fields** (full CV state simulation engine)

Instead, SchroSIM aims to **complement** these projects by focusing on the architecture layer and integration boundaries.


## Project Highlights

- **Language:** Swift + SwiftUI + Metal
- **Simulation Modes:**  
  - *Gaussian* (symplectic / covariance formalism)  
  - *Non-Gaussian* (Fock/tensor-based modules; staged roadmap)
- **Platform:** macOS (Apple Silicon), with future portability goals
- **GUI (planned):** drag-and-drop photonic circuit builder
- **Compiler Layer (planned):** intermediate representation (IR) for hardware-agnostic mapping
- **Backends (roadmap):** CPU + GPU acceleration; optional integration with external QPU workflows


## Concept Note / Preprint

- **TechRxiv:** https://www.techrxiv.org/users/924890/articles/1304432-schrosim-a-schr%C3%B6dinger-inspired-scalable-quantum-photonic-circuit-simulator-for-hardware-agnostic-quantum-computing  
- Local copy (optional): `docs/SchroSIM_ConceptNote.pdf`

## Quickstart (documentation-first MVP)

SchroSIM is currently under active development. If you want to contribute now:

- Start here: **docs/architecture.md**
- Then: **docs/quickstart.md**
- Examples roadmap: **docs/examples.md**

## Roadmap

See ROADMAP.md for milestones and deliverables.

## Repository Structure