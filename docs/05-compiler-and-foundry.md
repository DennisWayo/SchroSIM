# Compiler and Foundry Layer

## Foundry Compilation Model

Foundry compilation applies governance and hardware-like constraints before execution.

Core operations:

1. Validate circuit against foundry policy.
2. Optionally inject calibrated/static mode-loss gates.
3. Emit compiled circuit for backend execution.

Reference implementation:

- `core-swift/Sources/SchroSIM/src/compiler/foundry/foundry_spec.swift`

## Key Foundry Constraints

- `max_modes`
- `max_squeezing_r`
- `allow_non_gaussian`
- `allow_measurements`
- `mode_loss_eta`
- `inject_mode_loss`

## Registry and Signature Flow

Registry-backed production profiles:

- `config/foundry_registry.json`
- `foundry-admin add-draft`
- `foundry-admin promote` (approval/signing)

Runtime profile verification includes:

- status checks (approved only),
- validity window checks,
- HMAC signature verification.

## Public Governance Inputs

- registry file path override: `--foundry-registry`
- signing key: `--foundry-key` or env var

## Profile Lifecycle (Public CLI Flow)

The runtime/registry lifecycle implemented by `schrosim-cli` is:

1. Draft creation (`foundry-admin add-draft`).
2. Approval and signing (`foundry-admin promote --to approved`).
3. Runtime consumption (`run|trace --prod` with `foundry_profile`).
4. Deprecation (`foundry-admin promote --to deprecated`) when superseded.

State transition rules are strict:

- `draft -> approved`
- `approved -> deprecated`

Any other transition is rejected as invalid.

Minimal example:

```bash
schrosim-cli foundry-admin add-draft \
  --profile-id public-default \
  --version 1 \
  --spec <foundry-spec.json> \
  --approver platform-admin

schrosim-cli foundry-admin promote \
  --profile-id public-default \
  --version 1 \
  --to approved \
  --approver platform-admin \
  --key "$SCHROSIM_FOUNDRY_HMAC_KEY"
```

Minimal `<foundry-spec.json>` shape:

```json
{
  "name": "public-default-v1",
  "max_modes": 64,
  "max_squeezing_r": 1.2,
  "allow_non_gaussian": true,
  "allow_measurements": true,
  "inject_mode_loss": true,
  "mode_loss_eta": [0.995]
}
```

## Validation and Failure Matrix

SchroSIM currently emits typed error classes rather than numeric failure codes. The table below maps the stable classes surfaced by the compiler and runtime.

| Error class | Trigger | Typical message shape | Surface |
|---|---|---|---|
| `FoundryValidationError.invalidMaxModes` | `max_modes <= 0` | `Foundry maxModes must be > 0` | compile/validate |
| `FoundryValidationError.modeCountExceedsLimit` | `circuit.modes > max_modes` | `Circuit modes ... exceed foundry limit ...` | compile/validate |
| `FoundryValidationError.invalidSqueezingLimit` | non-finite or negative `max_squeezing_r` | `maxSqueezingR must be finite and >= 0` | compile/validate |
| `FoundryValidationError.squeezingLimitExceeded` | `abs(r) > max_squeezing_r` | `Squeezing on mode ... exceeds foundry maxSqueezingR ...` | compile/validate |
| `FoundryValidationError.modeLossLengthMismatch` | `mode_loss_eta.count != modes` | `modeLossEta must have ... values` | compile/validate |
| `FoundryValidationError.invalidModeLoss` | non-finite or out-of-range loss eta | `modeLossEta[i] must be finite in [0,1]` | compile/validate |
| `FoundryValidationError.nonGaussianDisallowed` | non-Gaussian injection while disabled | `Foundry disallows non-Gaussian injection` | compile/validate |
| `FoundryValidationError.measurementsDisallowed` | measurement/feed-forward while disabled | `Foundry disallows measurement gates` | compile/validate |
| `FoundryValidationError.unsupportedPlaceholderGate` | placeholder gate reaches compile | `Foundry rejects placeholder gate` | compile/validate |
| `CLIInputError.invalidField` | invalid `--prod`/foundry field combinations | `Inline 'foundry' block is not allowed in --prod mode` | CLI argument/input parse |
| `FoundryRegistryError.nonApprovedProfile` | profile exists but not approved | `... is not approved (status=...)` | registry resolution |
| `FoundryRegistryError.unsignedProfile` | approved profile without signature | `... is missing a signature` | registry resolution |
| `FoundryRegistryError.invalidSignature` | HMAC mismatch for approved profile | `signature verification failed` | registry resolution |
| `FoundryRegistryError.expiredProfile` | outside `valid_from/valid_to` window | `... is expired/not-yet-valid` | registry resolution |

Practical rule: treat these class names as the stable automation interface, and treat the message body as human diagnostics.
