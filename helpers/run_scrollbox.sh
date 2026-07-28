#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    [[ -t 1 ]] || { cat -; return 0; }

    local -a buf=()
    local printed=0
    local first=1

    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        if (( first )); then
            printf '\n'        # fresh line so box doesn't eat caller's output
            first=0
        fi

        # Go up by previous print height, rewrite all lines
        if (( printed > 0 )); then
            printf '\033[%dA\r' "$printed"
        fi
        for l in "${buf[@]}"; do
            printf '%s\n' "$l"
        done
        printed=${#buf[@]}

        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            printf '\033[%dA\033[J' "$printed"
            printf '\n'
            return 0
        fi
    done

    if (( printed > 0 )); then
        printf '\033[%dA\033[J' "$printed"
        printf '\n'
    fi
}
