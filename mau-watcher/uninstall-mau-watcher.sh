#!/bin/bash
# https://github.com/rtholmes/rthbin
# version 2026-10-04
#
# Removes the Microsoft AutoUpdate watcher completely, including the aliases
# the installer added to your shell profile.

APP_DIR="$HOME/Library/Application Support/mau-watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/com.rtholmes.mauwatcher.plist"
MARKER="# mau-watcher aliases"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -rf "$APP_DIR"

# Remove the alias block from whichever profile the installer wrote it to:
# the marker line, the alias lines under it, and the blank line above it.
removed=0
for PROFILE in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$PROFILE" ] && grep -q "$MARKER" "$PROFILE" || continue
    TMP="$(mktemp)"
    awk -v marker="$MARKER" '
        { lines[n++] = $0 }
        END {
            for (i = 0; i < n; i++) {
                if (lines[i] == marker) {
                    if (kept > 0 && out[kept - 1] == "") kept--
                    while (i + 1 < n && lines[i + 1] ~ /^alias mau-(pause|resume|status)=/) i++
                    continue
                }
                out[kept++] = lines[i]
            }
            for (i = 0; i < kept; i++) print out[i]
        }' "$PROFILE" > "$TMP" && cat "$TMP" > "$PROFILE"
    rm -f "$TMP"
    echo "Removed the mau-watcher aliases from $PROFILE"
    removed=1
done

echo "mau-watcher stopped and removed."
if [ "$removed" -eq 1 ]; then
    echo "(Open a new terminal tab for the mau-pause / mau-resume / mau-status aliases to go away.)"
fi
