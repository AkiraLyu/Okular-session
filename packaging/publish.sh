#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[1-9][0-9]*$ ]]; then
    printf 'Usage: %s <vX.Y.Z-R> <asset-directory>\n' "$0" >&2
    exit 1
fi

tag=$1
version=${tag#v}
cd -- "$2"
assets=(
    "okular-session_${version}_all.deb"
    "okular-session-${version}-any.pkg.tar.zst"
    "okular-session-${version}.tar.gz"
    PKGBUILD
    install.sh
)
for asset in "${assets[@]}"; do
    [[ -s "$asset" ]] || { printf 'Missing release asset: %s\n' "$asset" >&2; exit 1; }
done
sha256sum -- "${assets[@]}" > SHA256SUMS

# Creation refuses an existing release, including a draft from an incomplete run.
# Assets remain private until every upload succeeds and the draft is published.
gh release create "$tag" "${assets[@]}" SHA256SUMS \
    --draft --verify-tag --generate-notes --title "$tag"
gh release edit "$tag" --draft=false --latest
