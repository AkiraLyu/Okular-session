#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
    printf 'Usage: %s <source-directory> <destination-directory> <deb|arch> <X.Y.Z-R>\n' "$0" >&2
    exit 1
fi

source_dir=$1
destination_dir=$2
# shellcheck source=packaging/common.sh
source "$source_dir/packaging/common.sh"
parse_package_version "$4"
case "$3" in
    deb|arch) ;;
    *) printf 'Unsupported package format: %s\n' "$3" >&2; exit 1 ;;
esac

install -Dm755 "$source_dir/okular-session.sh" "$destination_dir/usr/bin/okular-session"
install -Dm644 "$source_dir/okular-session.desktop" \
    "$destination_dir/usr/share/applications/okular-session.desktop"
install -Dm644 "$source_dir/README.md" "$destination_dir/usr/share/doc/okular-session/README.md"
doc_dir="$destination_dir/usr/share/doc/okular-session"
install -d "$destination_dir/usr/share/man/man1"
{
    printf '# NAME\n\nokular-session - save and restore local document sessions in Okular\n\n'
    cat "$source_dir/README.md"
} | pandoc --standalone --from=markdown --to=man \
    --metadata=title:OKULAR-SESSION --metadata=section:1 --metadata=header:'User Commands' \
    | gzip -n -9 > "$destination_dir/usr/share/man/man1/okular-session.1.gz"
changelog_name=changelog.gz
[[ "$3" != deb ]] || changelog_name=changelog.Debian.gz
sed -e "s/@VERSION@/$package_version/g" \
    -e "s/@DATE@/$(LC_ALL=C date -u -d "@$SOURCE_DATE_EPOCH" -R)/g" \
    "$source_dir/packaging/changelog.in" | gzip -n -9 > "$doc_dir/$changelog_name"
case "$3" in
    deb)
        install -m644 "$source_dir/packaging/debian/copyright" "$doc_dir/copyright"
        ;;
    arch)
        install -Dm644 "$source_dir/LICENSE" "$destination_dir/usr/share/licenses/okular-session/LICENSE"
        ;;
esac
