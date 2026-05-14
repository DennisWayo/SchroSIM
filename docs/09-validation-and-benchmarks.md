# Validation and Benchmarks

## Validation Suite

Cross-runtime validation script:

```bash
bash scripts/cv-validation-suite.sh --runtime both
```

Coverage cases include:

- single-mode squeezing,
- two-mode EPR + loss,
- thermal + heterodyne,
- single-mode Fock response.

## Trace SLO Gate

```bash
bash scripts/trace-slo-check.sh --max-gates 512 --max-frame-ms 50
```

## Compute Benchmarking

Smoke benchmark:

```bash
bash scripts/compute-benchmark.sh --backend gaussian --modes 2 --layers 16 --iterations 2 --compute-backends auto,cpu,metal --max-p95-ms 500
```

Scaling benchmark:

```bash
bash scripts/compute-benchmark-scaling.sh ...
```

## Baseline Artifacts

- `benchmarks/schrosim-core-baseline.json`
- `benchmarks/schrosim-core-scaling-baseline.json`
- `benchmarks/compute-scaling-baseline.json`

## Benchmark Interpretation Guide

Use the benchmark scripts as gates, not just telemetry.

For `compute-benchmark.sh`:

- Primary latency gate is `--max-p95-ms` (if provided).
- Fail means the requested compute backend exceeded that p95 budget.

For `compute-benchmark-scaling.sh`:

- Baseline comparison is enabled with `--baseline <file>`.
- Baseline identity must match current run dimensions:
  - same simulation backend,
  - same compute backend list,
  - same modes list,
  - same layers list.
- Backend routing consistency is strict:
  - `compute_backend_candidate` must match baseline,
  - `compute_backend_used` must match baseline.

Latency regression envelope (current implementation):

- relative allowance: `max-regression-pct` (default `180`),
- absolute floors:
  - `p95`: baseline + `25 ms`,
  - `avg`: baseline + `15 ms`.

A row fails only when it exceeds the larger of:

1. baseline * (1 + `max-regression-pct`/100), or
2. baseline + absolute floor.

This avoids noisy failures for very small baselines while still catching large real regressions.

## Practical CI Usage

Recommended gate order:

1. `bash scripts/cv-validation-suite.sh --runtime both`
2. `bash scripts/trace-slo-check.sh --max-gates 512 --max-frame-ms 50`
3. `bash scripts/compute-benchmark.sh ... --max-p95-ms <budget>`
4. `bash scripts/compute-benchmark-scaling.sh --baseline benchmarks/compute-scaling-baseline.json --max-regression-pct 180`

If step 4 fails on routing mismatch, treat it as a policy/routing regression, not a raw latency fluctuation.
