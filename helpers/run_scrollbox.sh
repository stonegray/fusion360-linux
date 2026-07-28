#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Show piped output in a scrollable box.
# Pipe into it:  long-command 2>&1 | run_scrollbox 5

run_scrollbox() {
    local until_pat=""
    [[ "${1:-}" == "--until" ]] && { until_pat="$2"; shift 2; }
    local height="${1:-5}"

    # ── TTY self-test ──────────────────────────────────────────────────
    local tty_dev
    tty_dev=$(tty <&1 2>/dev/null) || tty_dev="/dev/tty"

    # Print diagnostics to the actual terminal (bypass any pipe)
    # This tells us if the TTY device is correct
    printf 'TTY=%s ' "$tty_dev" > "$tty_dev" 2>/dev/null || {
        # Can't write to TTY at all — fall through to cat
        cat -
        return 0
    }

    # Verify by writing [OK] — if we see it, TTY works
    printf '[' > "$tty_dev"
    printf 'OK' > "$tty_dev"
    printf ']\n' > "$tty_dev"

    # Also print height and terminal info
    printf 'height=%d cols=%d tput=%s\n' "$height" "$(tput cols 2>/dev/null || echo 80)" "$(command -v tput)" > "$tty_dev"

    # Now redirect all subsequent output to the terminal
    exec > "$tty_dev"
    # ────────────────────────────────────────────────────────────────────

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
            printf '%b' "$SAVE"
            started=1
        fi

        printf '%b' "$REST"
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
