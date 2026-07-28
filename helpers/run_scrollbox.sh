#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show live status line + last N lines at end.
# During execution: single updating line via \r (works on ALL terminals)
# At end: prints the final N lines of output.
# Use --until PATTERN to stop early when a line matches.

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    local -a buf=()
    local cols=80

    # Query terminal width (non-printing: uses TIOCGWINSZ ioctl, no ANSI sent)
    if [[ -t 1 ]]; then
        cols=$(tput cols 2>/dev/null || echo 80)
    fi

    while IFS= read -r line; do
        # Append and trim ring buffer when it exceeds height
        buf+=("$line")
        if (( ${#buf[@]} > height )); then
            buf=("${buf[@]:1}")
        fi

        # Live status: overwrite previous status line with \r
        if [[ -t 1 ]]; then
            printf '\r%s' "$line"
        fi

        if [[ -n "$until_pat" ]] && grep -q "$until_pat" <<< "$line"; then
            # Clear status line and print final window
            if [[ -t 1 ]]; then
                printf '\r%*s\r' "$cols" ""
            fi
            printf '%s\n' "${buf[@]}"
            return 0
        fi
    done

    # EOF: clear status line and show final window
    if [[ -t 1 ]]; then
        printf '\r%*s\r' "$cols" ""
    fi
    printf '%s\n' "${buf[@]}"
}
