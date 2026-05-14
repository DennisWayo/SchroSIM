# Mathematical Proofs

This chapter states and proves the model-level identities that SchroSIM implements for its CV Gaussian core and related runtime logic.

## 1) Notation and Assumptions

We use units with `hbar = 1`.

For `n` modes, define the quadrature vector

`R = (q1, p1, q2, p2, ..., qn, pn)^T`.

The canonical commutation relation is

`[Ri, Rj] = i Omega_ij`,

where `Omega = direct_sum_k [[0, 1], [-1, 0]]`.

For a state `rho`, define:

1. mean vector `d = <R>`,
2. covariance matrix `V_ij = (1/2) <{Delta Ri, Delta Rj}>`, with `Delta R = R - d`.

This chapter proves identities under the same modeling assumptions used by SchroSIM’s Gaussian path:

1. affine symplectic gates for Gaussian unitaries,
2. Gaussian channel updates for loss and thermal loss,
3. linear-Gaussian conditioning formulas for homodyne and heterodyne,
4. explicit compatibility predicates for backend routing.

## 2) Affine Symplectic Evolution

### Theorem 2.1 (Mean and covariance update)

Assume a gate acts as:

`R' = S R + u`,

with real matrix `S` and real vector `u`. Then:

1. `d' = S d + u`,
2. `V' = S V S^T`.

### Proof

For the mean:

`d' = <R'> = <S R + u> = S <R> + u = S d + u`.

For covariance, note `Delta R' = R' - d' = S(R - d) = S Delta R`. Therefore

`V' = (1/2)<{Delta R', Delta R'^T}>`
`   = (1/2)<{S Delta R, (S Delta R)^T}>`
`   = S ( (1/2)<{Delta R, Delta R^T}> ) S^T`
`   = S V S^T`.

QED.

### Corollary 2.2 (Commutation preservation condition)

`[R'i, R'j] = i (S Omega S^T)_ij`.

Hence canonical commutation is preserved iff:

`S Omega S^T = Omega`.

This is exactly the symplectic condition checked by `isSymplectic(...)`.

### Corollary 2.3 (Physicality preservation under symplectic maps)

If a covariance matrix satisfies

`V + i Omega/2 >= 0`

and `S Omega S^T = Omega`, then `V' = S V S^T` also satisfies

`V' + i Omega/2 >= 0`.

### Proof

`V' + i Omega/2 = S V S^T + i Omega/2`
`               = S V S^T + i S Omega S^T / 2`
`               = S (V + i Omega/2) S^T`.

For any vector `x`, let `y = S^T x`. Then

`x^* (V' + i Omega/2) x = y^* (V + i Omega/2) y >= 0`,

since `V + i Omega/2 >= 0`.

QED.

## 3) Gaussian Channel Correctness

## 3.1 Pure loss channel

### Theorem 3.1

For one mode with transmissivity `eta in [0, 1]`, model

`R_out = sqrt(eta) R_in + sqrt(1-eta) R_env`,

with vacuum environment (`d_env = 0`, `V_env = I2/2`). Then:

1. `d_out = sqrt(eta) d_in`,
2. `V_out = eta V_in + (1-eta) I2/2`.

In `n`-mode embedding on mode `m`, this becomes:

`d' = K d`,
`V' = K V K^T + N`,

with `K` identity except the `m`-mode block scaled by `sqrt(eta)`, and `N` zero except diagonal entries `(q_m, p_m)` equal to `(1-eta)/2`.

### Proof

By linearity:

`d_out = <R_out> = sqrt(eta) <R_in> + sqrt(1-eta) <R_env> = sqrt(eta) d_in`.

For covariance, using independence of input and environment and zero cross-covariance:

`V_out = eta V_in + (1-eta) V_env = eta V_in + (1-eta) I2/2`.

Embedding into `n` modes yields the `K`/`N` form by block insertion.

QED.

## 3.2 Thermal loss channel

### Theorem 3.2

With thermal environment mean photon number `n_th >= 0`, environment covariance is

`V_env = ((2 n_th + 1)/2) I2`.

Then:

`d_out = sqrt(eta) d_in`,
`V_out = eta V_in + (1-eta) ((2 n_th + 1)/2) I2`.

In `n`-mode embedding:

`d' = K d`,
`V' = K V K^T + N`,

where injected diagonal noise at target mode is

`(1-eta)(2 n_th + 1)/2`.

### Proof

Same derivation as pure loss with thermal `V_env`.

QED.

### Theorem 3.3 (Gaussian-channel physicality condition for loss/thermal-loss)

For affine Gaussian channels `V' = K V K^T + N`, complete positivity is guaranteed by:

`N + i (Omega - K Omega K^T)/2 >= 0`.

For one-mode loss/thermal-loss blocks in SchroSIM:

`K = sqrt(eta) I2`,
`N = (1-eta) (2 n_th + 1) I2 / 2`,

with `n_th = 0` for pure loss.

### Proof

Compute:

`Omega - K Omega K^T = Omega - eta Omega = (1-eta) Omega`.

So CP condition becomes:

`N + i (1-eta) Omega / 2 >= 0`
`= (1-eta)/2 * ( (2 n_th + 1) I2 + i Omega )`.

When `eta in [0,1]`, prefactor `(1-eta)/2 >= 0`, so it is enough to show

`(2 n_th + 1) I2 + i Omega >= 0`.

The eigenvalues of `i Omega` are `+1` and `-1`, so eigenvalues of the matrix above are:

`(2 n_th + 1) +/- 1 = 2 n_th + 2` and `2 n_th`.

Both are nonnegative for `n_th >= 0`. Therefore the channel is CP.

