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

    local -a buf=()
    local started=0

    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        if (( !started )); then
            echo          # move to a fresh line so box starts below caller's output
            tput sc
            started=1
        fi

        # Go to saved position, overwrite each line (clearing it first)
        tput rc
        for l in "${buf[@]}"; do
            printf '\033[K%s\n' "$l"
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
    if (( started )); then
        tput rc
        tput ed
    fi
}
