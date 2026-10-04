#!/bin/bash
# https://github.com/rtholmes/rthbin
# version 2026-09-20
#
# Installs the Microsoft AutoUpdate watcher for the current user.
# No sudo required -- everything lives under your home directory.
#
# Usage: cd into the folder containing these files, then run:
#   bash install-mau-watcher.sh
#
# Running it again updates an installed copy in place.

set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/Library/Application Support/mau-watcher"
AGENTS_DIR="$HOME/Library/LaunchAgents"
SCRIPT_PATH="$APP_DIR/mau-watcher.sh"
LOG_PATH="$APP_DIR/watcher.log"
PLIST_PATH="$AGENTS_DIR/com.rtholmes.mauwatcher.plist"

mkdir -p "$APP_DIR" "$AGENTS_DIR"

# Stop a watcher that is already running before replacing its script
launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Copy the scripts into place
cp "$SRC_DIR/mau-watcher.sh" "$APP_DIR/mau-watcher.sh"
cp "$SRC_DIR/mau-pause" "$APP_DIR/mau-pause"
cp "$SRC_DIR/mau-resume" "$APP_DIR/mau-resume"
cp "$SRC_DIR/mau-status" "$APP_DIR/mau-status"
chmod +x "$APP_DIR/mau-watcher.sh" "$APP_DIR/mau-pause" "$APP_DIR/mau-resume" "$APP_DIR/mau-status"

# Fill in the plist template with real paths and install it
sed -e "s#__SCRIPT_PATH__#$SCRIPT_PATH#" \
    -e "s#__LOG_PATH__#$LOG_PATH#" \
    "$SRC_DIR/com.rtholmes.mauwatcher.plist" > "$PLIST_PATH"

# Start the LaunchAgent
launchctl load "$PLIST_PATH"

# Add convenience aliases to the profile your shell reads, if not already
# there. zsh is the default shell on macOS and reads ~/.zshrc; bash reads
# ~/.bash_profile for the login shells Terminal opens. The file is created if
# it does not exist yet.
case "${SHELL:-}" in
    */zsh)  PROFILE="$HOME/.zshrc" ;;
    */bash) PROFILE="$HOME/.bash_profile" ;;
    *)      PROFILE="" ;;
esac
MARKER="# mau-watcher aliases"
if [ -z "$PROFILE" ]; then
    echo "Your shell (${SHELL:-unknown}) is not zsh or bash, so no aliases were added."
    echo "The mau-pause, mau-resume, and mau-status commands are in:"
    echo "  $APP_DIR"
elif ! grep -q "$MARKER" "$PROFILE" 2>/dev/null; then
    {
        echo ""
        echo "$MARKER"
        echo "alias mau-pause='\"$APP_DIR/mau-pause\"'"
        echo "alias mau-resume='\"$APP_DIR/mau-resume\"'"
        echo "alias mau-status='\"$APP_DIR/mau-status\"'"
    } >> "$PROFILE"
    echo "Added mau-pause / mau-resume / mau-status aliases to $PROFILE"
    echo "(open a new terminal tab, or run: source $PROFILE)"
fi

echo ""
echo "Installed and running. Microsoft AutoUpdate will be force-quit within a couple"
echo "of seconds of it opening, from now on -- including after you log out and back in."
echo ""
echo "When you want to let Office update itself, run:  mau-pause"
echo "When you're done, run:                           mau-resume"
echo "To check what's going on, run:                   mau-status"
