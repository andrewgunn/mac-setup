# Mac Setup

Sets up a Mac the way I like it. `run.sh` does everything that can be scripted;
the [Manual steps](#manual-steps) at the bottom are the things that genuinely
can't be, each with the reason why.

## Getting started

1. Sign in to iCloud and the App Store (the `mas` entries in the `Brewfile`
   need it)
1. Clone this repository into `~/Code`. On a fresh Mac the `git` command
   triggers the Command Line Tools install dialog; accept it, wait, then clone
1. Run `./run.sh` from a normal terminal, not from inside an editor or agent
   shell, because sudo needs a real terminal to prompt on. It asks for your
   password once at the start and keeps the sudo ticket alive for the rest of
   the run, then for your git name and email, and an SSH key passphrase
1. Open a new terminal and work through the [Manual steps](#manual-steps)

`run.sh` is safe to re-run. Every step is idempotent, it only prompts for input
it doesn't already have, and it prints a summary of failed steps at the end
rather than stopping at the first one.

### What it does

- Installs Rosetta 2, Homebrew, and everything in the `Brewfile` (formulae,
  casks and App Store apps), and puts `brew` on the PATH of new shells
- Installs a LaunchAgent that upgrades formulae and casks in the background,
  leaving self-updating apps and root-installer casks alone
- Reinstalls the Xcode Command Line Tools if they have no package receipt
- Configures git from `config/gitconfig` (Beyond Compare as diff and merge
  tool, `git lg`, prune on fetch) and installs the global ignore file
- Installs the .NET global tools, Claude Code and Rokit
- Sets up Oh My Zsh with zsh-syntax-highlighting, and installs the
  powerlevel10k theme along with the finished `config/p10k.zsh`, so the
  interactive `p10k configure` wizard never has to be run
- Applies the system, Finder, Dock, trackpad and Spotlight defaults: dark
  mode, list view, folders first, tap to click, auto-hiding Dock, screenshots
  to Downloads, no auto-capitalisation
- Creates `~/Code`
- Configures Rectangle, Stats, SmoothScroll and iTerm
- Installs the VS Code and Cursor extensions
- Generates a GitHub SSH key and adds it to the keychain

`Taskfile.yml` has the maintenance jobs: `task lint` runs the CI checks,
`task check` confirms the `Brewfile` is fully installed, `task drift` lists
what's on this Mac but not in the repo, and `task autoupdate-status` shows the
background upgrade agent.

## Homebrew

`run.sh` installs a LaunchAgent, `com.andrewgunn.brew-autoupdate`, that runs
`config/brew-autoupdate.sh` every 12 hours and at login. Each run does
`brew update`, `brew upgrade --formula`, `brew upgrade --cask` and
`brew cleanup`, with two deliberate exceptions:

- **Casks that update themselves** (`auto_updates true`: Chrome, iTerm,
  Claude, 1Password, Cursor, Slack, Docker Desktop, and most of the rest of the
  `Brewfile`) are left alone. Homebrew 6 changed the default so `brew upgrade`
  replaces these whenever the cask is ahead of the installed app, and it does
  that by quitting the running app. The script sets
  `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS` to restore the old behaviour; the
  apps update themselves in their own time. `brew outdated --cask --greedy`
  shows what brew would have done.
- **Casks whose installer is a `.pkg`** (`SUDO_CASKS` in the script:
  `dotnet-sdk`, `naps2`, `wifiman`) are skipped, because they need root and a
  launchd job has nowhere to ask for a password. `run.sh` upgrades them
  instead, while you're at the keyboard. When adding a cask, check
  `brew info --cask <name>` for a `Pkg` artifact and add it to the list.
  Note that the .NET SDK upgrade uninstalls every `com.microsoft.dotnet.*`
  package first, including older runtimes.

This replaced the [domt4/autoupdate](https://github.com/DomT4/homebrew-autoupdate)
tap. That tap has no way to pass the environment variable above, and its
`--sudo` mode (a `pinentry-mac` password dialog with a 60-second timeout) was
the source of the background password prompts. `run.sh` removes the tap and its
agent if they're still installed.

Useful commands:

```
launchctl print gui/$UID/com.andrewgunn.brew-autoupdate   # state, run count, last exit code
tail -f ~/Library/Logs/brew-autoupdate.log                # watch a run, or see why one failed
launchctl kickstart gui/$UID/com.andrewgunn.brew-autoupdate   # run now
```

A failed run turns into a yellow warning the next time a login shell starts
(`~/.zprofile` reads the last exit status from launchd). The script also posts
a notification, but launchd jobs aren't guaranteed notification permission, so
don't rely on it.

To keep the `Brewfile` honest, `task drift` lists top-level formulae, casks,
.NET tools and VS Code extensions that are installed but not in the repo. Add
what you want to keep, uninstall the rest by name. The `Brewfile` has a few
commented-out entries (`pyenv`, `poetry`, `ta-lib`, `mongodb-atlas-cli`): those
are deliberately not installed on a new machine, so `drift` will keep listing
them until they're uninstalled here.

Avoid `brew bundle cleanup --force`. It proposes removing everything not
required by the `Brewfile`, which includes the dependencies of anything
installed manually outside it, so `libpng`, `freetype` and friends show up as
removable.

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

## Before wiping this Mac

`run.sh` recreates the software and settings. It does not recreate data, and a
few things live outside this repo on purpose. Check each before erasing:

- **Run `task drift`** and fold anything you want to keep into the repo
- **`~/Code`**: every repo pushed, no uncommitted work (`git status` in each)
- **SSH**: `run.sh` generates a new `~/.ssh/github` key on the new machine.
  Add it to GitHub afterwards and remove the old one. Copy any other keys in
  `~/.ssh` by hand if you still need them
- **Licences**: SmoothScroll (kept out of the repo deliberately), Beyond
  Compare, Rider (JetBrains account), Bambu Studio account
- **Signed-in apps** re-authenticate through their own flows: 1Password, Slack,
  Chrome profiles, Google Drive, Docker, `gh auth login`, `az login`, Claude
- **Claude Code**: `~/.claude` holds settings, memory and project notes. Copy
  it across if you want them back
- **Ollama models** in `~/.ollama` are large and re-downloadable; skip them
- **iTerm** keyboard mappings and **Rider** settings are manual steps below;
  Rider can also restore from JetBrains settings sync
- **Anything in `~/Downloads`**, since Finder and screenshots both default
  there

## Manual steps

Everything below resisted automation for a stated reason. If a reason stops
being true, move the step into `run.sh`.

### Finder sidebar

Add `~/Code` to the Finder sidebar by dragging it there. `run.sh` creates the
directory, but there's no maintained CLI for sidebar favourites — `mysides` was
the only real option and homebrew-cask disabled it on 2025-10-13.

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
