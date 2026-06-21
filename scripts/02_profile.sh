#!/usr/bin/env bash
# Step 02 — Profile + analyze with rocprof-compute.
# Args: <run_name> [label]   label in {baseline,modified}, default baseline.
# Produces:
#   workloads[_<label>]/      raw counters
#   rocprof_compute_<label>.txt   analyze report (the human/agent-readable one)
source "$(dirname "$0")/lib.sh"
kol_load_config
RUN="$(kol_init_run "${1:-}")"
LABEL="${2:-baseline}"

WL="$RUN/workloads"
EXTRA_ENV=""
if [ "$LABEL" = "modified" ]; then
  WL="$RUN/workloads_modified"
  EXTRA_ENV="TRITON_CACHE_DIR=/tmp/kol_triton_cache_modified"
fi
PROFILE_LOG="$RUN/rocprof_compute_profile_$LABEL.log"
ANALYZE_OUT="$RUN/rocprof_compute_$LABEL.txt"

kol_log "profiling ($LABEL) — this reruns the benchmark once per counter group (can be 10+ passes)"
( cd "$KOL_PROJECT_ROOT" && \
  "$KOL_ROCPROF" profile -n "$LABEL" -p "$WL" --no-roof -- \
    $(kol_bench_cmd "$EXTRA_ENV") ) > "$PROFILE_LOG" 2>&1 || \
    kol_warn "profile returned non-zero; inspect $PROFILE_LOG"

kol_log "analyzing -> $ANALYZE_OUT"
"$KOL_ROCPROF" analyze -p "$WL" > "$ANALYZE_OUT" 2>>"$PROFILE_LOG" || \
    kol_warn "analyze returned non-zero; inspect $PROFILE_LOG"

kol_log "$LABEL profile done. Agent: read $ANALYZE_OUT for VGPR/occupancy/MFMA/cache/wait counters."
