# Mac Setup

Sets up a Mac the way I like it. `run.sh` handles everything that can be
scripted; the rest of this file is the manual configuration that can't.

## Getting started

1. Open iTerm
    1. Make the code directory `mkdir ~/Code`
1. Open Finder
    1. Navigate to $USER
    1. Add `Code` directory to the Finder sidebar
1. Clone this repository into `~/Code`
1. Run `./run.sh`

`run.sh` is safe to re-run — every step is idempotent, and it only prompts for
your git name and email if they aren't already configured. It prints a summary
of any failed steps at the end rather than stopping at the first one.

It installs Homebrew and everything in the `Brewfile`, configures git, installs
the .NET tooling and Claude Code, sets up Oh My Zsh with powerlevel10k and
zsh-syntax-highlighting, and applies the Finder / Dock / Spotlight defaults.

Afterwards:

1. Open a new terminal
1. Run `p10k configure` to configure the powerlevel10k prompt
1. Work through the manual steps below

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
prompt from `pinentry-mac` via `--sudo`. That dialog times out after 60 seconds,
and a cask upgrade that loses its sudo step can fail *after* removing the old
app — leaving nothing installed. If you're not at the machine when a prompt
appears, reinstall from a terminal afterwards rather than assuming it worked.

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

## OS

1. Open System Settings
    1. Go to Accessibility
        1. Increase the pointer size (`run.sh` attempts this, but it needs Full
           Disk Access for your terminal, so it often has to be done by hand)

## 1Password

1. Open 1Password
    1. Go to Settings
    1. Go to General
        1. Disable `Keep 1Password in the menu bar`
        1. Disable the `Show 1Password` shortcut
        1. Change the `Show Quick Access` shortcut to ⇧⌘P

## Rectangle

1. Open Rectangle
    1. Go to Keyboard Shortcuts
        1. Disable all shortcuts
        1. Set the following shortcuts:
            1. Left Half `^⌥←`
            1. Right Half `^⌥→`
            1. Centre Half `^⌥↓`
            1. Maximise `^⌥↑`
            1. Centre `^⌥↩`
            1. First Third `^⌥1`
            1. Centre Third `^⌥2`
            1. Last Third `^⌥3`
            1. First Two Thirds `^⌥⇧←`
            1. Last Two Thirds `^⌥⇧→`
    1. Go to Settings
        1.  Enable `Launch on login`
        1.  Enable `Hide menu bar icon`

## SmoothScroll

1. Open SmoothScroll
    1. Disable `Show menu bar icon`
    1. Enable `Reverse Wheel Direction`

## Stats

1. Open Stats
    1. Go to Battery
        1. Disable
    1. Go to Settings
        1. Enable `Start at login`

## iTerm

1. Open iTerm
    1. Go to Settings
    1. Go to General
        1. Go to Closing
            1. Disable `Confirm closing multiple sessions`
            1. Disable `Confirm "Quit iTerm2 (⌘Q)"`
        1. Go to Window
            1. Disable `Native full screen windows`
    1. Go to Appearance
        1. Go Tabs
            1. Disable `Show tab bar in fullscreen`
        1. Go to Dimming
            1. Disable all 
    1. Go to Profiles
        1. Go to General
            1. Set split plane directory to current directory `Working Directory > Advanced Configuration > Edit > Working Directory for New Split Panes > Reuse previous session's directory`
        1. Go to Text
            1. Change the font to Fira Code `Font`
            1. Change the font weight to Retina `Font`
            1. Change the font size to 18 `Font`
            1. Enable ligatures `Font > Use ligatures`
        1. Go to Window
            1. Set screen to `Settings for New Windows > Screen > Main Screen`
        1. Go to Keys
            1. Go to Key Mappings
                1. Load natural text editing key mappings `Presets... > Natural Text Editing`
                2. Add a new key mapping `+`
                3. Send Hex Codes with the code `0x1B 0x08`

## Beyond Compare

`run.sh` configures git to use Beyond Compare as its diff and merge tool, but
that only works once its CLI tools are installed.

1. Open Beyond Compare
    1. Go to the `Beyond Compare` menu
        1. Choose `Install Command Line Tools` (installs `bcomp`)
1. Verify with `command -v bcomp`

## GitHub SSH

1. Open iTerm
    1. Create SSH directory `mkdir ~/.ssh`
    1. Change directory `cd ~/.ssh`
    1. Generate SSH key (use `github` as the file) `ssh-keygen -t ed25519 -C "github"`
    1. Create SSH configuration file `touch ~/.ssh/config`
    1. Update the SSH configuration file:
        ```
        Host *
        AddKeysToAgent yes
        UseKeychain yes
        IdentityFile ~/.ssh/github
        ```
    1. Add SSH key to Keychain `ssh-add --apple-use-keychain ~/.ssh/github`
    1. Add public key to GitHub `gh auth login`

## Rider

1. Open Rider
    1. Sign in with your JetBrains account `License` / `JetBrains Account`
    1. Go to Settings
        1. Go to Editor > Font
            1. Change the font to Fira Code
            1. Enable ligatures `Enable ligatures`
        1. Go to Version Control > Git
            1. Set SSH executable to `Native`

## Visual Studio Code

1. Install [Jupyter Extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)

## References

- [Mac setup for web development](https://www.robinwieruch.de/mac-setup-web-development/)
- [.NET MAUI development environment set up walkthrough](https://khalidabuhakmeh.com/dotnet-maui-development-environment-set-up-walkthrough)
