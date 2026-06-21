# kernel-opt-loop

An **agent-in-the-loop** workflow for iteratively optimizing GPU kernels on AMD
Instinct (gfx942 / MI300-class) hardware. It turns the manual
"profile → read counters → disassemble → change one thing → re-measure" grind
into a repeatable loop where:

- **deterministic scripts** do the mechanical work (benchmark, `rocprof-compute`
  profile/analyze, ISA disassembly, before/after comparison), and
- **an agent** (Claude Code) does the judgment (form the bottleneck hypothesis,
  pick the single variable to change, read the comparison, recommend accept/rollback),
- with a **human** holding the wheel at four explicit gates.

It is the AMD equivalent of an NVIDIA Nsight Compute optimization loop:
`rocprof-compute` ≈ NCU, `llvm-objdump` ISA ≈ SASS, MFMA ≈ tensor cores,
LDS ≈ shared memory, scratch ≈ local/spill.

## Why a loop, and why a human in it

Kernel tuning is a search through a space where **every step is cheap to measure
but expensive to judge**. The mechanical parts are perfectly automatable. The
judgment parts — *what is actually limiting this kernel? is this regression worth
the register savings? do I trust this number?* — are where experience lives, and
where a wrong autonomous decision quietly wastes hours.

So this repo splits the two and inserts the human exactly where a wrong call is
costly or irreversible.

```
                ┌─────────────────────── one iteration ───────────────────────┐
   ⛔ Gate 0    │  scripts          agent              scripts        agent     │
  confirm target│  ─────────        ─────              ───────        ─────     │
        │       │  baseline ─► profile/analyze ─► extract ISA                   │
        ▼       │       │            │                  │                       │
  [scripts run] │       └────────────┴──────────────────┘                      │
        │       │                    ▼                                          │
        │       │            AGENT: findings.md                                 │
        │       │            (hotspot + ONE hypothesis)                         │
        ▼       │                    │                                          │
   ⛔ Gate A ───┼──────────  human approves hypothesis + the one change         │
  approve change│                    ▼                                          │
        │       │            AGENT edits ONE variable                          │
        ▼       │                    │                                          │
  [scripts run] │       modified: baseline/profile/isa ─► compare.py            │
        │       │                    ▼                                          │
        │       │            AGENT: verdict (improved/regressed + evidence)     │
        ▼       │                    │                                          │
   ⛔ Gate B ───┼──────────  human decides ACCEPT or ROLLBACK ◄── most important │
  accept/rollbk │                    │                                          │
        └───────┼────────────────────┘  (loop again with next experiment)      │
                └──────────────────────────────────────────────────────────────┘
   ⛔ Gate C  ── human authorizes commit / push (never automatic)
```

## The four human-in-the-loop gates

The whole point of the design is *where* the human is required. These are hard
stops; the agent presents evidence and waits.

| Gate | When | What the human decides | Why it can't be automated |
|---|---|---|---|
| **0 — Target** | before any run | right GPU, right benchmark, how correctness is verified | a wrong target invalidates every number that follows |
| **A — Hypothesis** | after baseline analysis, before editing | is the bottleneck diagnosis right, and is *this one variable* the thing to change | stops the agent from rewriting half the kernel on a hunch |
| **B — Accept/Rollback** | after the comparison | keep the change or revert it; whether to iterate again | the core judgment call — a faster runtime with new register spill is often a *worse* kernel |
| **C — Commit/Push** | when a win is real | land it in the project repo | outward-facing and irreversible; never done on the agent's own initiative |

