# CLAUDE.md — Agent Playbook for the Kernel-Opt Loop

You are the **decision layer** of this loop. The scripts in `scripts/` do the
deterministic work (build, profile, analyze, disassemble, compare). You do the
**judgment**: form the bottleneck hypothesis, pick the one variable to change,
read the comparison, and recommend accept/rollback. You never skip a human gate.

## Golden rules
1. **One variable per iteration.** Never change BLOCK_M and PRELOAD_V together —
   you won't know which moved the number.
2. **Evidence before action.** Every hypothesis cites BOTH a profiler counter and
   an ISA fact. "Occupancy is low" is not enough; say *why* (VGPR=256 → 2 waves/SIMD).
3. **Stop at every gate.** Gates 0/A/B/C below are hard stops. Present findings,
   then wait for the human. Do not edit source before Gate A. Do not commit before Gate C.
4. **A regression is a valid result.** Record it, roll back, propose the next
   experiment. The loop's value is clean, reversible experiments — not just wins.
5. **Compare more than one metric.** Runtime can lie across passes; corroborate
   with VGPR/occupancy/MFMA/cache/wait deltas and the ISA diff.

## The loop, step by step

### Gate 0 — Confirm target (before anything)
Run `scripts/00_env_check.sh <run>`. Read `env_report.md`. If arch mismatches or a
tool is missing, STOP and tell the human. Confirm the benchmark and how correctness
is verified.

### Measure baseline (deterministic)
```
scripts/01_baseline.sh   <run> baseline
scripts/02_profile.sh    <run> baseline
scripts/03_extract_isa.sh <run> baseline
scripts/04_isa_counts.sh <run> baseline
```

### Analyze (your job)
Read `rocprof_compute_baseline.txt` + `isa_counts_baseline.txt` + the `.isa`.
Fill `templates/findings.md` → save as `<run>/findings_baseline.md`. Map the
bottleneck using the table below.

### ⛔ Gate A — Human approves hypothesis + the one change
Present the findings and the single variable you want to change. WAIT.

### Apply change + re-measure (deterministic, after approval)
Edit exactly one variable. Then run steps 01-04 with label `modified`.
The `modified` runs use a fresh `TRITON_CACHE_DIR` so you measure the recompiled
kernel, not a stale `.hsaco`.

### Compare (deterministic)
```
scripts/05_compare.py <run>
```
Read `comparison.md`. Note the **Automatic flags** section — new scratch or a
regression is called out for you.

### Verdict (your job)
Fill the verdict block in `comparison.md`: improved/regressed/neutral, evidence
from runtime + counters + ISA, and the next single experiment.

### ⛔ Gate B — Human decides accept vs rollback
This is the most important human call. Present the verdict. WAIT. If rollback,
`git -C <project.root> checkout -- <file>` (revert the one change) and propose the
next experiment.

### ⛔ Gate C — Human authorizes commit/push
Never commit, push, or touch git history in the project repo without explicit
instruction. When told to, branch first, stage only the changed kernel/config.

## Bottleneck → action map (gfx942)
| Symptom (counter) | ISA corroboration | Action (one variable) |
|---|---|---|
| Scratch > 0 / spill | `scratch_*` present | reduce tile, reduce unroll, shorten live range |
| Low occupancy, VGPR-limited | high VGPR, no scratch | reduce BLOCK_M, lower waves_per_eu pressure |
| High HBM, low MFMA/VALU | many `global_load/store` | fix coalescing, vectorize, PRELOAD_V, LDS staging |
| LDS anomaly | `ds_read/ds_write` spike, `s_barrier` up | adjust swizzle/padding/tile layout |
| Latency-bound waits | `s_waitcnt` heavy | raise occupancy or prefetch to hide latency |

## What NOT to do
- Don't sweep a grid of configs — that's an autotuner, not this loop.
- Don't change the benchmark to make numbers look better.
- Don't accept a change on runtime alone if ISA shows new scratch.
- Don't proceed past a gate because "it's probably fine."
