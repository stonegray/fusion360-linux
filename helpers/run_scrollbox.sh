#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.
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

    # Not a terminal — pass through
    [[ -t 1 ]] || { cat -; return 0; }

    # Save cursor, reserve blank lines (push terminal up if at bottom),
    # then restore cursor to saved position — this is our fixed anchor.
    tput sc
    for ((i=0; i<height; i++)); do echo; done
    tput rc

    local -a buf=()
    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        # Go to saved anchor, clear everything below it, redraw buffer
        tput rc
        tput ed
        for l in "${buf[@]}"; do
            printf '%s\n' "$l"
        done

        # Completion pattern
        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            tput rc
            tput ed
            return 0
        fi
    done

    # Clean up the box area
    tput rc
    tput ed
}
