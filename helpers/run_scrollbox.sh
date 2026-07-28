#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.
# The last 'height' lines remain visible when done (no cleanup).

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    [[ -t 1 ]] || { cat -; return 0; }

    local -a buf=()
    local prev_lines=0

    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        # Go to top of box and rewrite
        if (( prev_lines > 0 )); then
            printf '\033[%dA\r' "$prev_lines"
        fi
        for l in "${buf[@]}"; do
            printf '\r\033[K%s\n' "$l"
        done
        prev_lines=${#buf[@]}

        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            return 0  # last lines stay visible
        fi
    done
    # No cleanup — last lines stay visible
}
