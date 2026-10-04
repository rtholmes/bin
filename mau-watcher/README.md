# mau-watcher

Silences the "Microsoft AutoUpdate" popup by force-quitting it within a
couple of seconds of it opening. Runs quietly in the background forever
(survives logout/restart), and can be paused when you actually want to run
updates.

No admin/sudo access is required — everything is installed under your own
home directory as a per-user LaunchAgent.

## Install

```
bash install-mau-watcher.sh
```

This copies the scripts to `~/Library/Application Support/mau-watcher/`,
installs and starts the background watcher, and adds `mau-pause`,
`mau-resume`, and `mau-status` as shell aliases in `~/.zshrc` (or
`~/.bash_profile` if your shell is bash), creating the file if needed. Open a
new terminal tab afterward, or run `source ~/.zshrc`, for the aliases to
become available. Running the installer again updates an installed copy.

From then on, "Microsoft AutoUpdate" will be killed automatically any time
it opens.

## Uninstall

```
bash uninstall-mau-watcher.sh
```

Stops the watcher and removes everything it installed, including the three
aliases from your shell profile.

## Commands

### `mau-pause`

Pauses the watcher. Run this before you sit down to do your Office
updates — Microsoft AutoUpdate will be left alone and behave normally
until you resume.

### `mau-resume`

Resumes the watcher after a pause. Microsoft AutoUpdate goes back to being
killed on sight.

### `mau-status`

Reports whether the watcher is running, whether it's currently paused or
active, and shows the last few times it killed something (from its log).
Useful for checking a pause actually took effect, or confirming the
watcher survived a restart.

## Files this installs

| File | Location | Purpose |
|---|---|---|
| `mau-watcher.sh` | `~/Library/Application Support/mau-watcher/` | The background loop that checks for and kills the app |
| `mau-pause`, `mau-resume`, `mau-status` | `~/Library/Application Support/mau-watcher/` | The commands above |
| `com.rtholmes.mauwatcher.plist` | `~/Library/LaunchAgents/` | Tells macOS to keep the watcher running at login |
| `paused` (created on demand) | `~/Library/Application Support/mau-watcher/` | Presence of this file pauses the watcher |
| `watcher.log` (created on demand) | `~/Library/Application Support/mau-watcher/` | Timestamped record of each kill |

## Notes

- This treats the symptom (closes the popup) rather than the cause (MAU's
  own background check schedule), so it keeps working even if a future
  Office update resets MAU's internal settings.
- If you're installing this from a shared folder for someone else, each
  person should run `install-mau-watcher.sh` themselves under their own
  account — it's a per-user LaunchAgent, not a system-wide one.
