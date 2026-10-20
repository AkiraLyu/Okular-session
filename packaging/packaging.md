# Packaging

Okular Session ships as a Debian package and an Arch package. This document describes how to build, verify, and release them. Run all commands from the repository root.

## Versioning

Package versions use `X.Y.Z-R`: the upstream version and a positive package revision. Increase `R` for packaging-only changes; restart at `1` for each new upstream version. Release tags use `vX.Y.Z-R`.

## Building

Build as a regular user. Debian builds require Git, `dpkg-deb`, and Pandoc; Arch builds require `base-devel`, Git, and `pandoc-cli`.

```bash
bash packaging/build.sh deb 1.0.0-2 dist/deb
bash packaging/build.sh arch 1.0.0-2 dist/arch
```

The timestamp defaults to the checked-out commit. Set it explicitly when building outside Git. The Arch output includes a source archive and a standalone `PKGBUILD` with its checksum. Keep both files together and run `makepkg -s` to rebuild; published recipes can also download the source archive from the release. The installed manual, `man okular-session`, is generated from `README.md`.

## Build Paths

Arch metadata records absolute build paths. Local builds use `.build/arch`; `OKULAR_SESSION_BUILD_ROOT` overrides the root. CI uses `/build/okular-session` in disposable containers. Reproducible builds require the same source timestamp, paths, tool versions, and makepkg configuration. The Packages workflow checks package metadata, repeat-build checksums, installation, session restoration, revision upgrades, and removal.

## Releasing

To release, update `packaging/changelog.in`, commit, and push a new `vX.Y.Z-R` tag. The Packages workflow uploads all assets to a draft before publishing. Existing releases, including incomplete drafts, cause publication to fail. Inspect and remove an incomplete draft before retrying. Use a new revision for an already published version. GitHub immutable releases can additionally protect tags and assets from changes outside the workflow.
