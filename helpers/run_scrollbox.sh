#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.
# Pipe into it:  long-command 2>&1 | run_scrollbox 5

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    # Determine the actual terminal device (check stdout, not stdin — stdin is the pipe)
    local tty_dev
    tty_dev=$(tty <&1 2>/dev/null) || tty_dev="/dev/tty"
    [[ -c "$tty_dev" ]] || { cat -; return 0; }

    # Redirect stdout to the terminal so all ANSI goes there directly
    exec > "$tty_dev"

    # DEC sequences (work in tmux/screen)
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
            printf '\n'          # fresh line
            printf '%b' "$SAVE"  # save cursor here
            started=1
        fi

        printf '%b' "$REST"      # go to saved position
        for l in "${buf[@]}"; do
            printf '%b%s\n' "$CLR" "$l"
        done

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
