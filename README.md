# Okular Session Wrapper

`okular-session` saves local document paths from Okular and restores them when launched without arguments. It requires Linux, Bash 4.4 or later, and Okular.

> [!WARNING]
> This project was generated with AI assistance.

## Installation

Choose the package format explicitly. For Debian/Ubuntu:

```bash
curl -fsSL https://github.com/AkiraLyu/Okular-session/releases/latest/download/install.sh | bash -s -- --package deb --yes
```

For Arch Linux:

```bash
curl -fsSL https://github.com/AkiraLyu/Okular-session/releases/latest/download/install.sh | bash -s -- --package arch --yes
```

The installer selects the package from the release checksum manifest, verifies its SHA-256 checksum, and installs it with dependencies. It requires `curl`, coreutils, and the selected package format's package manager. Run as a regular user with `sudo` available, or as root.

| Parameter | Purpose |
| --- | --- |
| `--package deb\|arch` | Select the package format. Required. |
| `--version vX.Y.Z-R` | Install a specific upstream version and package revision instead of the latest. |
| `--yes` | Accept package manager confirmation prompts. Use with the piped commands above. |
| `--help` | Show usage. |

For example, to install a specific Debian package release:

```bash
curl -fsSL https://github.com/AkiraLyu/Okular-session/releases/latest/download/install.sh | bash -s -- --package deb --version v1.0.0-2 --yes
```

## Usage

```bash
okular-session                                      # Restore saved documents
okular-session /path/to/file.pdf /path/to/file.epub   # Open specific documents
```

All arguments are passed to Okular. Restoration occurs only when no arguments are supplied. To use the wrapper for desktop file opening, select **Okular Session** as the default application for the relevant document types.

## Configuration

The wrapper sources `${XDG_CONFIG_HOME:-$HOME/.config}/okular-session/config` if it exists. Use Bash variable assignments. Environment variables override values in the file; `OKULAR_SESSION_CONFIG_FILE` selects a different file.

| Variable | Default | Purpose |
| --- | --- | --- |
| `OKULAR_BIN` | `/usr/bin/okular` | Okular executable. |
| `OKULAR_SESSION_POLL_INTERVAL` | `1` | Scan interval in seconds. |
| `OKULAR_SESSION_EXTENSIONS` | `pdf epub md markdown txt` | Replace the tracked extensions. |
| `OKULAR_SESSION_EXTRA_EXTENSIONS` | Empty | Extend the defaults when no replacement list is set. |
| `OKULAR_SESSION_STATE_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/okular-session` | Session state directory. |
| `OKULAR_SESSION_FILE` | `$OKULAR_SESSION_STATE_DIR/last-pdfs.txt` | Saved document list for all tracked formats. |

Extension lists accept spaces, commas, colons, or semicolons. Leading dots are optional; matching is case-insensitive. Okular needs a backend for each format. If a custom session file is outside the state directory, create its parent directory first.

Example configuration:

```bash
OKULAR_SESSION_EXTRA_EXTENSIONS="djvu cbz"
OKULAR_SESSION_POLL_INTERVAL=2
```

## Session Behavior

- Existing local document arguments seed the initial session list.
- The wrapper scans file descriptors from the launched process and all processes named `okular`.
- When the launched process exits, it saves the last non-empty list. Launches with arguments merge eligible documents from the previous session.
- Restoration includes only existing local files with tracked extensions.

Capture depends on visible file descriptors. Closed documents may remain in the saved list, and documents may be missed. Remote URLs, page positions, and window layout are not saved.

## Packaging

Package versions use `X.Y.Z-R`: the upstream version and a positive package
revision. Increase `R` for packaging-only changes; restart at `1` for each new
upstream version. Release tags use `vX.Y.Z-R`.

Build as a regular user. Debian builds require Git, `dpkg-deb`, and Pandoc; Arch builds
require `base-devel`, Git, and `pandoc-cli`.

```bash
bash packaging/build.sh deb 1.0.0-2 dist/deb
bash packaging/build.sh arch 1.0.0-2 dist/arch
```

The timestamp defaults to the checked-out commit. Set it explicitly when building
outside Git. The Arch output includes a source archive and a standalone
`PKGBUILD` with its checksum. Keep both files together and run `makepkg -s` to
rebuild; published recipes can also download the source archive from the release.
The installed manual, `man okular-session`, is generated from this README.

Arch metadata records absolute build paths. Local builds use `.build/arch`;
`OKULAR_SESSION_BUILD_ROOT` overrides the root. CI uses `/build/okular-session`
in disposable containers. Reproducible builds require the same source timestamp,
paths, tool versions, and makepkg configuration. CI checks package metadata,
repeat-build checksums, installation, session restoration, revision upgrades,
and removal.

To release, update `packaging/changelog.in`, commit, and push a new `vX.Y.Z-R`
tag. The workflow uploads all assets to a draft before publishing. Existing
releases, including incomplete drafts, cause publication to fail. Inspect and
remove an incomplete draft before retrying. Use a new revision for an already
published version. GitHub immutable releases can additionally protect tags and
assets from changes outside the workflow.

## License

See [LICENSE](./LICENSE).
