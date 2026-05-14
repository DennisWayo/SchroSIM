# Enterprise Boundary

This folder is the local boundary for enterprise-only materials.

Contents here are intentionally excluded from the public repository by `.gitignore`.

Public SchroSIM scope remains:
- CLI/runtime core
- open examples/config/docs needed for public workflows

Enterprise GUI and sensitive/internal enterprise assets should stay under this folder until the private repository is established and wired as a private dependency.

If local enterprise UI sources are present at `enterprise/core-swift/Sources/schrosim-enterprise-ui`, the root package exposes:

`swift run schrosim-enterprise-ui`
