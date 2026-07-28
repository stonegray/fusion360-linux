#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Display piped input in a fixed-height scrollable box.
# Pipe command output into it:  long-command 2>&1 | run_scrollbox 5
# Reads from stdin, shows the last N lines in a gray scrollable area.
# Cleans up when stdin closes, or when --until pattern matches.
#
# Usage:
#   command 2>&1 | run_scrollbox 5
#   run_scrollbox --until "Installation complete" 5 < /tmp/pipe

run_scrollbox() {
    local until_pattern=""

    # Parse optional --until flag (must come before height)
    if [[ "${1:-}" == "--until" ]]; then
        until_pattern="${2:-}"
        shift 2
    fi

    local height="${1:-5}"
    local gray="\033[37m"
    local reset="\033[0m"

    # Fallback if not a terminal — just pass stdin through
    if ! command -v tput &>/dev/null || [[ ! -t 1 ]]; then
        cat -
        return 0
    fi

    local cols; cols=$(tput cols)
    local -a scrollbuf=()

    # Save cursor, reserve blank lines, return to top
    tput sc
    for ((i=0; i<height; i++)); do echo; done
    tput rc

    # Read stdin, maintain ring buffer, redraw full block each line
    while IFS= read -r line; do
        (( ${#line} > cols-1 )) && line="${line:0:cols-2}..."
        scrollbuf+=("$line")
        (( ${#scrollbuf[@]} > height )) && scrollbuf=("${scrollbuf[@]: -height}")

        tput rc
        for ((i=0; i<${#scrollbuf[@]}; i++)); do
            tput el
            printf '%b%s%b\n' "$gray" "${scrollbuf[i]}" "$reset"
        done
        for ((i=${#scrollbuf[@]}; i<height; i++)); do
            tput el
            echo
        done
        tput rc

        # Check for completion pattern
        if [[ -n "$until_pattern" ]] && echo "$line" | grep -q "$until_pattern"; then
            # Let the last lines display briefly, then clean up
            sleep 0.5
            tput rc
            tput ed
            return 0
        fi
    done

    # Clean up: erase the box area
    tput rc
    tput ed
}
