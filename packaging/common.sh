#!/usr/bin/env bash
# Shared metadata and version fields are consumed by the sourcing scripts.
# shellcheck disable=SC2034

package_maintainer='Akira Lyu <akira.uestc@gmail.com>'

parse_package_version() {
    package_version=$1
    if [[ ! "$package_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+[a-zA-Z0-9.]+)?-[1-9][0-9]*$ ]]; then
        printf 'Invalid package version: %s (expected X.Y.Z-R)\n' "$package_version" >&2
        return 1
    fi
    upstream_version=${package_version%-*}
    package_revision=${package_version##*-}
}
