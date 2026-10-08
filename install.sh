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
    printf 'Usage: bash install.sh --package <deb|arch> [--version vX.Y.Z-R] [--yes]\n'
    printf '  --package deb|arch  Select the package format (required).\n'
    printf '  --version vX.Y.Z-R  Install a specific package revision (default: latest).\n'
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

for dependency in curl sha256sum mktemp "$package_manager"; do
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
[[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[1-9][0-9]*$ ]] \
    || fail 'Release tags must use vX.Y.Z-R, for example v1.0.0-2.'

download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT
download_url="$RELEASE_URL/download/$version"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --output "$download_dir/SHA256SUMS" "$download_url/SHA256SUMS" \
    || fail "Could not download SHA256SUMS from release $version."
package_name=''
while read -r checksum candidate extra; do
    case "$format:$candidate" in
        deb:okular-session_*_all.deb)
            candidate_version=${candidate#okular-session_}
            candidate_version=${candidate_version%_all.deb}
            ;;
        arch:okular-session-*-any.pkg.tar.zst)
            candidate_version=${candidate#okular-session-}
            candidate_version=${candidate_version%-any.pkg.tar.zst}
            ;;
        *) continue ;;
    esac
    [[ "$candidate_version" == "${version#v}" ]] || continue
    [[ "$checksum" =~ ^[[:xdigit:]]{64}$ && -z "$extra" ]] || fail 'Invalid package checksum entry.'
    [[ -z "$package_name" ]] || fail 'The release contains multiple matching packages.'
    package_name=$candidate
    printf '%s  %s\n' "$checksum" "$package_name" > "$download_dir/package.sha256"
done < "$download_dir/SHA256SUMS"
[[ -n "$package_name" ]] || fail 'The release contains no package for the requested format and version.'
printf 'Downloading %s...\n' "$package_name"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --output "$download_dir/$package_name" "$download_url/$package_name" \
    || fail "Could not download $package_name from release $version."
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
