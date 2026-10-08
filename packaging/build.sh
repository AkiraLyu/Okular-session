#!/usr/bin/env bash
set -euo pipefail
umask 022
export LC_ALL=C

if [[ $# -lt 2 || $# -gt 3 ]]; then
    printf 'Usage: %s <deb|arch> <X.Y.Z-R> [output-directory]\n' "$0" >&2
    exit 1
fi

format=$1
case "$format" in
    deb|arch) ;;
    *) printf 'Unsupported package format: %s\n' "$format" >&2; exit 1 ;;
esac

repository_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=packaging/common.sh
source "$repository_dir/packaging/common.sh"
parse_package_version "$2"
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
    SOURCE_DATE_EPOCH=$(git -C "$repository_dir" show -s --format=%ct HEAD)
fi
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || { printf 'Invalid SOURCE_DATE_EPOCH\n' >&2; exit 1; }
export SOURCE_DATE_EPOCH
mkdir -p -- "${3:-$repository_dir/dist}"
output_dir=$(cd -- "${3:-$repository_dir/dist}" && pwd)

case "$format" in
    deb)
        build_dir=$(mktemp -d)
        trap 'rm -rf -- "$build_dir"' EXIT
        package_dir="$build_dir/package"
        bash "$repository_dir/packaging/stage.sh" "$repository_dir" "$package_dir" deb "$package_version"
        install -d "$package_dir/DEBIAN"
        sed "s/@VERSION@/$package_version/" "$repository_dir/packaging/debian/control" \
            > "$package_dir/DEBIAN/control"
        installed_size=$(du -sk "$package_dir/usr" | awk '{print $1}')
        printf 'Installed-Size: %s\n' "$installed_size" >> "$package_dir/DEBIAN/control"
        (cd "$package_dir" && find usr -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums)
        dpkg-deb --root-owner-group --uniform-compression --build "$package_dir" \
            "$output_dir/okular-session_${package_version}_all.deb"
        ;;
    arch)
        build_root=${OKULAR_SESSION_BUILD_ROOT:-$repository_dir/.build}
        mkdir -p -- "$build_root"
        build_root=$(cd -- "$build_root" && pwd)
        exec 9> "$build_root/arch.lock"
        flock 9
        build_dir="$build_root/arch"
        mkdir -p -- "$build_dir"
        source_name="okular-session-$package_version"
        tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
            --format=gnu --exclude='__pycache__' --transform="s,^,$source_name/," -C "$repository_dir" \
            -cf - README.md LICENSE okular-session.sh okular-session.desktop install.sh packaging tests \
            | gzip -n -9 > "$build_dir/$source_name.tar.gz"
        source_checksum=$(sha256sum "$build_dir/$source_name.tar.gz")
        sed -e "s/@UPSTREAM_VERSION@/$upstream_version/g" \
            -e "s/@REVISION@/$package_revision/g" \
            -e "s/@VERSION@/$package_version/g" \
            -e "s/@SOURCE_DATE_EPOCH@/$SOURCE_DATE_EPOCH/g" \
            -e "s/@SOURCE_SHA256@/${source_checksum%% *}/g" \
            "$repository_dir/packaging/arch/PKGBUILD.in" > "$build_dir/PKGBUILD"
        cd -- "$build_dir"
        PACKAGER="$package_maintainer" BUILDDIR="$build_dir" PKGDEST="$output_dir" PKGEXT='.pkg.tar.zst' \
            makepkg --nodeps --cleanbuild --clean --force --nosign
        cp -- PKGBUILD "$source_name.tar.gz" "$output_dir/"
        ;;
esac
