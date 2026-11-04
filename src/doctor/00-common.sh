# src/doctor/00-common.sh — Shared state and output helpers
# Sourced by doctor.sh, not executed directly.

# Load share/ modules. Two layouts to support:
#   repo:      <root>/src/doctor/00-common.sh  -> <root>/share/
#   installed: <data>/00-common.sh             -> <data>/share/
# Only the repo layout used to be probed, so an installed doctor looked for
# <data>/../share and carried on with no share functions loaded at all.
_doctor_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
for _candidate in "$_doctor_dir/../../share" "$_doctor_dir/share" "$_doctor_dir/../share"; do
  if [[ -f "$_candidate/load.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_candidate/load.sh"
    break
  fi
done
unset _doctor_dir _candidate



SAVE=""
QUICK=false
REPORT_FILE=""

parse_args() {
  SAVE="${1:-}"
  case "$SAVE" in
    --save)
      REPORT_FILE="$FUSION_DOCTOR_REPORT_TEMPLATE"
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



print_summary() {
  section_header "Summary"
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
    echo "  ✗ $SECTION_FAIL critical issue(s). Re-run ./install.sh from the repo before launching."
    exit 2
  fi
}

print_banner() {
  section_header "Fusion360 on Linux — Doctor Report"
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
