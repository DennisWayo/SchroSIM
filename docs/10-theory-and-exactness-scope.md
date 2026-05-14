# Theory and Exactness Scope

This chapter defines what SchroSIM means by "exact" and where that claim stops.

## 1) Mathematical Conventions

SchroSIM’s CV Gaussian model uses:

1. quadrature ordering `R = (q1, p1, q2, p2, ...)`,
2. units `hbar = 1`,
3. Gaussian state parameterization by mean `d` and covariance `V`,
4. symplectic form `Omega = direct_sum_k [[0,1],[-1,0]]`.

Formal derivations are in [11-mathematical-proofs.md](11-mathematical-proofs.md).

## 2) Exactness Taxonomy in SchroSIM

### 2.1 Model-Exact (Gaussian Core)

Within the Gaussian model assumptions, updates are exact identities:

1. affine symplectic evolution:
   - `d' = S d + u`
   - `V' = S V S^T`
2. Gaussian channels (loss, thermal-loss) in closed form,
3. linear-Gaussian conditioning for homodyne and heterodyne updates.

This is the exactness regime referenced in the README for tractable workflows.

Terminology used across docs:

1. **model-exact**: exact with respect to the implemented Gaussian model equations,
2. **controlled approximation**: bounded/explicit approximation regimes (cutoff, truncation, routed non-Gaussian paths).

### 2.2 Deterministic Runtime Reproducibility

Given the same:

1. circuit payload,
2. seed,
3. backend selection and runtime configuration,
4. foundry profile/policy inputs,

SchroSIM targets deterministic replay at the result/trace level.

### 2.3 Approximation Regimes

Model-exactness does not imply exact infinite-dimensional quantum dynamics in every mode of operation. Controlled approximation enters when:

1. Fock simulations use finite cutoff dimension,
2. matrix exponential operators are series-truncated numerically,
3. effective/derived non-Gaussian handling paths are used for practical workflows,
4. backend routing selects an alternate compatible execution path.

## 3) Physicality and Validity Conditions

Core validity conditions include:

1. uncertainty compatibility:
   - `V + i Omega/2 >= 0`,
2. channel parameter domains:
   - `eta in [0,1]`, `n_th >= 0`,
3. IR parameter finiteness and mode-index validity,
4. foundry policy constraints (`max_modes`, squeezing limits, measurement/non-Gaussian allowances).

## 4) Claim Boundary

SchroSIM claims:

1. exact implementation of the stated Gaussian model equations,
2. explicit policy-aware execution and diagnostics,
3. deterministic, reproducible runtime behavior under fixed inputs/configuration.

SchroSIM does not claim:

1. exact simulation of arbitrary infinite-dimensional non-Gaussian dynamics without truncation,
2. hardware-faithful behavior without calibrated model assumptions,
3. approximation-free Fock evolution at finite cutoff.

## 5) Practical Interpretation for Users

Use this decision rule:

1. For Gaussian and tractable circuits: treat SchroSIM results as model-exact.
2. For Fock/non-Gaussian-heavy or very large circuits: treat results as controlled approximations and report cutoff/backend settings with outputs.
3. For pre-hardware studies: always bind runs to foundry profile/policy identifiers and seeds.

## 6) Cross-References

- Proofs: [11-mathematical-proofs.md](11-mathematical-proofs.md)
- Backends: [06-execution-backends.md](06-execution-backends.md)
- Compiler/foundry constraints: [05-compiler-and-foundry.md](05-compiler-and-foundry.md)
