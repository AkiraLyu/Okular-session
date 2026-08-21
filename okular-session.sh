#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="${OKULAR_SESSION_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/okular-session/config}"
declare -A ENV_OVERRIDES=()

capture_environment_overrides() {
    local name=""

    for name in \
        OKULAR_BIN \
        OKULAR_SESSION_FILE \
        OKULAR_SESSION_POLL_INTERVAL \
        OKULAR_SESSION_EXTENSIONS \
        OKULAR_SESSION_EXTRA_EXTENSIONS \
        OKULAR_SESSION_STATE_DIR \
        XDG_STATE_HOME; do
        if [[ -v "$name" ]]; then
            ENV_OVERRIDES["$name"]="${!name}"
        fi
    done
}

restore_environment_overrides() {
    local name=""

    for name in "${!ENV_OVERRIDES[@]}"; do
        printf -v "$name" '%s' "${ENV_OVERRIDES[$name]}"
    done
}

load_local_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
}

capture_environment_overrides
load_local_config
restore_environment_overrides

OKULAR_BIN="${OKULAR_BIN:-/usr/bin/okular}"
STATE_DIR="${OKULAR_SESSION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/okular-session}"
SESSION_FILE="${OKULAR_SESSION_FILE:-$STATE_DIR/last-pdfs.txt}"
POLL_INTERVAL="${OKULAR_SESSION_POLL_INTERVAL:-1}"
DEFAULT_SUPPORTED_EXTENSIONS=(pdf epub md markdown txt)
SUPPORTED_EXTENSIONS=()

LAST_SNAPSHOT=""
RESTORED_SESSION=()

add_supported_extensions() {
    local extension_list="$1"
    local extension=""

    extension_list="${extension_list//,/ }"
    extension_list="${extension_list//:/ }"
    extension_list="${extension_list//;/ }"

    for extension in $extension_list; do
        extension="${extension#.}"
        extension="${extension,,}"
        [[ "$extension" =~ ^[a-z0-9][a-z0-9_+-]*$ ]] || continue
        SUPPORTED_EXTENSIONS+=("$extension")
    done
}

configure_supported_extensions() {
    SUPPORTED_EXTENSIONS=()

    if [[ -n "${OKULAR_SESSION_EXTENSIONS:-}" ]]; then
        add_supported_extensions "$OKULAR_SESSION_EXTENSIONS"
    else
        add_supported_extensions "${DEFAULT_SUPPORTED_EXTENSIONS[*]}"
        add_supported_extensions "${OKULAR_SESSION_EXTRA_EXTENSIONS:-}"
    fi

    if [[ ${#SUPPORTED_EXTENSIONS[@]} -eq 0 ]]; then
        add_supported_extensions "${DEFAULT_SUPPORTED_EXTENSIONS[*]}"
    fi
}

is_supported_document_path() {
    local document_path="${1% (deleted)}"
    local lower_path="${document_path,,}"
    local extension=""

    [[ -n "$document_path" ]] || return 1

    for extension in "${SUPPORTED_EXTENSIONS[@]}"; do
        if [[ "$lower_path" == *."$extension" ]]; then
            return 0
        fi
    done

    return 1
}

snapshot_document_paths() {
    local pid=""
    local fd_dir=""
    local fd_path=""
    local fd_target=""
    local found_fd_dir=0
    local -a document_paths=()

    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue

        fd_dir="/proc/$pid/fd"
        [[ -d "$fd_dir" ]] || continue
        found_fd_dir=1

        for fd_path in "$fd_dir"/*; do
            [[ -L "$fd_path" ]] || continue
            fd_target="$(readlink "$fd_path" 2>/dev/null || true)"
            fd_target="${fd_target% (deleted)}"

            if is_supported_document_path "$fd_target"; then
                document_paths+=("$fd_target")
            fi
        done
    done < <(
        {
            ps -C okular -o pid= || true
            if [[ -n "${okular_pid:-}" ]]; then
                printf '%s\n' "$okular_pid"
            fi
        } | awk '$1 ~ /^[0-9]+$/ && !seen[$1]++ { print $1 }'
    )

    [[ "$found_fd_dir" -eq 1 ]] || return 1
    [[ ${#document_paths[@]} -gt 0 ]] || return 0

    printf '%s\n' "${document_paths[@]}" | awk 'NF && !seen[$0]++'
}

refresh_snapshot() {
    local current_snapshot=""

    if current_snapshot="$(snapshot_document_paths)" && [[ -n "$current_snapshot" ]]; then
        LAST_SNAPSHOT="$current_snapshot"
    fi
}

seed_snapshot_from_launch_args() {
    local launch_arg=""
    local document_path=""
    local seeded_snapshot=""

    seeded_snapshot="$(
        for launch_arg in "$@"; do
            [[ -f "$launch_arg" ]] || continue
            document_path="$(readlink -f -- "$launch_arg" 2>/dev/null)" || continue
            is_supported_document_path "$document_path" || continue
            printf '%s\n' "$document_path"
        done | awk 'NF && !seen[$0]++'
    )"

    if [[ -n "$seeded_snapshot" ]]; then
        LAST_SNAPSHOT="$seeded_snapshot"
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
    local document_path=""

    [[ -s "$SESSION_FILE" ]] || return 1

    RESTORED_SESSION=()

    while IFS= read -r document_path; do
        [[ -n "$document_path" && -f "$document_path" ]] || continue
        is_supported_document_path "$document_path" || continue
        RESTORED_SESSION+=("$document_path")
    done <"$SESSION_FILE"

    [[ ${#RESTORED_SESSION[@]} -gt 0 ]] || return 1
}

merge_restored_session_into_snapshot() {
    local merged_snapshot=""

    [[ ${#RESTORED_SESSION[@]} -gt 0 ]] || return 0

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

    configure_supported_extensions

    if [[ ${#launch_args[@]} -gt 0 ]]; then
        has_launch_args=1
    fi

    restore_saved_session || true

    if [[ ${#launch_args[@]} -eq 0 && ${#RESTORED_SESSION[@]} -gt 0 ]]; then
        launch_args=("${RESTORED_SESSION[@]}")
    fi

    seed_snapshot_from_launch_args "${launch_args[@]}"

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
