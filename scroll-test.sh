#!/usr/bin/env bash
# scroll-test.sh — Test run_scrollbox with simulated installer output.
# Run with: bash scroll-test.sh
# Tweak input speed and patterns at the bottom of this file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/run_scrollbox.sh"

test_foreground() {
  echo "=== TEST: foreground pipe ==="
  local lines=(
    "[1/5] Downloading package 1 of 10..."
    "[1/5] Downloading package 2 of 10..."
    "[1/5] Downloading package 3 of 10..."
    "[1/5] Downloading package 4 of 10..."
    "[1/5] Downloading package 5 of 10..."
    "[1/5] Downloading package 6 of 10..."
    "[1/5] Downloading package 7 of 10..."
    "[1/5] Downloading package 8 of 10..."
    "[1/5] Downloading package 9 of 10..."
    "[1/5] Downloading package 10 of 10..."
    "[1/5] Extracting..."
    "[1/5] Installing..."
    "[1/5] Installation complete."
  )

  for l in "${lines[@]}"; do
    echo "$l"
    sleep 0.3
  done | run_scrollbox 5

  echo "  (foreground test done)"
}

test_until() {
  echo "=== TEST: --until pattern ==="
  local lines=(
    "[1/5] Starting..."
    "[1/5] Downloading..."
    "[1/5] Installing..."
    "[1/5] Installation complete."
    "[1/5] Cleanup..."
    "[1/5] Done."
  )

  for l in "${lines[@]}"; do
    echo "$l"
    sleep 0.3
  done | run_scrollbox --until "complete" 5

  echo "  (--until test done)"
}

test_fifo() {
  echo "=== TEST: FIFO (simulates step 5) ==="
  local fifo="/tmp/scroll-test-fifo"
  mkfifo "$fifo" 2>/dev/null || true

  # Writer: background process sending lines at intervals
  (
    for i in $(seq 1 20); do
      echo "[streamer] Processing package $i..."
      sleep 0.2
    done
    echo "[streamer] Installation complete."
    sleep 0.3
    echo "[streamer] Finalizing..."
    sleep 0.5
  ) > "$fifo" 2>&1 &

  local writer_pid=$!

  # Reader: scrollbox
  run_scrollbox --until "complete" 5 < "$fifo"
  local scroll_exit=$?

  wait "$writer_pid" 2>/dev/null || true
  rm -f "$fifo"
  echo "  (FIFO test done, scrollbox exit=$scroll_exit)"
}

test_many_lines() {
  echo "=== TEST: fast many lines (simulates streamer flood) ==="
  for i in $(seq 1 50); do
    echo "[$(date +%H:%M:%S)] Streamer output line $i of 50: processing data chunk $(printf '%04d' $i)..."
  done | run_scrollbox 5
  echo "  (many lines test done)"
}

test_short_output() {
  echo "=== TEST: fewer lines than height ==="
  echo -e "line1\nline2\nline3" | run_scrollbox 5
  echo "  (short output test done)"
}

# ── Run tests ─────────────────────────────────────────────────────────
# Comment out tests you don't want to run
test_short_output
sleep 0.5
test_many_lines
sleep 0.5
test_foreground
sleep 0.5
test_until
sleep 0.5
test_fifo

echo ""
echo "=== All tests passed ==="
