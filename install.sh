#!/usr/bin/env bash
set -euo pipefail

RELEASE_URL=https://github.com/AkiraLyu/Okular-session/releases
format=''
version=''
assume_yes=false

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: bash install.sh --package <deb|arch> [--version vX.Y.Z] [--yes]\n'
    printf '  --package deb|arch  Select the package format (required).\n'
    printf '  --version vX.Y.Z    Install a specific release (default: latest).\n'
    printf '  --yes              Accept package manager confirmation prompts.\n'
    printf '  -h, --help         Show this help.\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package)
            [[ $# -ge 2 ]] || fail '--package requires deb or arch.'
            format=$2
            shift 2
            ;;
        --version)
            [[ $# -ge 2 ]] || fail '--version requires a release tag.'
            version=$2
            shift 2
            ;;
        --yes) assume_yes=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

case "$format" in
    deb) package_manager=apt-get ;;
    arch) package_manager=pacman ;;
    '') fail 'Select a package format with --package deb or --package arch.' ;;
    *) fail "Unsupported package format: $format. Choose deb or arch." ;;
esac
[[ $(uname -s) == Linux ]] || fail 'Only Linux is supported.'

for dependency in curl sha256sum awk mktemp "$package_manager"; do
    command -v "$dependency" >/dev/null 2>&1 || fail "Required command not found: $dependency"
done

privilege_command=()
if [[ $(id -u) -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || fail 'Install sudo or run this script as root.'
    privilege_command=(sudo)
fi

if [[ -z "$version" ]]; then
    latest_url=$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --output /dev/null --write-out '%{url_effective}' "$RELEASE_URL/latest") \
        || fail 'Could not resolve the latest release. Check that a release has been published.'
    [[ "$latest_url" == "$RELEASE_URL/tag/"* ]] || fail 'No published release was found.'
    version=${latest_url#"$RELEASE_URL/tag/"}
fi
[[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || fail 'Release tags must use vX.Y.Z, for example v1.0.0.'

case "$format" in
    deb) package_name="okular-session_${version#v}_all.deb" ;;
    arch) package_name="okular-session-${version#v}-1-any.pkg.tar.zst" ;;
esac

download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT
download_url="$RELEASE_URL/download/$version"
printf 'Downloading %s...\n' "$package_name"
for filename in "$package_name" SHA256SUMS; do
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --output "$download_dir/$filename" "$download_url/$filename" \
        || fail "Could not download $filename from release $version."
done

awk -v package="$package_name" '$2 == package { print }' "$download_dir/SHA256SUMS" \
    > "$download_dir/package.sha256"
[[ $(awk 'END { print NR }' "$download_dir/package.sha256") -eq 1 ]] \
    || fail 'The release must contain exactly one checksum for the selected package.'
(
    cd -- "$download_dir"
    sha256sum --check --strict package.sha256
) || fail 'Package checksum verification failed.'

printf 'Installing %s with the system package manager...\n' "$version"
install_options=()
if [[ "$assume_yes" == true ]]; then
    case "$format" in
        deb) install_options=(--yes) ;;
        arch) install_options=(--noconfirm) ;;
    esac
fi
case "$format" in
    deb) "${privilege_command[@]}" apt-get install "${install_options[@]}" "$download_dir/$package_name" ;;
    arch) "${privilege_command[@]}" pacman -U "${install_options[@]}" "$download_dir/$package_name" ;;
esac
printf 'Installation complete. Run okular-session to restore your documents.\n'
