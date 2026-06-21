#!/usr/bin/env python3
"""Step 05 — Compare baseline vs modified into comparison.md.

Reads the run directory artifacts produced by steps 01-04 for both labels and
emits a markdown table of deltas plus an ISA diff. It does NOT decide the
verdict — that is the agent's job (and the human's at Gate B). It only lays out
the evidence so the judgment is grounded in numbers.

Usage: 05_compare.py <run_dir>
"""
import re
import sys
import pathlib

RUN = pathlib.Path(sys.argv[1])


def read(p, default=""):
    f = RUN / p
    return f.read_text() if f.exists() else default


def runtime_ms(label):
    txt = read(f"runtime_{label}_ms.txt").strip()
    try:
        return float(txt)
    except ValueError:
        return None


def isa_counts(label):
    """Parse 'key: int' lines from isa_counts_<label>.txt."""
    out = {}
    for line in read(f"isa_counts_{label}.txt").splitlines():
        m = re.match(r"\s*(\w+):\s+(\d+)\s*$", line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def pct(base, mod):
    if base is None or mod is None or base == 0:
        return "N/A"
    return f"{(mod - base) / base * 100:+.1f}%"


def main():
    rt_b, rt_m = runtime_ms("baseline"), runtime_ms("modified")
    isa_b, isa_m = isa_counts("baseline"), isa_counts("modified")

    lines = ["# Profiling Comparison", ""]
    lines += ["## Runtime", "",
              "| Metric | Baseline | Modified | Change |",
              "|---|---:|---:|---:|",
              f"| End-to-end (ms) | {rt_b} | {rt_m} | {pct(rt_b, rt_m)} |", ""]

    lines += ["## ISA instruction counts", "",
              "| Pattern | Baseline | Modified | Change |",
              "|---|---:|---:|---:|"]
    for k in sorted(set(isa_b) | set(isa_m)):
        b, m = isa_b.get(k), isa_m.get(k)
        lines.append(f"| {k} | {b} | {m} | {pct(b, m)} |")
    lines.append("")

    # Hard flags the human must not miss.
    flags = []
    if isa_m.get("scratch", 0) > isa_b.get("scratch", 0):
        flags.append("**NEW SCRATCH (register spill) introduced — usually reject.**")
    if rt_b and rt_m and rt_m > rt_b:
        flags.append(f"Runtime regressed by {pct(rt_b, rt_m)}.")
    elif rt_b and rt_m and rt_m < rt_b:
        flags.append(f"Runtime improved by {pct(rt_b, rt_m)}.")

    lines += ["## Automatic flags", ""]
    lines += [f"- {f}" for f in flags] or ["- none"]
    lines += ["",
              "## Verdict (agent fills, human confirms at Gate B)", "",
              "- Result: improved / regressed / neutral —",
              "- Main evidence —",
              "- ISA evidence —",
              "- Decision: ACCEPT (commit) / ROLLBACK —",
              "- Next experiment (one variable) —", ""]

    out = RUN / "comparison.md"
    out.write_text("\n".join(lines))
    print(f"[kol] comparison -> {out}")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
