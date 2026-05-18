#!/usr/bin/env bash

set -euo pipefail

OKULAR_BIN="${OKULAR_BIN:-/usr/bin/okular}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/okular-session"
SESSION_FILE="${OKULAR_SESSION_FILE:-$STATE_DIR/last-pdfs.txt}"
POLL_INTERVAL="${OKULAR_SESSION_POLL_INTERVAL:-1}"

LAST_SNAPSHOT=""
RESTORED_SESSION=()

snapshot_pdf_paths() {
    local pid_from_ps=""
    local fd_dir=""
    local raw_listing=""

    # Keep the user-requested /proc probe as the primary capture path.
    pid_from_ps="$(ps -C okular -o pid= | sed -e 's/[[:space:]]//g' || true)"

    if [[ -n "$pid_from_ps" && -d "/proc/$pid_from_ps/fd" ]]; then
        fd_dir="/proc/$pid_from_ps/fd"
    elif [[ -n "${okular_pid:-}" && -d "/proc/$okular_pid/fd" ]]; then
        # Fall back to the wrapper-tracked PID if multiple Okular processes
        # make the pid_from_ps value ambiguous.
        fd_dir="/proc/$okular_pid/fd"
    else
        return 1
    fi

    raw_listing="$(ls -l "$fd_dir" 2>/dev/null | grep '.pdf' || true)"

    printf '%s\n' "$raw_listing" \
        | sed -E 's/^.* -> //' \
        | sed -E 's/ \(deleted\)$//' \
        | awk 'NF && !seen[$0]++'
}

refresh_snapshot() {
    local current_snapshot=""

    if current_snapshot="$(snapshot_pdf_paths)"; then
        LAST_SNAPSHOT="$current_snapshot"
    fi
}

persist_snapshot() {
    local tmp_file=""

    mkdir -p "$STATE_DIR"

    if [[ -z "$LAST_SNAPSHOT" ]]; then
        rm -f "$SESSION_FILE"
        return
    fi

    tmp_file="$(mktemp "${SESSION_FILE}.XXXXXX")"
    printf '%s\n' "$LAST_SNAPSHOT" >"$tmp_file"
    mv "$tmp_file" "$SESSION_FILE"
}

restore_saved_session() {
    local pdf_path=""

    [[ -s "$SESSION_FILE" ]] || return 1

    RESTORED_SESSION=()

    while IFS= read -r pdf_path; do
        [[ -n "$pdf_path" && -f "$pdf_path" ]] || continue
        RESTORED_SESSION+=("$pdf_path")
    done <"$SESSION_FILE"

    [[ ${#RESTORED_SESSION[@]} -gt 0 ]] || return 1
}

merge_restored_session_into_snapshot() {
    local merged_snapshot=""

    [[ ${#RESTORED_SESSION[@]} -gt 0 ]] || return

    merged_snapshot="$(
        {
            printf '%s\n' "${RESTORED_SESSION[@]}"
            if [[ -n "$LAST_SNAPSHOT" ]]; then
                printf '%s\n' "$LAST_SNAPSHOT"
            fi
        } | awk 'NF && !seen[$0]++'
    )"

    LAST_SNAPSHOT="$merged_snapshot"
}

main() {
    local launch_args=("$@")
    local has_launch_args=0
    local okular_status=0

    if [[ ${#launch_args[@]} -gt 0 ]]; then
        has_launch_args=1
    fi

    restore_saved_session || true

    if [[ ${#launch_args[@]} -eq 0 && ${#RESTORED_SESSION[@]} -gt 0 ]]; then
        launch_args=("${RESTORED_SESSION[@]}")
    fi

    "$OKULAR_BIN" "${launch_args[@]}" &
    okular_pid=$!

    refresh_snapshot

    while kill -0 "$okular_pid" 2>/dev/null; do
        sleep "$POLL_INTERVAL"
        refresh_snapshot
    done

    if wait "$okular_pid"; then
        okular_status=0
    else
        okular_status=$?
    fi

    refresh_snapshot
    if [[ "$has_launch_args" -eq 1 ]]; then
        merge_restored_session_into_snapshot
    fi
    persist_snapshot

    return "$okular_status"
}

main "$@"
