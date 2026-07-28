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

    # Redirect stdout directly to /dev/tty to bypass any shell buffering
    exec >/dev/tty

    # Hardcode ANSI sequences
    local SAVE='\0337'
    local REST='\0338'
    local CLR='\033[K'
    local CLRDN='\033[J'

    local -a buf=()
    local started=0

    while IFS= read -r line; do
        buf+=("$line")
        buf=("${buf[@]: -$height}")

        if (( !started )); then
            printf '\n'          # fresh line for the box
            printf '%b' "$SAVE"
            started=1
        fi

        # Restore cursor to saved position, write each line
        printf '%b' "$REST"
        for l in "${buf[@]}"; do
            printf '%b%s\n' "$CLR" "$l"
        done

        # Completion pattern
        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            sleep 0.5
            printf '%b' "$REST"
            printf '%b' "$CLRDN"
            return 0
        fi
    done

    if (( started )); then
        printf '%b' "$REST"
        printf '%b' "$CLRDN"
    fi
}
