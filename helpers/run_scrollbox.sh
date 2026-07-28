#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Display command output in a fixed-height scrollable box
# Source this file, then call the function.
# Usage in install-scripts/*.sh:
#   source "$SCRIPT_DIR/helpers/run_scrollbox.sh"
#   run_scrollbox 5 "wineserver -k 2>&1 || true"

run_scrollbox() {
    local height="${1:-5}"
    shift
    local cmd="$*"
    local gray="\e[90m"
    local reset="\e[0m"

    # Fallback if tput is missing or output is not a terminal
    if ! command -v tput &>/dev/null || [[ ! -t 1 ]]; then
        eval "$cmd"
        return $?
    fi

    local cols
    cols=$(tput cols)
    local exit_code=0
    local line_count=0

    # Reserve space on screen
    tput sc
    for ((i=0; i<height; i++)); do
        echo
    done
    tput rc

    # Read command output line by line
    while IFS= read -r line; do
        # Truncate long lines to terminal width
        if (( ${#line} > cols )); then
            line="${line:0:cols-1}"
        fi

        tput rc
        tput cud $((line_count % height))
        tput el
        printf '%b%s%b' "$gray" "$line" "$reset"

        ((line_count++))
    done < <(eval "$cmd" 2>&1)

    exit_code=$?

    # Clean up: erase the scroll box
    tput rc
    tput ed

    return $exit_code
}
