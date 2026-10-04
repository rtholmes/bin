# rthbin

Small command-line tools I use every day, shared in case they are useful to
you too. Everything here is under the MIT license.

| Tool | What it does | Runs on |
|---|---|---|
| [`repoStatus`](repoStatus) | Reports, pulls, or pushes every git repo in a folder at once | macOS, Linux |
| [`o`](o) | Opens an app by a short alias: `o vsc .`, `o chrome example.com` | macOS |
| [`fh`](fh) | Opens a folder in Finder: `fh`, `fh ~/Downloads` | macOS |
| [`mau-watcher/`](mau-watcher/) | Stops the Microsoft AutoUpdate popup from appearing | macOS |

## Install

Clone this repo and put it on your `PATH`:

```sh
git clone https://github.com/rtholmes/rthbin.git ~/rthbin
echo 'export PATH="$HOME/rthbin:$PATH"' >> ~/.zshrc
```

Then open a new terminal tab. The one exception is `mau-watcher`, which runs
in the background and so has its own installer; see
[its README](mau-watcher/README.md).

## repoStatus

Run it inside a git repo and it works on that repo. Run it in a folder of
repos, such as `~/dev`, and it works on every repo directly inside it.

```
repoStatus              status of each repo, from what git already knows
repoStatus -f           fetch first, so the ahead and behind counts are current
repoStatus pull         fast-forward each repo that has an upstream
repoStatus push         push each repo with commits its upstream does not have
repoStatus help         everything else
```

It needs git 2.11 or newer. Fetches, pulls, and pushes run a few at a time,
nothing ever prompts for a password, and a host that does not answer is
reported while the others carry on. The smoke test,
[`test/repoStatus-test.sh`](test/repoStatus-test.sh), builds throwaway repos
for every situation it reports and checks the output; run it after changing
the script.

## o

`o` opens an app by a short alias, or by its full name, and passes anything
else on to `open`:

```
o vsc .                       the current folder in Visual Studio Code
o chrome https://example.com  that page in Chrome
o Preview report.pdf          any app, by name
o -l                          list the aliases
```

Neither aliases nor app names are case sensitive, so `o preview` opens
Preview; aliases are only for shortening a name. `vsc` and `chrome` are built
in; add your own in `~/.zshrc` as `name=App` pairs separated by semicolons:

```sh
export O_ALIASES="ff=Firefox;slack=Slack;word=Microsoft Word"
```

[`test/o-test.sh`](test/o-test.sh) checks `o` and `fh` against a stand-in
for `open`, so running it opens nothing.

## fh

`fh` opens the current folder in Finder, and `fh <folder>` opens that one.
