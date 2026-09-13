# Mac Setup

Sets up a Mac the way I like it. `run.sh` does everything that can be scripted.
The [manual steps](#manual-steps) at the end are what genuinely can't be, each
with the reason why.

## Getting started

1. Clone this repo into `~/Code`. On a fresh Mac, `git` first triggers the
   Command Line Tools dialog: accept it, wait, then clone
1. Run `./run.sh` from a real terminal (not an editor or agent shell: sudo
   needs one to prompt on). It asks for your password once, whether the App
   Store is signed in (Xcode comes from there), your git name and
   email, an SSH key passphrase, and whether to sign in to GitHub
1. Open a new terminal and work through the [manual steps](#manual-steps)

Safe to re-run: every step is idempotent, prompts are skipped once answered,
and failures are collected and listed at the end rather than stopping the run.

While it runs, each step shows a spinner with its last few lines of output,
then folds into one tick or cross with the time taken. Settings report what
actually changed, so a re-run reads "all already set". Long or interactive
steps (downloads, sudo, `ssh-keygen`) stay live. It ends with a summary, a
chart of where the time went, and a checklist of what's still manual. Runs
over two minutes also ring the bell and post a notification.

- `./run.sh -v` streams every step's output instead of folding it
- `NO_COLOR=1`, or piping the output, switches to plain ASCII
- everything also goes to `~/Library/Logs/mac-setup/<timestamp>.log`

### What it does

- Rosetta 2, Homebrew, and everything in the `Brewfile`: formulae, casks and
  App Store apps. Puts `brew` on the PATH of new shells
- A LaunchAgent that upgrades Homebrew packages in the background, leaving
  self-updating apps and `.pkg` installers alone ([details](#homebrew))
- Reinstalls the Command Line Tools if they have no package receipt
- Git from `config/gitconfig` (Beyond Compare as diff and merge tool,
  `git lg`, prune on fetch) plus the global ignore file
- .NET global tools, Claude Code, Rokit
- Oh My Zsh with zsh-syntax-highlighting and powerlevel10k, using the finished
  `config/p10k.zsh` so the `p10k configure` wizard never runs
- System defaults: dark mode, Finder list view with folders first, tap to
  click, auto-hiding Dock, screenshots to Downloads, no auto-capitalisation
- Rectangle shortcuts, Stats, SmoothScroll and iTerm preferences
- VS Code and Cursor extensions
- A GitHub SSH key added to the agent and keychain, `gh auth login` in the
  browser, and the key uploaded to the account

Maintenance lives in `Taskfile.yml`: `task lint` (the CI checks),
`task check` (is the `Brewfile` fully installed?), `task drift` (what's on this
Mac but not in the repo?) and `task autoupdate-status`.

## Homebrew

A LaunchAgent, `com.andrewgunn.brew-autoupdate`, runs
`config/brew-autoupdate.sh` every 12 hours and at login: `brew update`,
`brew upgrade --formula`, `brew upgrade --cask`, `brew cleanup`. Two things are
deliberately skipped:

- **Self-updating casks** (`auto_updates true`: Chrome, iTerm, Claude,
  1Password, Cursor, Slack, Docker Desktop and most of the `Brewfile`).
  Homebrew 6 upgrades these by default whenever the cask is ahead of the app,
  quitting the running app to do it. `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS`
  restores the old behaviour and the apps update themselves.
- **`.pkg` casks** (`SUDO_CASKS` in the script: `dotnet-sdk`, `naps2`,
  `wifiman`). They need root, and a launchd job has nowhere to ask for a
  password, so `run.sh` upgrades them while you're at the keyboard. CI fails if
  a `.pkg` cask is added without joining that list. Note the .NET SDK upgrade
  removes every `com.microsoft.dotnet.*` package first, older runtimes included.

This replaced the domt4/autoupdate tap, which couldn't set that variable and
whose `--sudo` password dialog was the source of the background prompts.
`run.sh` removes the tap if it's still installed.

```
task autoupdate-status                                          # state, last exit, recent log
launchctl kickstart gui/$UID/com.andrewgunn.brew-autoupdate     # run now
tail -f ~/Library/Logs/brew-autoupdate.log
```

A failed run prints a yellow warning at the next login shell (`~/.zprofile`
reads launchd's last exit status). It also posts a notification, but launchd
jobs aren't guaranteed permission for that, so don't rely on it.

`task drift` keeps the `Brewfile` honest: it lists formulae, casks, .NET tools
and VS Code extensions that are installed but not in the repo. The commented-out
entries (`pyenv`, `poetry`, `ta-lib`, `mongodb-atlas-cli`) are deliberately not
installed on a new machine, so `drift` lists them until they're uninstalled
here. Avoid `brew bundle cleanup --force`: it also removes the dependencies of
anything installed outside the `Brewfile`.

## Command Line Tools

If `brew doctor` says a newer Command Line Tools release is available while
Software Update shows nothing, the install probably has no package receipt:

```
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables
```

Without a receipt Software Update can't see them and never updates them.
`run.sh` handles this: no receipt means it removes the directory and reinstalls
headlessly through `softwareupdate` (about 1GB); with a receipt the step is a
no-op. After that they update with everything else, governed by the settings in
`defaults read /Library/Preferences/com.apple.SoftwareUpdate`, which should all
be enabled.

macOS releases are deliberately not installed by `run.sh`: they reboot the
machine, which would abandon the rest of the script.

## Before wiping this Mac

`run.sh` recreates software and settings, not data. Check before erasing:

- **`task drift`**, and fold anything you want to keep into the repo
- **`~/Code`**: everything pushed, no uncommitted work
- **SSH**: the new machine gets a new `~/.ssh/github` key, which `run.sh`
  uploads to GitHub. Remove the old one there, and copy any other keys by hand
- **Licences**: SmoothScroll (kept out of the repo), Beyond Compare, Rider,
  Bambu Studio
- **Sign-ins** happen through each app: 1Password, Slack, Chrome, Google
  Drive, Docker, `gh auth login`, `az login`, Claude
- **`~/.claude`** holds Claude Code settings, memory and project notes
- **`~/.ollama`** models are large and re-downloadable; skip them
- **`~/Downloads`**, since Finder and screenshots both land there

## Manual steps

Each of these resisted automation for a stated reason. If the reason stops
being true, move it into `run.sh`. The end of a run lists them, ticking the
ones it can detect.

### Finder sidebar

Drag `~/Code` into the sidebar. There's no maintained CLI for sidebar items:
`mysides` was the only option and homebrew-cask disabled it on 2025-10-13.

### 1Password

Its preferences aren't exposed through `defaults`, so in Settings > General:
disable `Keep 1Password in the menu bar`, disable the `Show 1Password`
shortcut, and set `Show Quick Access` to ⇧⌘P.

### iTerm

`run.sh` sets the quit, fullscreen and dimming preferences and the Fira Code 18
font with ligatures. The rest live in the profile's keyboard map, where scripted
edits are too fragile to be worth it. In Settings > Profiles:

1. General > Working Directory > Advanced Configuration > Edit: set
   `Working Directory for New Split Panes` to `Reuse previous session's directory`
1. Window > Settings for New Windows > Screen: `Main Screen`
1. Keys > Key Mappings: `Presets… > Natural Text Editing`, then add a mapping
   that sends the hex codes `0x1B 0x08`

iTerm rewrites its plist on quit, so `run.sh` skips this section while iTerm is
running. Use Terminal.app for a first setup.

### Rider

Signing in is interactive and the settings live in version-numbered directories
that move with each release. Sign in with the JetBrains account, then in
Settings: Editor > Font to Fira Code with ligatures, and Version Control > Git
SSH executable to `Native`. JetBrains settings sync can restore the rest.

### Pointer size

`run.sh` writes it, but `com.apple.universalaccess` is protected and the write
silently fails unless the terminal has Full Disk Access. If the pointer is still
small: System Settings > Accessibility > Display.

### SmoothScroll licence

The repo is public and the licence lives in `com.galambalazs.SmoothScroll`, so
`run.sh` writes only the three behavioural keys and never touches it.

## References

- [Mac setup for web development](https://www.robinwieruch.de/mac-setup-web-development/)
- [.NET MAUI development environment set up walkthrough](https://khalidabuhakmeh.com/dotnet-maui-development-environment-set-up-walkthrough)
