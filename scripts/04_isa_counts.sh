#!/usr/bin/env bash
# Step 04 — Count ISA instruction patterns (the bottleneck fingerprint).
# Greps the disassembly for each pattern in config.isa_patterns.
# Args: <run_name> [label]
source "$(dirname "$0")/lib.sh"
kol_load_config
RUN="$(kol_init_run "${1:-}")"
LABEL="${2:-baseline}"

ISA="$RUN/${KOL_KERNEL_MATCH}.$LABEL.isa"
[ -f "$ISA" ] || kol_die "ISA not found: $ISA (run 03_extract_isa.sh first)"
OUT="$RUN/isa_counts_$LABEL.txt"

# Pull pattern labels+regexes out of the YAML.
mapfile -t PAIRS < <(python3 - "$KOL_CONFIG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for k, v in (d.get("isa_patterns") or {}).items():
    print(f"{k}\t{v}")
PY
)

: > "$OUT"
echo "$LABEL" >> "$OUT"
for pair in "${PAIRS[@]}"; do
  label="${pair%%$'\t'*}"; rx="${pair#*$'\t'}"
  n="$(grep -cE "$rx" "$ISA" || true)"
  printf '  %s: %s\n' "$label" "$n" >> "$OUT"
done
echo "  instruction_lines: $(grep -cE '^\s*[0-9a-f]+:' "$ISA" || wc -l < "$ISA")" >> "$OUT"
kol_log "$LABEL ISA counts -> $OUT"
cat "$OUT" >&2
