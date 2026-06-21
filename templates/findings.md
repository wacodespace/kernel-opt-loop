# Baseline Findings

> Filled by the agent after reading `rocprof_compute_baseline.txt`,
> `isa_counts_baseline.txt`, and `<kernel>.baseline.isa`.
> One hypothesis, one variable to change. This is what the human approves at Gate A.

## Target
- GPU / arch:
- Benchmark:
- Runtime baseline (ms):

## Hotspot
- Top kernel:
- rocprof-compute top-kernel share / mean duration:

## Key Counters
- Registers: Arch VGPR / Accum VGPR / SGPR:
- LDS per workgroup / scratch per workitem:
- Occupancy (waves, %):
- Instruction mix: VALU / MFMA / LDS / VMEM:
- Waits: SQ_WAIT_ANY / SQ_WAIT_INST_ANY:
- Cache: TCC read/write, TCP read/write:

## Bottleneck Hypothesis
- What is limiting the kernel (register-limited / LDS-limited / memory-latency / occupancy):
- Evidence from counters AND ISA:

## Proposed Experiment (ONE variable)
- Change:
- Why it should help the bottleneck above:
- Risk (what could regress):
