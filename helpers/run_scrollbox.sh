#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Display piped output.
# Currently a simple pass-through (scrollbox temporarily disabled while
# being reworked). Preserves --until pattern detection.

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    while IFS= read -r line; do
        printf '%s\n' "$line"

        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            return 0
        fi
    done
}
