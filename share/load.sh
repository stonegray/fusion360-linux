# share/load.sh — Single entry point for all share/ modules
#
# Usage: source /path/to/share/load.sh
#
# Sources all .fn files in dependency order.  Every script that needs
# share/ utilities should source THIS FILE ONLY, never individual .fn
# files directly.
#
# Layer 0 (no dependencies)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/constants.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/traps.fn"

# Layer 1 (depends on Layer 0)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/os.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/network.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/disk.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hosts.fn"

# Layer 2 (depends on Layers 0-1)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/proton.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wine.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/desktop.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/icon.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/browser-request.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/detect-display.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/browser-bridge.fn"

# Layer 3 (depends on Layers 0-2)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dpi.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dark-mode.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/process.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/daemon.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cleanup.fn"

# Layer 4 (depends on Layers 0-1)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/report.fn"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-dep.fn"
