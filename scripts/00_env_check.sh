#!/usr/bin/env bash
# Step 00 — Environment check (HITL Gate 0).
# Confirms the toolchain exists and the GPU matches config BEFORE any run.
# Does NOT modify anything. Writes env_report.md into the run dir.
source "$(dirname "$0")/lib.sh"
kol_load_config
RUN="$(kol_init_run "${1:-}")"
REPORT="$RUN/env_report.md"

ok=1
resolve() { command -v "$1" 2>/dev/null || ([ -x "$1" ] && echo "$1") || echo ""; }

HIPCC_P="$(resolve "$KOL_HIPCC")"
ROCPROF_P="$(resolve "$KOL_ROCPROF")"
OBJDUMP_P="$(resolve "$KOL_OBJDUMP")"
ROCMINFO_P="$(resolve "$KOL_ROCMINFO")"

DETECTED_ARCH="$("$ROCMINFO_P" 2>/dev/null | grep -oE 'gfx[0-9a-f]+' | head -1)"
[ -n "$DETECTED_ARCH" ] || DETECTED_ARCH="unknown"

{
  echo "# Environment Report"
  echo
  echo "- Config: \`$KOL_CONFIG\`"
  echo "- Project root: \`$KOL_PROJECT_ROOT\`"
  echo "- Expected arch: \`$KOL_ARCH\` ($KOL_PRODUCT)"
  echo "- Detected arch (rocminfo): \`$DETECTED_ARCH\`"
  echo "- HIP_VISIBLE_DEVICES: \`$KOL_DEVICE\`"
  echo
  echo "## Toolchain"
  echo "| tool | resolved | found |"
  echo "|---|---|---|"
  echo "| hipcc | \`${HIPCC_P:-MISSING}\` | $([ -n "$HIPCC_P" ] && echo yes || echo no) |"
  echo "| rocprof-compute | \`${ROCPROF_P:-MISSING}\` | $([ -n "$ROCPROF_P" ] && echo yes || echo no) |"
  echo "| llvm-objdump | \`${OBJDUMP_P:-MISSING}\` | $([ -n "$OBJDUMP_P" ] && echo yes || echo no) |"
  echo "| rocminfo | \`${ROCMINFO_P:-MISSING}\` | $([ -n "$ROCMINFO_P" ] && echo yes || echo no) |"
  echo
  echo "## Benchmark command"
  echo '```'
  kol_bench_cmd
  echo '```'
} > "$REPORT"

[ -n "$ROCPROF_P" ] || { kol_warn "rocprof-compute not found"; ok=0; }
[ -n "$OBJDUMP_P" ] || { kol_warn "llvm-objdump not found ($KOL_OBJDUMP)"; ok=0; }
if [ "$DETECTED_ARCH" != "unknown" ] && [ "$DETECTED_ARCH" != "$KOL_ARCH" ]; then
  kol_warn "arch mismatch: config=$KOL_ARCH detected=$DETECTED_ARCH"; ok=0
fi

kol_log "env report -> $REPORT"
if [ "$ok" -eq 1 ]; then
  kol_log "GATE 0 PASS — environment matches config."
else
  kol_warn "GATE 0 ATTENTION — review $REPORT before proceeding. STOP and ask the human."
fi