QED.

## 4) Measurement Conditioning Correctness

All formulas below are standard linear-Gaussian conditioning identities and match the direct implementation used in SchroSIM.

## 4.1 Homodyne update

Define scalar measurement model:

`y = h^T R + nu`,

with measurement-noise variance `Var(nu) = v_meas` (`v_meas = 0` for ideal homodyne in the code path). Let prior be `R ~ N(d, V)`.

Define:

`mu = h^T d`,
`s2 = h^T V h + v_meas`,
`k = V h / s2`.

### Theorem 4.1

Conditioned on observed outcome `y`:

1. `d' = d + k (y - mu)`,
2. `V' = V - (V h h^T V) / s2`.

Equivalent code form:

`d' = d + (Vh) (y-mu)/s2`,
`V' = V - (Vh)(Vh)^T/s2`,

where `Vh = V h`.

### Proof

The joint Gaussian of `(R, y)` has mean `(d, mu)` and covariance:

`[[V, Vh], [h^T V, s2]]`.

Applying the Gaussian conditional formula gives exactly the above mean/covariance updates.

QED.

## 4.2 Heterodyne update

For one target mode, define:

`y = H R + nu`,

where `H` selects `(q_m, p_m)`, and `nu ~ N(0, Rm)` with

`Rm = (1/2) I2`

for quantum-limited heterodyne added vacuum noise.

Define innovation covariance:

`S = H V H^T + Rm`.

### Theorem 4.2

Conditioned on observed `y`:

1. `K = V H^T S^{-1}`,
2. `d' = d + K (y - H d)`,
3. `V' = V - K H V`.

### Proof

Again from multivariate Gaussian conditioning for linear observation model.

QED.

## 5) Backend Routing Correctness Conditions

Routing is a semantic selection problem over finite predicates.

Let:

1. `requiresFockPath(circuit)` be true iff circuit contains `inject_fock` or `inject_cat`,
2. `fockPathIssues(circuit)` enumerate compatibility violations (single-mode and supported-gate checks).

### Theorem 5.1 (Routing safety)

Given requested backend in `{gaussian, fock, auto, hybrid}`:

1. if request is `fock`, execution is permitted iff `fockPathIssues` is empty,
2. if request is `auto/hybrid` and `requiresFockPath` is false, choose Gaussian path,
3. if request is `auto/hybrid` and `requiresFockPath` is true, choose Fock path iff compatible; otherwise fail with explicit incompatibility.

### Proof sketch

This follows directly from exhaustive case analysis in `resolveExecutionBackend(...)` and `assertFockCompatible(...)`.

No silent unsafe downgrade exists for incompatible Fock-required circuits; failure is explicit.

QED (by case split over finite branch logic).

## 6) Fock Truncation and Exponential-Series Error

SchroSIM’s Fock displacement uses:

1. finite cutoff `d`,
2. finite Taylor terms `T` in matrix exponential.

Let truncated generator be `G_d` and truncated exponential approximation be

`E_T(G_d) = sum_{k=0}^T G_d^k / k!`.

For finite-dimensional operator norm:

`||exp(G_d) - E_T(G_d)|| <= exp(||G_d||) * ||G_d||^(T+1) / (T+1)!`.

Thus total modeling error has two parts:

1. **cutoff error** from replacing infinite-dimensional dynamics with finite `d`,
2. **series truncation error** bounded as above for fixed `d`.

This chapter treats that as a controlled approximation regime, not a model-exact identity claim.

## 7) GKP Nearest-Lattice Decode/Correction Semantics

For syndrome value `x`, lattice spacing `Delta > 0`, define:

`n = round(x / Delta)`,
`x_lattice = n Delta`,
`correction = -x_lattice`,
`residual = x - x_lattice`.

### Theorem 7.1

1. `residual` is exactly the signed distance from `x` to the nearest lattice point.
2. For nearest-integer rounding, `|residual| <= Delta/2` (tie behavior at exactly half-spacing depends on rounding convention).
3. Post-correction displacement by `correction` shifts syndrome by `-x_lattice`.

### Proof

By definition of nearest-integer rounding and lattice construction.

QED.

## 8) Implementation Correspondence Table

| Proven item | Implementation source |
|---|---|
| Affine symplectic update | `core-swift/Sources/SchroSIM/core/evolution/symplectic_evolution.swift` |
| Symplectic condition check | `core-swift/Sources/SchroSIM/core/evolution/symplectic_evolution.swift` |
| Loss and thermal-loss channel equations | `core-swift/Sources/SchroSIM/core/evolution/gaussian_channels.swift` |
| Homodyne/heterodyne conditioning | `core-swift/Sources/SchroSIM/core/operators/measurement.swift` |
| Fock displacement via matrix exponential | `core-swift/Sources/SchroSIM/backends/fock/fock_ops.swift` |
| Backend routing predicates | `core-swift/Sources/SchroSIM/src/core/backend_routing.swift` |
| GKP nearest-lattice decode semantics | `core-swift/Sources/SchroSIM/src/core/gkp_decoder.swift` |

## 9) Model-Exact Claim Boundary (Current)

Within this docs set, "model-exact" means exact with respect to the implemented Gaussian model equations and conditional-update rules, under the chosen parameterization and arithmetic behavior.

Approximation enters when:

1. non-Gaussian dynamics require finite Fock cutoff,
2. matrix exponentials are numerically truncated,
3. optional effective models are used for workflow practicality.

This aligns with the taxonomy in [10-theory-and-exactness-scope.md](10-theory-and-exactness-scope.md): model-exact Gaussian core plus controlled approximation regimes outside that boundary.
