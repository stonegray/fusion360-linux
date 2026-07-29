# src/doctor/00-common.sh — Shared state and output helpers
# Sourced by doctor.sh, not executed directly.

# Load share/ modules (path resolution: this file is at src/doctor/,
# share/ is at the repo root)
_share_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../share" 2>/dev/null && pwd)" || true
if [[ -d "$_share_dir" ]]; then
  source "$_share_dir/load.sh"
fi
unset _share_dir

SECTION_PASS=0
SECTION_FAIL=0
SECTION_WARN=0
RECOMMENDATIONS=()

SAVE=""
QUICK=false
REPORT_FILE=""

parse_args() {
  SAVE="${1:-}"
  case "$SAVE" in
    --save)
      REPORT_FILE="/tmp/fusion360-doctor-$(date +%Y%m%d-%H%M%S).txt"
      exec > >(tee "$REPORT_FILE") 2>&1 || exec > "$REPORT_FILE" 2>&1
      ;;
    --quick)
      QUICK=true
      ;;
    "")
      # No argument — run full report
      ;;
    *)
      echo "Unknown option: $SAVE"
      echo "Usage: doctor.sh [--save] [--quick]"
      exit 1
      ;;
  esac
}

# ── Unified output formatting (mirrors src/install/00-common.sh) ──
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
  _C_RESET="\e[0m"; _C_BOLD="\e[1m"; _C_DIM="\e[2m"
  _C_RED="\e[31m"; _C_GREEN="\e[32m"; _C_YELLOW="\e[33m"
  _C_BLUE="\e[34m"; _C_CYAN="\e[36m"
else
  _C_RESET=""; _C_BOLD=""; _C_DIM=""; _C_RED=""; _C_GREEN=""
  _C_YELLOW=""; _C_BLUE=""; _C_CYAN=""
fi

header()   { printf "\n${_C_BOLD}${_C_CYAN}━━━ %s ━━━${_C_RESET}\n" "$*"; }
pass()     { printf "  ${_C_GREEN}✓${_C_RESET} %s\n" "$*"; ((SECTION_PASS++)) || true; }
fail()     { printf "  ${_C_RED}✗${_C_RESET} %s\n" "$*"; ((SECTION_FAIL++)) || true; RECOMMENDATIONS+=("$*"); }
warn()     { printf "  ${_C_YELLOW}⚠${_C_RESET} %s\n" "$*"; ((SECTION_WARN++)) || true; }
info()     { printf "  ${_C_BLUE}●${_C_RESET} %s\n" "$*"; }
detail()   { printf "  ${_C_DIM}%s${_C_RESET}\n" "$*"; }

print_summary() {
  header "Summary"
  echo "  Passed checks:  $SECTION_PASS"
  echo "  Failed checks:  $SECTION_FAIL"
  echo "  Warnings:       $SECTION_WARN"
  echo ""

  if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
    echo "  ┌── Recommendations ──"
    for r in "${RECOMMENDATIONS[@]}"; do
      echo "  │ $r"
    done
    echo "  └─────────────────────"
    echo ""
  fi

  if [[ $SECTION_FAIL -eq 0 ]]; then
    echo "  ✓ All critical checks passed. Fusion360 should be ready to launch."
    exit 0
  elif [[ $SECTION_FAIL -lt 3 ]]; then
    echo "  △ $SECTION_FAIL minor issue(s). Likely launchable but some features may be affected."
    exit 1
  else
    echo "  ✗ $SECTION_FAIL critical issue(s). Run install.sh and setup-fusion.sh before launching."
    exit 2
  fi
}

print_banner() {
  header "Fusion360 on Linux — Doctor Report"
  echo ""
}

quick_exit() {
  echo ""
  echo "── Quick Summary ──"
  echo "  Pass: $SECTION_PASS  Fail: $SECTION_FAIL  Warn: $SECTION_WARN"
  echo ""
  if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
    echo "  Issues found:"
    for r in "${RECOMMENDATIONS[@]}"; do echo "    - $r"; done
  fi
  exit $(( SECTION_FAIL > 0 ? 1 : 0 ))
}
