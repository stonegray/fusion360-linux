#!/usr/bin/env bash
# scroll-test.sh — Test run_scrollbox
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/run_scrollbox.sh"

echo "=== TEST 1: 12 lines, height=5 → should show lines 8-12 ==="
seq 1 12 | run_scrollbox 5
echo ""

echo "=== TEST 2: 3 lines, height=5 → should show all 3 ==="
printf 'a\nb\nc\n' | run_scrollbox 5
echo ""

echo "=== TEST 3: Slow scroll (10 lines, 0.3s each, height=5) ==="
{
    for i in $(seq 1 10); do
        echo "$(date +%H:%M:%S) line $i"
        sleep 0.3
    done
} | run_scrollbox 5
echo ""
echo "  (last 5 lines should be lines 6-10 with timestamps)"
echo ""

echo "=== TEST 4: --until cut-off ==="
{
    echo "line 1"
    sleep 0.1
    echo "line 2"
    sleep 0.1
    echo "STOP NOW"
    sleep 0.1
    echo "line 4 (hidden)"
    sleep 0.1
    echo "line 5 (hidden)"
} | run_scrollbox --until "STOP NOW" 5
echo ""
echo "  (should have shown up to 'STOP NOW')"