Gate B is the one that matters most, and the worked example below shows exactly
why: the obvious change made things **33% slower**, and only a human (reading the
agent's evidence) should decide to throw it away.

## Worked example — a real *failed* experiment

This is not hypothetical. It is the first iteration we actually ran, kept here
because a loop that can't cleanly record and reverse a bad idea is useless.

**Target:** MI308X (gfx942, 80 CU), Triton FlashAttention forward,
`b=1 hq=32 hk=32 sq=1024 sk=1024 d=128 causal bf16`. Baseline **0.2010 ms**.

**Gate 0:** confirmed — rocprof reports gfx942/MI308X, `rocprof-compute` 3.4.0
and `llvm-objdump` present.

**Baseline analysis (agent):** the `_attn_fwd` kernel is 68% of GPU time. Arch
VGPR 128 + Accum VGPR 128 = **256 VGPR/lane → only ~2 waves/SIMD**, occupancy
**5.64%**. No scratch. Heavy `s_waitcnt` / `SQ_WAIT` cycles → latency-bound from
too few waves to hide it.

**Hypothesis (→ Gate A):** *register-limited occupancy.* Change **one** variable:
`BLOCK_M` 128 → 64, to shrink the tile and free registers for more resident waves.
Human approved testing it.

**Result (compare.py → Gate B):**

| Metric | Baseline | Modified (BLOCK_M=64) | Change |
|---|---:|---:|---:|
| End-to-end | 0.2010 ms | 0.2684 ms | **+33.6%** |
| Hotspot kernel time | 189777 ns | 256882 ns | +35.4% |
| Arch VGPR | 128 | 108 | −15.6% |
| SQ waves | 1024 | 2048 | +100% |
| MFMA instrs | 589824 | 835584 | +41.7% |
| LDS instrs | 515584 | 1841664 | **+257%** |
| ISA scratch | 0 | 0 | none |

**Verdict (agent):** *regressed.* The hypothesis was half-right — occupancy
doubled (waves 1024→2048, VGPR dropped) — but the smaller tile **exploded LDS
traffic (+257%) and MFMA count**, and the extra tiling overhead dwarfed the
occupancy gain. More waves did not help because the kernel became more
work-bound, not latency-bound.

**Gate B decision (human):** **ROLLBACK.** Revert the config. Next single
experiment: keep `BLOCK_M=128`, try `PRELOAD_V=true` — attack the memory/cache
pressure directly without touching register pressure or tile size.

The lesson the loop is built around: *the intuitive fix regressed, the numbers
said so across several metrics, and the structure made reverting trivial.* That
is the human gate earning its place.

## Layout

```
README.md                     this file — for humans
CLAUDE.md                     playbook the agent follows (the gates, the bottleneck map)
config/target.example.yaml    copy to target.yaml; defines GPU, paths, benchmark, ISA patterns, thresholds
scripts/
  lib.sh                      config reader + shared helpers (no external deps beyond pyyaml)
  00_env_check.sh   Gate 0    confirm toolchain + arch, write env_report.md
  01_baseline.sh              run benchmark, capture runtime         (label: baseline|modified)
  02_profile.sh               rocprof-compute profile + analyze       (label: baseline|modified)
  03_extract_isa.sh           find .hsaco in triton cache, llvm-objdump it
  04_isa_counts.sh            grep ISA for the bottleneck fingerprint
  05_compare.py               baseline vs modified → comparison.md + automatic flags
templates/findings.md         hypothesis template the agent fills
experiments/<timestamp>/      all artifacts for one run (gitignored by default)
```

The scripts are deterministic and idempotent — you can run any step by hand. The
agent just calls them in order and does the reading/judging in between.

## Quick start

```bash
# 1. point it at your code and benchmark
cp config/target.example.yaml config/target.yaml
$EDITOR config/target.yaml          # project.root, benchmark.cmd, kernel.name_match ...

# 2. Gate 0
scripts/00_env_check.sh run01

# 3. baseline (deterministic)
for s in 01_baseline 02_profile 03_extract_isa 04_isa_counts; do
  scripts/$s.sh run01 baseline; done

# 4. hand the artifacts to the agent: "read experiments/run01, follow CLAUDE.md"
#    → agent writes findings, stops at Gate A.

# 5. after you approve a change + the agent applies it:
for s in 01_baseline 02_profile 03_extract_isa 04_isa_counts; do
  scripts/$s.sh run01 modified; done
scripts/05_compare.py run01
#    → agent writes verdict, stops at Gate B (accept/rollback).
```

## Requirements
- ROCm with `rocprof-compute` (Rocprofiler-Compute ≥ 3.4) and `llvm-objdump`.
- `rocprof-compute`'s own Python deps (dash, plotext, astunparse, …) installed in
  the active environment, or `analyze` will error — see its `requirements.txt`.
- `python3` with `pyyaml` for the config reader and `05_compare.py`.
- A benchmark that (a) prints a parseable runtime and (b) triggers compilation of
  the kernel you're studying.

## Scope
Deliberately narrow: **AMD gfx942 kernel tuning, one variable per iteration.**
Not an autotuner (no grid sweep), not a generic profiler frontend, not autonomous
(the gates are the point). Adapting to another arch is mostly editing
`config/target.yaml` — `gpu.arch`, the `isa_patterns`, and the bottleneck map in
`CLAUDE.md`.


