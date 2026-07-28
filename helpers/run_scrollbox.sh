#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a fixed-height scrollable box.
# Pipe into it:  long-command 2>&1 | run_scrollbox 5
# Box is removed when stdin closes or --until pattern matches.
#
# Usage:
#   command 2>&1 | run_scrollbox 5
#   run_scrollbox --until "Done" 5 < /tmp/pipe

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    # Not a terminal — pass stdin through
    if [[ ! -t 1 ]]; then
        cat -
        return
    fi

    local save="\033[s" restore="\033[u" clearline="\033[K" cleardown="\033[J"
    local cols; cols=$(tput cols 2>/dev/null || echo 80)

    # Save cursor, reserve blank lines, restore to top of box
    echo -ne "$save"
    for ((i=0; i<height; i++)); do echo; done
    echo -ne "$restore"

    local -a buf=()
    while IFS= read -r line; do
        # Truncate long lines
        (( ${#line} >= cols-1 )) && line="${line:0:cols-2}…"

        buf+=("$line")
        buf=("${buf[@]: -$height}")

        # Redraw full block from top of box
        echo -ne "$restore"
        for l in "${buf[@]}"; do
            echo -ne "$clearline"
            printf '%s\n' "$l"
        done
        # Clear remaining lines in the box
        for ((i=${#buf[@]}; i<height; i++)); do
            echo -ne "$clearline"
            echo
        done

        # Completion pattern detected — return early
        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            echo -ne "$restore$cleardown"
            return
        fi
    done

    # Clean up the box area
    echo -ne "$restore$cleardown"
}
