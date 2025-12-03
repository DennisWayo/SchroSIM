
  <!-- Core tech badges -->
  <a href="https://github.com/DennisWayo/SchroSIM">
    <img src="https://img.shields.io/badge/language-Swift-F05138?logo=swift&logoColor=white" alt="Language: Swift">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM">
    <img src="https://img.shields.io/badge/framework-SwiftUI-0066CC?logo=apple&logoColor=white" alt="Framework: SwiftUI">
  </a>
  <a href="https://developer.apple.com/metal/">
    <img src="https://img.shields.io/badge/acceleration-Metal-1F1F1F?logo=apple&logoColor=white" alt="Acceleration: Metal">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM">
    <img src="https://img.shields.io/badge/platform-macOS_Apple_Silicon-000000?logo=apple&logoColor=white" alt="Platform: macOS Apple Silicon">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/releases">
    <img src="https://img.shields.io/badge/version-v0.1-orange" alt="Version: v0.1">
  </a>





  <!-- Activity / community badges -->
  <a href="https://github.com/DennisWayo/SchroSIM/stargazers">
    <img src="https://img.shields.io/github/stars/DennisWayo/SchroSIM?style=social" alt="GitHub Stars">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/network/members">
    <img src="https://img.shields.io/github/forks/DennisWayo/SchroSIM?style=social" alt="GitHub Forks">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/issues">
    <img src="https://img.shields.io/github/issues/DennisWayo/SchroSIM?color=informational" alt="Open Issues">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/pulls">
    <img src="https://img.shields.io/github/issues-pr/DennisWayo/SchroSIM?color=yellow" alt="Open PRs">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/releases">
    <img src="https://img.shields.io/github/downloads/DennisWayo/SchroSIM/total?logo=github" alt="Total Downloads">
  </a>
  <a href="https://github.com/DennisWayo/SchroSIM/commits/main">
    <img src="https://img.shields.io/github/last-commit/DennisWayo/SchroSIM?color=brightgreen" alt="Last commit">
  </a>


# SchroSIM

**SchroSIM** is a Schrödinger-inspired, scalable, and hardware-agnostic simulator for quantum photonic circuits. Built in Swift and optimized for Apple’s Metal framework, SchroSIM supports both continuous-variable (CV) and non-Gaussian quantum operations, offering a modular architecture suitable for education, research, and photonic hardware prototyping.


### Project Highlights

- **Language**: Swift + SwiftUI + Metal
- **Simulator Types**: Gaussian (symplectic formalism) and Non-Gaussian (Fock/tensor-based)
- **Platform Support**: macOS (M1/M2), future WebGPU-ready
- **GUI**: Drag-and-drop photonic circuit builder
- **Compiler**: Intermediate Representation (IR) for hardware-agnostic mapping
- **Backends**: CPU/GPU/QPU accelerated simulation



### Concept Note
This repository accompanies the technical concept note:

**Dennis Wayo**,

"SchroSIM: A Schrödinger-Inspired Scalable Quantum Photonic Circuit Simulator for Hardware-Agnostic Quantum Computing,"

 [TechRxiv Link]([https://arxiv.org/abs/2025.xxxxx](https://www.techrxiv.org/users/924890/articles/1304432-schrosim-a-schr%C3%B6dinger-inspired-scalable-quantum-photonic-circuit-simulator-for-hardware-agnostic-quantum-computing))  
 [PDF Download](docs/SchroSIM_ConceptNote.pdf)

---

### Project Structure (WIP)

```bash
schrosim/
├── docs/              # Technical documentation and preprints
├── src/               # Swift source files
│   ├── simulator/     # Simulation engine (CV, Fock, tensor)
│   ├── compiler/      # IR and circuit parsing
│   └── ui/            # SwiftUI GUI modules
├── examples/          # Test circuits and use-cases
├── tests/             # Benchmarking and unit tests
├── LICENSE
├── README.md
└── CONTRIBUTING.md
```


### Roadmap

| Version | Features |
|---------|----------|
| **v0.1** | SwiftUI GUI, basic CV gates, IR compiler stub |
| **v0.2** | Full CV + non-Gaussian backend, Metal acceleration |
| **v0.3** | HAL, benchmarking tasks (GBS, cluster states) |
| **v1.0** | Release candidate, reproducibility scripts, documentation |


### Contributing
We welcome contributors from the quantum, photonic, and Swift communities. To get started:

1. Fork the repository
2. Create a new branch: `git checkout -b feature-name`
3. Submit a pull request with a clear description

See [CONTRIBUTING.md](CONTRIBUTING.md) for style guides and module naming conventions.


###  Contact
**Dennis Wayo**  
Quantum Computing Researcher and Software Developer, SchroSIM Project  
🔗 [GitHub](https://github.com/DennisWayo/SchroSIM)


###  License
MIT License. See [LICENSE](LICENSE) for details.

---

> This repository serves as the implementation base for the SchroSIM technical concept note and will track its open-source development from concept to release.

### Funders
This project will acknowledge support from funding organizations upon award.  
A dedicated section will be updated here to credit any sponsors who contribute to SchroSIM.
