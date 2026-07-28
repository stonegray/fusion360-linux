#!/usr/bin/env bash
# scroll-test.sh — Test run_scrollbox with simulated installer output.
# Run with: bash scroll-test.sh
# All tests inject delays so you can see the scrolling behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/run_scrollbox.sh"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     scroll-test.sh                                          ║"
echo "║     Watch each test — content should appear in a 5-line     ║"
echo "║     scrollable box and disappear when done.                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Test 1: FIFO (simulates step 5 — real-time streaming) ────────────
echo "=== TEST 1: FIFO (streaming, like step 5) ==="
echo "    Watch for scrolling content in the box below..."
fifo="/tmp/scroll-test-fifo"
rm -f "$fifo"
mkfifo "$fifo"

# Writer: slow stream to simulate installer
(
  for i in $(seq 1 12); do
    echo "[streamer] Processing package $i..."
    sleep 0.3
  done
  echo "[streamer] Installation complete."
  sleep 0.3
  echo "[streamer] Finalizing..."
  sleep 0.5
) > "$fifo" 2>&1 &

writer_pid=$!
run_scrollbox --until "complete" 5 < "$fifo"
wait "$writer_pid" 2>/dev/null || true
rm -f "$fifo"
echo "  (test 1 done)"
echo ""

# ── Test 2: slow foreground pipe ──────────────────────────────────────
echo "=== TEST 2: slow pipe (download simulation) ==="
echo "    Lines should appear one by one in a 5-line box..."
for i in $(seq 1 10); do
  echo "[download] Package $i/10..."
  sleep 0.2
done | run_scrollbox 5
echo "  (test 2 done)"
echo ""

# ── Test 3: fewer lines than height ───────────────────────────────────
echo "=== TEST 3: fewer lines than height ==="
echo "    Only 3 lines — should appear without extra blank space..."
sleep 0.5
{
  echo "Short output"
  sleep 0.3
  echo "line two"
  sleep 0.3
  echo "line three"
} | run_scrollbox 5
echo "  (test 3 done)"
echo ""

# ── Test 4: --until pattern cut-off ───────────────────────────────────
echo "=== TEST 4: --until pattern cut-off ==="
echo "    Should STOP at \"STOP HERE\" and not show the later lines..."
{
  echo "Line 1"
  sleep 0.3
  echo "Line 2"
  sleep 0.3
  echo "STOP HERE"
  sleep 0.3
  echo "Line 4 (should NOT appear)"
  sleep 0.3
  echo "Line 5 (should NOT appear)"
} | run_scrollbox --until "STOP HERE" 5
echo "  (test 4 done)"
echo ""

# ── Test 5: many lines, fast ──────────────────────────────────────────
echo "=== TEST 5: fast flood (should show last 5) ==="
echo "    50 lines at once — should end showing lines 46-50..."
for i in $(seq 1 50); do
  echo "Line $i of 50"
done | run_scrollbox 5
echo "  (test 5 done)"
echo ""

echo "=== All tests completed ==="
