#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.
# Uses cursor-up (\033[<n>A) which works on ALL terminals.

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    [[ -t 1 ]] || { cat -; return 0; }

    local CLR='\033[K'
    local -a buf=()
    local printed=0  # lines printed in previous iteration

    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        # Go up by number of lines from previous print
        if (( printed > 0 )); then
            printf '\033[%dA\r' "$printed"
        fi

        # Print current buffer
        for l in "${buf[@]}"; do
            printf '%b%s\n' "$CLR" "$l"
        done
        printed=${#buf[@]}

        # Completion pattern
        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            printf '\033[%dA\033[J' "$printed"
            return 0
        fi
    done

    # Clean up
    if (( printed > 0 )); then
        printf '\033[%dA\033[J' "$printed"
    fi
}
