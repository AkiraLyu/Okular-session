> [!WARNING]
> This project was generated with AI assistance.

# Okular Session Wrapper

`okular-session.sh` adds a simple document session restore layer around the installed `/usr/bin/okular`.

Behavior:

- If you launch it without file arguments, it restores the last saved document list.
- If you launch it with file arguments, it opens those files directly and preserves the previous saved document list when writing the next snapshot.
- While Okular is running, it samples open file descriptors from `/proc/.../fd` and keeps paths whose extension is supported by the wrapper configuration.
- When Okular exits, it writes the latest observed document set to `${XDG_STATE_HOME:-$HOME/.local/state}/okular-session/last-pdfs.txt`; file-argument launches merge that set with the previous saved list so desktop right-click opens do not discard earlier records.
- If no supported documents are open at exit after a no-argument session launch, it clears the saved session.

Supported extensions default to `pdf`, `epub`, `md`, `markdown`, and `txt`. This only controls session tracking; Okular still needs the matching backend installed to open each format.

Configuration:

- Persistent local configuration is loaded from `${XDG_CONFIG_HOME:-$HOME/.config}/okular-session/config` if that file already exists. The wrapper does not create this file automatically.
- `OKULAR_SESSION_CONFIG_FILE` points to a different config file path.
- Environment variables override values from the local config file.
- Config files use shell-compatible variable assignments.
- `OKULAR_SESSION_EXTRA_EXTENSIONS` appends more extensions to the default list.
- `OKULAR_SESSION_EXTENSIONS` replaces the default list entirely.
- `OKULAR_SESSION_STATE_DIR` changes the directory used for saved session state.
- Extension lists may be separated by spaces, commas, colons, or semicolons, and leading dots are optional.

Examples:

```bash
OKULAR_SESSION_EXTRA_EXTENSIONS="djvu cbz" okular-session
OKULAR_SESSION_EXTENSIONS="pdf,epub,txt" okular-session
```

Example local config:

```bash
# ~/.config/okular-session/config
OKULAR_SESSION_EXTRA_EXTENSIONS="djvu cbz"
OKULAR_SESSION_POLL_INTERVAL=2
```

Usage:

```bash
~/okular-session/okular-session.sh
~/okular-session/okular-session.sh /path/to/file.pdf
~/okular-session/okular-session.sh /path/to/file.epub
```

The repository also includes [okular-session.desktop](./okular-session.desktop), and the AUR package installs it to `/usr/share/applications/okular-session.desktop`.

To make it your default launcher, point your desktop entry or shell alias to `~/okular-session/okular-session.sh` instead of `/usr/bin/okular`.

Notes:

- The wrapper restores only existing files.
- The primary snapshot path reads Okular file descriptors from:

```bash
/proc/$(ps -C okular -o pid= | sed -e 's/\s//g')/fd
```

- If multiple Okular processes make that PID expression ambiguous, the wrapper falls back to the PID it launched itself.
