#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    printf 'Usage: %s <deb|arch> <version> [output-directory]\n' "$0" >&2
    exit 1
fi

format=$1
version=$2
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+[a-zA-Z0-9.]+)?$ ]]; then
    printf 'Invalid package version: %s\n' "$version" >&2
    exit 1
fi
case "$format" in
    deb|arch) ;;
    *) printf 'Unsupported package format: %s\n' "$format" >&2; exit 1 ;;
esac

repository_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p -- "${3:-$repository_dir/dist}"
output_dir=$(cd -- "${3:-$repository_dir/dist}" && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT

case "$format" in
    deb)
        package_dir="$build_dir/package"
        bash "$repository_dir/packaging/stage.sh" "$repository_dir" "$package_dir" deb
        install -d "$package_dir/DEBIAN"
        sed "s/@VERSION@/$version/" "$repository_dir/packaging/debian/control" \
            > "$package_dir/DEBIAN/control"
        installed_size=$(du -sk "$package_dir/usr" | awk '{print $1}')
        printf 'Installed-Size: %s\n' "$installed_size" >> "$package_dir/DEBIAN/control"
        dpkg-deb --root-owner-group --build "$package_dir" \
            "$output_dir/okular-session_${version}_all.deb"
        ;;
    arch)
        cp -- "$repository_dir/packaging/arch/PKGBUILD" "$build_dir/PKGBUILD"
        cp -- "$repository_dir/packaging/stage.sh" "$build_dir/stage.sh"
        for filename in okular-session.sh okular-session.desktop README.md LICENSE; do
            cp -- "$repository_dir/$filename" "$build_dir/$filename"
        done
        cd -- "$build_dir"
        PACKAGE_VERSION="$version" PKGDEST="$output_dir" \
            makepkg --nodeps --cleanbuild --clean --force
        ;;
esac
