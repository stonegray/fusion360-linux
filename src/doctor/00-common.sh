# src/doctor/00-common.sh — Shared state and output helpers
# Sourced by doctor.sh, not executed directly.

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

header()   { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
pass()     { echo "  [PASS] $*"; ((SECTION_PASS++)); }
fail()     { echo "  [FAIL] $*"; ((SECTION_FAIL++)); RECOMMENDATIONS+=("$*"); }
warn()     { echo "  [WARN] $*"; ((SECTION_WARN++)); }
info()     { echo "  [INFO] $*"; }
detail()   { echo "         $*"; }

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
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     Fusion360 on Linux — Doctor Report                      ║"
  echo "║     $(date)                ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
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
