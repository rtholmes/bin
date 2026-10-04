#!/bin/bash
# https://github.com/rtholmes/rthbin
# version 2026-10-04
#
# mau-watcher.sh
# Watches for the "Microsoft AutoUpdate" app and force-quits it the moment
# it appears, unless watching is paused. Runs forever (intended to be kept
# alive by a launchd LaunchAgent — see install-mau-watcher.sh).

APP_DIR="$HOME/Library/Application Support/mau-watcher"
PAUSE_FILE="$APP_DIR/paused"
LOG_FILE="$APP_DIR/watcher.log"
PROCESS_NAME="Microsoft AutoUpdate"

mkdir -p "$APP_DIR"

while true; do
    if [ ! -f "$PAUSE_FILE" ]; then
        if pgrep -x "$PROCESS_NAME" > /dev/null 2>&1; then
            pkill -x "$PROCESS_NAME"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - killed \"$PROCESS_NAME\"" >> "$LOG_FILE"
        fi
    fi
    sleep 2
done
