# doctor/20-deps.sh — System Dependency checks

header "2. System Dependencies"

PKG_MGR=""
if command -v apt-get &>/dev/null; then
  PKG_MGR="apt-get"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MGR="pacman"
elif command -v zypper &>/dev/null; then
  PKG_MGR="zypper"
fi
info "Package manager: ${PKG_MGR:-unknown}"

check_dep() {
  local bin="$1" pkg="$2"
  if command -v "$bin" &>/dev/null; then
    pass "$pkg ($bin found)"
  else
    fail "$pkg ($bin not found)"
  fi
}

check_dep wrestool "icoutils"
check_dep zenity  "zenity"
check_dep cabextract "cabextract"
check_dep wget    "wget"
check_dep xdg-open "xdg-utils"
check_dep desktop-file-validate "desktop-file-utils"

if python3 -c "import tkinter" &>/dev/null 2>&1; then
  pass "python3-tk (tkinter import OK)"
else
  fail "python3-tk (tkinter import failed — launcher-config GUI needs this)"
fi

if command -v convert &>/dev/null; then
  pass "imagemagick (convert found) — icon extraction available"
fi

vk_icd_count=$(find /usr/share/vulkan/icd.d/ -name '*.json' 2>/dev/null | wc -l)
if [[ "$vk_icd_count" -gt 0 ]]; then
  info "Vulkan ICD: $vk_icd_count file(s) found"
  ls /usr/share/vulkan/icd.d/ 2>/dev/null | sed 's/^/             /'
else
  warn "No Vulkan ICD files found — Fusion may fall back to software rendering"
fi
