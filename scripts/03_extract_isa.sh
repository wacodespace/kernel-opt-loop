#!/usr/bin/env bash
# Step 03 — Extract ISA from the compiled Triton kernel.
# Locates the most recently written .hsaco in the triton cache whose sibling
# metadata matches the kernel name, disassembles it with llvm-objdump.
# Args: <run_name> [label]
source "$(dirname "$0")/lib.sh"
kol_load_config
RUN="$(kol_init_run "${1:-}")"
LABEL="${2:-baseline}"

CACHE="$KOL_TRITON_CACHE"
if [ "$LABEL" = "modified" ]; then
  CACHE="/tmp/kol_triton_cache_modified"
fi
[ -d "$CACHE" ] || kol_die "triton cache not found: $CACHE (run the benchmark first)"

# Find candidate .hsaco files for the kernel, newest first.
HSACO="$(find "$CACHE" -name "*.hsaco" -printf '%T@ %p\n' 2>/dev/null \
         | sort -rn | awk '{print $2}' \
         | while read -r f; do
             d="$(dirname "$f")"
             if ls "$d" 2>/dev/null | grep -q "$KOL_KERNEL_MATCH"; then echo "$f"; fi
           done | head -1)"
# Fallback: just the newest .hsaco if name match found nothing.
[ -n "$HSACO" ] || HSACO="$(find "$CACHE" -name "*.hsaco" -printf '%T@ %p\n' | sort -rn | awk 'NR==1{print $2}')"
[ -n "$HSACO" ] || kol_die "no .hsaco found under $CACHE"

echo "$(dirname "$HSACO")" > "$RUN/triton_cache_dir_$LABEL.txt"
ISA="$RUN/${KOL_KERNEL_MATCH}.$LABEL.isa"
kol_log "disassembling $HSACO"
"$KOL_OBJDUMP" -d --mcpu="$KOL_ARCH" "$HSACO" > "$ISA" 2>/dev/null
cp "$HSACO" "$RUN/${KOL_KERNEL_MATCH}.$LABEL.hsaco"
kol_log "$LABEL ISA -> $ISA ($(wc -l < "$ISA") lines)"
