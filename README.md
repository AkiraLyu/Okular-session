> [!WARNING]
> This project was generated with AI assistance.

# Okular Session Wrapper

`okular-session.sh` adds a simple PDF session restore layer around the installed `/usr/bin/okular`.

Behavior:

- If you launch it without file arguments, it restores the last saved PDF list.
- If you launch it with file arguments, it opens those files directly and preserves the previous saved PDF list when writing the next snapshot.
- While Okular is running, it samples open PDF file descriptors using the requested `/proc/.../fd | grep '.pdf'` approach.
- When Okular exits, it writes the latest observed PDF set to `${XDG_STATE_HOME:-$HOME/.local/state}/okular-session/last-pdfs.txt`; file-argument launches merge that set with the previous saved list so desktop right-click opens do not discard earlier records.
- If no PDFs are open at exit after a no-argument session launch, it clears the saved session.

Usage:

```bash
~/okular-session/okular-session.sh
~/okular-session/okular-session.sh /path/to/file.pdf
```

The repository also includes [okular-session.desktop](./okular-session.desktop), and the AUR package installs it to `/usr/share/applications/okular-session.desktop`.

To make it your default launcher, point your desktop entry or shell alias to `~/okular-session/okular-session.sh` instead of `/usr/bin/okular`.

Notes:

- The wrapper restores only existing files.
- The primary snapshot path is equivalent to:

```bash
ls -l /proc/$(ps -C okular -o pid= | sed -e 's/\s//g')/fd | grep '.pdf'
```

- If multiple Okular processes make that PID expression ambiguous, the wrapper falls back to the PID it launched itself.
