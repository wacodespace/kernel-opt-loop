#!/usr/bin/env bash
# Step 01 — Baseline (or modified) runtime.
# Runs the benchmark once, captures stdout, greps the runtime number.
# Args: <run_name> [label]   label in {baseline,modified}, default baseline.
source "$(dirname "$0")/lib.sh"
kol_load_config
RUN="$(kol_init_run "${1:-}")"
LABEL="${2:-baseline}"

EXTRA_ENV=""
if [ "$LABEL" = "modified" ]; then
  # Force a fresh Triton cache so we measure the recompiled kernel, not a stale
  # .hsaco from the baseline run. This bit me before — keep it.
  EXTRA_ENV="TRITON_CACHE_DIR=/tmp/kol_triton_cache_modified"
fi

OUT="$RUN/runtime_$LABEL.txt"
kol_log "running $LABEL benchmark in $KOL_PROJECT_ROOT"
( cd "$KOL_PROJECT_ROOT" && eval "$(kol_bench_cmd "$EXTRA_ENV")" ) | tee "$OUT"

MS="$(grep -oE "$KOL_RUNTIME_RE" "$OUT" | tail -1 || true)"
echo "$MS" > "$RUN/runtime_${LABEL}_ms.txt"
[ -n "$MS" ] && kol_log "$LABEL runtime: $MS ms" || kol_warn "could not parse runtime (check benchmark.runtime_regex)"
