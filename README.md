# SchroSIM

**SchroSIM** is a Schrödinger-inspired, scalable, and hardware-agnostic simulator for quantum photonic circuits. Built in Swift and optimized for Apple’s Metal framework, SchroSIM supports both continuous-variable (CV) and non-Gaussian quantum operations, offering a modular architecture suitable for education, research, and photonic hardware prototyping.


### Project Highlights

- **Language**: Swift + SwiftUI + Metal
- **Simulator Types**: Gaussian (symplectic formalism) and Non-Gaussian (Fock/tensor-based)
- **Platform Support**: macOS (M1/M2), future WebGPU-ready
- **GUI**: Drag-and-drop photonic circuit builder
- **Compiler**: Intermediate Representation (IR) for hardware-agnostic mapping
- **Backends**: CPU and GPU accelerated simulation



### Concept Note
This repository accompanies the technical concept note:

**Dennis Wayo**, "SchroSIM: A Schrödinger-Inspired Scalable Quantum Photonic Circuit Simulator for Hardware-Agnostic Quantum Computing," arXiv:2025.xxxxx

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
