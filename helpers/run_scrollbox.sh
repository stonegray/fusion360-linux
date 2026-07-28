#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.
# Pipe into it:  long-command 2>&1 | run_scrollbox 5
# Output overwrites in-place at the cursor. Box is removed when done.
#
# Usage:
#   command 2>&1 | run_scrollbox 5
#   run_scrollbox --until "Done" 5 < /tmp/pipe

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    # Not a terminal — pass through
    [[ -t 1 ]] || { cat -; return; }

    local -a buf=()
    local cols; cols=$(tput cols 2>/dev/null || echo 80)
    local prev_lines=0  # lines printed in previous iteration

    while IFS= read -r line; do
        # Truncate
        (( ${#line} >= cols-1 )) && line="${line:0:cols-2}…"

        buf+=("$line")
        buf=("${buf[@]: -$height}")

        # Move cursor up by number of lines from previous iteration
        if (( prev_lines > 0 )); then
            printf '\033[%dA\r' "$prev_lines"
        fi

        # Print current buffer
        for l in "${buf[@]}"; do
            printf '\033[K%s\n' "$l"
        done
        prev_lines=${#buf[@]}

        # Completion pattern
        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            printf '\033[%dA\033[J' "$prev_lines"
            return
        fi
    done

    # Remove the box from display
    printf '\033[%dA\033[J' "$prev_lines"
}
