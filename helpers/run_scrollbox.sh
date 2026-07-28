#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    [[ -t 1 ]] || { cat -; return 0; }

    # STEP 1: test if ANY output works
    printf 'SCROLLBOX_ACTIVE\n'

    local -a buf=()
    local prev_lines=0

    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        # Just print — no ANSI at all
        printf '%s\n' "$line"

        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            printf 'SCROLLBOX_DONE\n'
            return 0
        fi
    done
    printf 'SCROLLBOX_DONE\n'
}
