#!/usr/bin/env bash
# helpers/run_scrollbox.sh — Display command output in a fixed-height scrollable box
# Source this file, then call the function.
#
# Usage:
#   run_scrollbox 5 "long-command --with output"
#   run_scrollbox --pid MY_PID 5 "long-command --with output"
#
# With --pid: runs command in background, writes PID to the named variable,
# and displays output in the scrollbox. Useful when the caller needs to
# track the PID for cleanup traps.

run_scrollbox() {
    local pid_var=""
    local bg=0

    # Parse optional --pid flag
    if [[ "${1:-}" == "--pid" ]]; then
        pid_var="${2:-}"
        if [[ -z "$pid_var" ]]; then
            echo "run_scrollbox: --pid requires a variable name" >&2
            return 1
        fi
        shift 2
        bg=1
    fi

    local height="${1:-5}"
    shift
    local cmd="$*"
    local gray="\e[90m"
    local reset="\e[0m"

    # Fallback if tput is missing or output is not a terminal
    if ! command -v tput &>/dev/null || [[ ! -t 1 ]]; then
        if [[ $bg -eq 1 ]]; then
            eval "$cmd" &
            printf -v "$pid_var" "%s" "$!"
            wait $! 2>/dev/null || true
            return $?
        else
            eval "$cmd"
            return $?
        fi
    fi

    local cols; cols=$(tput cols)
    local exit_code=0
    local line_count=0
    local tmpout=""

    # Background mode: redirect output to temp file, poll for updates
    if [[ $bg -eq 1 ]]; then
        tmpout=$(mktemp /tmp/fusion-scrollbox-XXXXX)
        eval "$cmd" >"$tmpout" 2>&1 &
        local pid=$!
        printf -v "$pid_var" "%s" "$pid"

        # Reserve space
        tput sc
        for ((i=0; i<height; i++)); do echo; done
        tput rc

        local line
        while kill -0 "$pid" 2>/dev/null; do
            while IFS= read -r line; do
                if (( ${#line} > cols )); then line="${line:0:cols-1}"; fi
                tput rc
                tput cud $((line_count % height))
                tput el
                printf '%b%s%b' "$gray" "$line" "$reset"
                ((line_count++))
            done < "$tmpout" 2>/dev/null || true
            sleep 0.2
        done

        # Drain any remaining output
        while IFS= read -r line; do
            if (( ${#line} > cols )); then line="${line:0:cols-1}"; fi
            tput rc
            tput cud $((line_count % height))
            tput el
            printf '%b%s%b' "$gray" "$line" "$reset"
            ((line_count++))
        done < "$tmpout" 2>/dev/null || true

        wait "$pid" 2>/dev/null || true
        exit_code=$?
        rm -f "$tmpout"

    else
        # Foreground mode (existing behavior)
        tput sc
        for ((i=0; i<height; i++)); do echo; done
        tput rc

        while IFS= read -r line; do
            if (( ${#line} > cols )); then line="${line:0:cols-1}"; fi
            tput rc
            tput cud $((line_count % height))
            tput el
            printf '%b%s%b' "$gray" "$line" "$reset"
            ((line_count++))
        done < <(eval "$cmd" 2>&1)

        exit_code=$?
    fi

    tput rc
    tput ed
    return $exit_code
}
