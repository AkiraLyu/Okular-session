#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || "${OKULAR_SESSION_TEST_CONTAINER:-}" != 1 || $(id -u) -ne 0 ]]; then
    printf 'Run as root in a disposable container: OKULAR_SESSION_TEST_CONTAINER=1 %s <deb|arch> <X.Y.Z-R> <output-directory>\n' "$0" >&2
    exit 1
fi

format=$1
repository_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=packaging/common.sh
source "$repository_dir/packaging/common.sh"
parse_package_version "$2"
version=$package_version
upgrade_version="$upstream_version-$((package_revision + 1))"
mkdir -p -- "$3"
output_dir=$(cd -- "$3" && pwd)
scratch_dir=$(mktemp -d)
trap 'rm -rf -- "$scratch_dir"' EXIT
chmod 755 "$scratch_dir"
mkdir "$scratch_dir/repeat" "$scratch_dir/upgrade"

case "$format" in
    deb)
        package_file="okular-session_${version}_all.deb"
        upgrade_file="okular-session_${upgrade_version}_all.deb"
        ;;
    arch)
        package_file="okular-session-${version}-any.pkg.tar.zst"
        upgrade_file="okular-session-${upgrade_version}-any.pkg.tar.zst"
        useradd --create-home builder
        export OKULAR_SESSION_BUILD_ROOT=/build/okular-session
        install -d -o builder -g builder "$OKULAR_SESSION_BUILD_ROOT"
        chown builder:builder "$output_dir" "$scratch_dir/repeat" "$scratch_dir/upgrade"
        pacman-conf | sed '/^NoExtract[[:space:]]*=/d' > "$scratch_dir/pacman.conf"
        ;;
    *) printf 'Unsupported package format: %s\n' "$format" >&2; exit 1 ;;
esac

build_package() {
    if [[ "$format" == arch ]]; then
        runuser -u builder -- env SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
            OKULAR_SESSION_BUILD_ROOT="$OKULAR_SESSION_BUILD_ROOT" \
            bash "$repository_dir/packaging/build.sh" "$format" "$1" "$2"
    else
        bash "$repository_dir/packaging/build.sh" "$format" "$1" "$2"
    fi
}

install_package() {
    if [[ "$format" == deb ]]; then
        apt-get install --yes --no-install-recommends \
            -o 'Dpkg::Options::=--path-include=/usr/share/doc/okular-session/*' \
            -o 'Dpkg::Options::=--path-include=/usr/share/man/man1/okular-session.1.gz' "$1"
    else
        pacman --config "$scratch_dir/pacman.conf" -U --noconfirm "$1"
    fi
}

verify_installation() {
    test -x /usr/bin/okular-session
    cmp "$repository_dir/okular-session.sh" /usr/bin/okular-session
    cmp "$repository_dir/okular-session.desktop" /usr/share/applications/okular-session.desktop
    cmp "$repository_dir/README.md" /usr/share/doc/okular-session/README.md
    gzip -t /usr/share/man/man1/okular-session.1.gz
    desktop-file-validate /usr/share/applications/okular-session.desktop
    if [[ "$format" == deb ]]; then
        test "$(dpkg-query -W -f='${Version}' okular-session)" = "$1"
        cmp "$repository_dir/packaging/debian/copyright" /usr/share/doc/okular-session/copyright
        gzip -t /usr/share/doc/okular-session/changelog.Debian.gz
        verification=$(dpkg --verify okular-session)
        test -z "$verification"
    else
        test "$(pacman -Q okular-session)" = "okular-session $1"
        cmp "$repository_dir/LICENSE" /usr/share/licenses/okular-session/LICENSE
        gzip -t /usr/share/doc/okular-session/changelog.gz
        pacman -Qkk okular-session
    fi
}

build_package "$version" "$output_dir"
build_package "$version" "$scratch_dir/repeat"
cmp "$output_dir/$package_file" "$scratch_dir/repeat/$package_file"
printf 'Reproducible %s package verified.\n' "$format"

install_package "$output_dir/$package_file"
verify_installation "$version"
if [[ "$format" == deb ]]; then
    lintian --fail-on error,warning "$output_dir/$package_file"
else
    # Namcap cannot infer all dependencies used by shell commands; retain its warnings.
    namcap "$output_dir/PKGBUILD" "$output_dir/$package_file" | tee "$scratch_dir/namcap.log"
    if grep -q ' E:' "$scratch_dir/namcap.log"; then
        exit 1
    fi
fi

# Restore a real saved path through the installed command without starting a GUI.
export XDG_STATE_HOME="$scratch_dir/state"
export OKULAR_SESSION_CONFIG_FILE="$scratch_dir/no-config"
export OKULAR_BIN="$scratch_dir/okular"
export OKULAR_SESSION_POLL_INTERVAL=0.01
cat > "$OKULAR_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$XDG_STATE_HOME/opened"
EOF
chmod 755 "$OKULAR_BIN"
touch "$scratch_dir/document.pdf"
mkdir -p "$XDG_STATE_HOME/okular-session"
printf '%s\n' "$scratch_dir/document.pdf" > "$scratch_dir/expected-session"
cp "$scratch_dir/expected-session" "$XDG_STATE_HOME/okular-session/last-pdfs.txt"
okular-session
cmp "$scratch_dir/expected-session" "$XDG_STATE_HOME/opened"

build_package "$upgrade_version" "$scratch_dir/upgrade"
install_package "$scratch_dir/upgrade/$upgrade_file"
verify_installation "$upgrade_version"
cmp "$scratch_dir/expected-session" "$XDG_STATE_HOME/okular-session/last-pdfs.txt"
if [[ "$format" == deb ]]; then
    apt-get purge --yes okular-session
else
    pacman -R --noconfirm okular-session
fi
test ! -e /usr/bin/okular-session
test ! -e /usr/share/applications/okular-session.desktop
test ! -e /usr/share/doc/okular-session
test ! -e /usr/share/man/man1/okular-session.1.gz
cmp "$scratch_dir/expected-session" "$XDG_STATE_HOME/okular-session/last-pdfs.txt"
printf 'Installation, restoration, revision upgrade, and removal verified.\n'
