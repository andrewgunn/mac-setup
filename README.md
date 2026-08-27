# Mac Setup

Sets up a Mac the way I like it. `run.sh` does everything that can be scripted;
the [Manual steps](#manual-steps) at the bottom are the things that genuinely
can't be, each with the reason why.

## Getting started

1. Clone this repository into `~/Code`
1. Run `./run.sh`
1. Open a new terminal and work through the [Manual steps](#manual-steps)

`run.sh` is safe to re-run. Every step is idempotent, it only prompts for input
it doesn't already have, and it prints a summary of failed steps at the end
rather than stopping at the first one.

### What it does

- Installs Homebrew and everything in the `Brewfile`
- Sets up background auto-updates for formulae and casks
- Reinstalls the Xcode Command Line Tools if they have no package receipt
- Configures git, including Beyond Compare as the diff and merge tool
- Installs the .NET tooling and Claude Code
- Sets up Oh My Zsh with powerlevel10k and zsh-syntax-highlighting
- Applies the Finder, Dock and Spotlight defaults
- Creates `~/Code` and adds it to the Finder sidebar
- Configures Rectangle, Stats, SmoothScroll and iTerm
- Installs the VS Code Jupyter extension
- Generates a GitHub SSH key and adds it to the keychain

## Homebrew

`run.sh` sets up [autoupdate](https://github.com/DomT4/homebrew-autoupdate) to
upgrade formulae and casks in the background every 12 hours:

```
brew autoupdate start 12h --upgrade --cleanup --immediate --sudo --notify-on-error
```

`--upgrade` is the important flag — without it, autoupdate only refreshes
metadata and never actually installs anything. `--sudo` opens a GUI password
prompt for casks that need root (needs `pinentry-mac`, which is in the
`Brewfile`).

Useful commands:

- `brew autoupdate status` — confirm it's running and check which flags are set
- `brew autoupdate logs --follow` — watch a run, or find out why one failed
- `brew outdated --cask --greedy` — casks with their own updaters (Chrome,
  Slack, Spotify, Cursor, VS Code) update themselves and are deliberately left
  alone. Add `--greedy` to the `start` command if you'd rather brew own them,
  at the cost of reinstalling apps while they're running.

Casks that need root (Docker Desktop, the .NET SDK, Elgato) get their password
prompt from `pinentry-mac`. Two warnings from experience:

- The prompt times out after 60 seconds, and a cask upgrade that loses its sudo
  step can fail *after* removing the old app, leaving nothing installed. If you
  weren't at the machine when a prompt appeared, check the app is still there.
- The tap generates its askpass with `OPTION allow-external-cache`, so pinentry
  can hand sudo a stale keychain value instead of what you typed. That shows up
  as the password dialog reappearing immediately after you submit it. Install
  those casks by hand when that happens.

To sync the `Brewfile` with what's actually installed:

```
brew bundle dump --force --describe --file=Brewfile   # rewrite from what's installed
brew bundle cleanup --file=Brewfile                   # list what's installed but unlisted
```

Read the `cleanup` output before acting on it, and don't reach for `--force`
casually. It proposes removing everything not required by the `Brewfile` —
which includes the dependencies of anything installed manually outside it, so
`libpng`, `freetype` and friends show up as removable. Uninstall the handful
you actually want gone by name instead.

## Command Line Tools

`brew doctor` may report "A newer Command Line Tools release is available" while
System Settings > Software Update shows nothing to install. That usually means
the CLT install has no package receipt:

```
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables
```

If that says "No receipt", Software Update has no record of CLT and cannot
update it, no matter what your update settings say.

`run.sh` detects and fixes this: when the directory exists but has no receipt it
removes it and reinstalls headlessly via `softwareupdate`, which needs sudo and
downloads roughly 1GB. When the receipt is present the whole step is skipped, so
re-running costs nothing.

After that it's maintained by Software Update along with everything else. There
is no separate auto-update toggle for CLT — it rides the system settings below,
all of which are on by default and worth confirming with:

```
defaults read /Library/Preferences/com.apple.SoftwareUpdate
```

`AutomaticCheckEnabled`, `AutomaticDownload`, `AutomaticallyInstallMacOSUpdates`,
`ConfigDataInstall` and `CriticalUpdateInstall` should all be enabled.

macOS releases themselves are deliberately left out of `run.sh`. Installing one
reboots the machine, which would abandon the rest of the script, so never
automate `softwareupdate --install --all`. Let the settings above install them,
and check Software Update by hand if one appears stuck.

## Manual steps

Everything below resisted automation for a stated reason. If a reason stops
being true, move the step into `run.sh`.

### powerlevel10k

Run `p10k configure`. It's an interactive wizard with no unattended mode; the
theme itself is already activated in `.zshrc` by `run.sh`.

### GitHub

Run `gh auth login`. `run.sh` has already generated `~/.ssh/github`, written
`~/.ssh/config` and added the key to the keychain — this step is the browser
OAuth flow, which can't be scripted.

### 1Password

Its preferences aren't exposed through `defaults` (the domain holds only generic
Cocoa keys), so these have to be clicked:

1. Open 1Password
    1. Go to Settings
    1. Go to General
        1. Disable `Keep 1Password in the menu bar`
        1. Disable the `Show 1Password` shortcut
        1. Change the `Show Quick Access` shortcut to ⇧⌘P

### iTerm

`run.sh` sets the closing, fullscreen and dimming preferences, and the Fira Code
18 font with ligatures. The rest live deep inside the profile's keyboard map,
where scripted edits are fragile enough not to be worth it:

1. Open iTerm
    1. Go to Settings > Profiles
        1. Go to General
            1. Set split plane directory to current directory `Working Directory > Advanced Configuration > Edit > Working Directory for New Split Panes > Reuse previous session's directory`
        1. Go to Window
            1. Set screen to `Settings for New Windows > Screen > Main Screen`
        1. Go to Keys > Key Mappings
            1. Load natural text editing key mappings `Presets... > Natural Text Editing`
            1. Add a new key mapping `+`
            1. Send Hex Codes with the code `0x1B 0x08`

Note that iTerm rewrites its plist on quit, so `run.sh` skips this section
entirely if iTerm is running. Run it from Terminal.app for a clean first setup.

### Rider

Signing in is interactive, and the editor settings live in version-numbered
config directories that move with each release:

1. Open Rider
    1. Sign in with your JetBrains account `License` / `JetBrains Account`
    1. Go to Settings
        1. Go to Editor > Font
            1. Change the font to Fira Code
            1. Enable ligatures `Enable ligatures`
        1. Go to Version Control > Git
            1. Set SSH executable to `Native`

### Pointer size

`run.sh` attempts this, but `com.apple.universalaccess` is protected by TCC and
the write silently fails unless your terminal has Full Disk Access. If the
pointer is still small, set it in System Settings > Accessibility > Display.

### SmoothScroll licence

Kept outside this repo deliberately — the repo is public, and the licence keys
and subscription ID live in `com.galambalazs.SmoothScroll`. `run.sh` writes only
the two behavioural keys and never reads or touches the licence.

## References

- [Mac setup for web development](https://www.robinwieruch.de/mac-setup-web-development/)
- [.NET MAUI development environment set up walkthrough](https://khalidabuhakmeh.com/dotnet-maui-development-environment-set-up-walkthrough)
