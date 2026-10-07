#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: %s <source-directory> <destination-directory> <deb|arch>\n' "$0" >&2
    exit 1
fi

source_dir=$1
destination_dir=$2
case "$3" in
    deb) license_path=usr/share/doc/okular-session/copyright ;;
    arch) license_path=usr/share/licenses/okular-session/LICENSE ;;
    *) printf 'Unsupported package format: %s\n' "$3" >&2; exit 1 ;;
esac

install -Dm755 "$source_dir/okular-session.sh" "$destination_dir/usr/bin/okular-session"
install -Dm644 "$source_dir/okular-session.desktop" \
    "$destination_dir/usr/share/applications/okular-session.desktop"
install -Dm644 "$source_dir/README.md" "$destination_dir/usr/share/doc/okular-session/README.md"
install -Dm644 "$source_dir/LICENSE" "$destination_dir/$license_path"
