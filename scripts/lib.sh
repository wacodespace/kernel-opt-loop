#!/usr/bin/env bash
# Shared helpers for all loop scripts. Sourced, not executed.
#
# Responsibilities:
#   - locate and parse config/target.yaml (minimal YAML reader, no deps)
#   - export the environment the benchmark needs
#   - manage the per-run experiment directory
#   - uniform logging
#
# Usage at top of every script:
#   set -euo pipefail
#   source "$(dirname "$0")/lib.sh"
#   kol_load_config        # populates KOL_* variables
#   kol_init_run "$1"      # optional: set/create the experiment dir

set -euo pipefail

KOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOL_CONFIG="${KOL_CONFIG:-$KOL_ROOT/config/target.yaml}"

kol_log()  { printf '\033[32m[kol]\033[0m %s\n' "$*" >&2; }
kol_warn() { printf '\033[33m[kol WARN]\033[0m %s\n' "$*" >&2; }
kol_die()  { printf '\033[31m[kol ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# Tiny YAML getter for "a.b.c" dotted keys. Handles scalars and `>-` folded
# blocks. Not a general YAML parser — only what target.yaml needs.
kol_yaml() {
  local key="$1" file="${2:-$KOL_CONFIG}"
  python3 - "$file" "$key" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)
cur = doc
for part in sys.argv[2].split('.'):
    if cur is None or part not in cur:
        sys.exit(0)
    cur = cur[part]
if isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is not None:
    print(str(cur).strip())
PY
}

kol_load_config() {
  [ -f "$KOL_CONFIG" ] || kol_die "config not found: $KOL_CONFIG (copy config/target.example.yaml)"
  KOL_PROJECT_ROOT="$(kol_yaml project.root)"
  KOL_PYTHONPATH="$(kol_yaml project.pythonpath)"
  KOL_ARCH="$(kol_yaml gpu.arch)"
  KOL_PRODUCT="$(kol_yaml gpu.product)"
  KOL_DEVICE="$(kol_yaml gpu.visible_device)"
  KOL_HIPCC="$(kol_yaml toolchain.hipcc)"
  KOL_ROCPROF="$(kol_yaml toolchain.rocprof_compute)"
  KOL_ROCPROFV3="$(kol_yaml toolchain.rocprofv3)"
  KOL_OBJDUMP="$(kol_yaml toolchain.llvm_objdump)"
  KOL_ROCMINFO="$(kol_yaml toolchain.rocminfo)"
  KOL_BENCH_CMD="$(kol_yaml benchmark.cmd)"
  KOL_RUNTIME_RE="$(kol_yaml benchmark.runtime_regex)"
  KOL_CORRECTNESS_CMD="$(kol_yaml benchmark.correctness_cmd)"
  KOL_KERNEL_MATCH="$(kol_yaml kernel.name_match)"
  KOL_TRITON_CACHE="$(eval echo "$(kol_yaml kernel.triton_cache_dir)")"
  [ -n "$KOL_PROJECT_ROOT" ] || kol_die "project.root is empty in config"
}

# Build the env-prefixed benchmark command. Arg 1: optional extra env (e.g. a
# dedicated TRITON_CACHE_DIR for the modified run so we don't reuse baseline .hsaco).
kol_bench_cmd() {
  local extra_env="${1:-}"
  echo "env HIP_VISIBLE_DEVICES=$KOL_DEVICE PYTHONPATH=$KOL_PYTHONPATH $extra_env $KOL_BENCH_CMD"
}

# Resolve / create the experiment run directory. Stored in KOL_RUN.
kol_init_run() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    name="$(date +%Y%m%d_%H%M%S)"
  fi
  case "$name" in
    /*) KOL_RUN="$name" ;;
    *)  KOL_RUN="$KOL_ROOT/experiments/$name" ;;
  esac
  mkdir -p "$KOL_RUN"
  echo "$KOL_RUN"
}
