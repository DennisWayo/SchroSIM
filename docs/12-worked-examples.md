# Worked Examples

## Example 1: Runtime Default Foundry

- Input: `examples/runtime_default_foundry.json`
- Goal: minimal end-to-end run path.

## Example 2: Fock Injection Smoke

- Input: `examples/fock_injection_smoke.json`
- Goal: demonstrate backend routing to Fock-compatible execution.

## Example 3: Foundry Loss Map

- Input: `examples/foundry_loss_map.json`
- Goal: foundry validation and injected mode-loss behavior.

## Example 4: GKP QEC Memory MVP

- Input: `examples/cv/qec_single_logical_gkp_memory_mvp.json`
- Goal: measurement-driven decode/correction loop and QEC metrics.

## Example Playbook (Command + Expected Result)

### 1) Runtime Default Foundry

Command:

```bash
swift run schrosim-cli run examples/runtime_default_foundry.json
```

Expected backend resolution:

- `backend_requested = "auto"`
- `backend = "gaussian"`

Key output fields:

- `status`, `backend`, `backend_requested`
- `gate_count`, `source_gate_count`, `foundry_injected_gate_count`
- `mean_photon_number`, `measurement_count`
- `final_state.representation`

Interpretation:

- This is the cleanest sanity check for parse -> compile -> execute.
- `foundry_injected_gate_count` should remain `0` for this input.

### 2) Fock Injection Smoke

Command:

```bash
swift run schrosim-cli run examples/fock_injection_smoke.json
```

Expected backend resolution:

- `backend_requested = "auto"`
- `backend = "fock"` (non-Gaussian Fock injection routing)

Key output fields:

- `backend`, `compute_backend_used`
- `cutoff`, `final_state.representation`
- `final_state.top_probabilities`

Interpretation:

- Confirms backend router can switch from auto to Fock path.
- Useful for catching regressions in non-Gaussian routing behavior.

### 3) Foundry Loss Map

Command:

```bash
swift run schrosim-cli run examples/foundry_loss_map.json
```

Expected backend resolution:

- `backend_requested = "auto"`
- `backend = "gaussian"`

Key output fields:

- `foundry`, `foundry_source`
- `source_gate_count`, `gate_count`, `foundry_injected_gate_count`
- `loss_eta`, `mean_photon_number`

Interpretation:

- `foundry_injected_gate_count > 0` indicates injected static mode-loss.
- `gate_count - source_gate_count` should match injected loss operations.

### 4) GKP QEC Memory MVP

Command:

```bash
swift run schrosim-cli run examples/cv/qec_single_logical_gkp_memory_mvp.json
```

Expected backend resolution:

- `backend_requested = "gaussian"`
- `backend = "gaussian"`

Key output fields:

- `measurement_count`
- `qec.rounds_executed`, `qec.logical_error_rate`
- `qec.suppression_factor`, `qec.break_even_gain`

Interpretation:

- Presence of `qec` confirms decode/correction rounds were recognized.
- Track `logical_error_rate` and `break_even_gain` across commits for QEC-quality drift.
