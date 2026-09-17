# Mac Setup

Sets up a Mac the way I like it. `run.sh` does everything that can be scripted.
The [manual steps](#manual-steps) at the end are what genuinely can't be, each
with the reason why.

## Getting started

1. Clone this repo into `~/Code`. On a fresh Mac, `git` first triggers the
   Command Line Tools dialog: accept it, wait, then clone
1. Run `./run.sh` from a real terminal (not an editor or agent shell: sudo
   needs one to prompt on). It asks for your password once, your git name
   and email, an SSH key passphrase, and whether to sign in to GitHub
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

- Rosetta 2, Homebrew, and everything in the `Brewfile`. Puts `brew` on the
  PATH of new shells. No App Store apps: Xcode is deliberately left out, since
  only MAUI builds for iOS or macOS need it (`brew 'mas'` plus
  `mas 'Xcode', id: 497799835` brings it back)
- A LaunchAgent that upgrades Homebrew packages in the background, leaving
  self-updating apps and `.pkg` installers alone ([details](#homebrew))
- Reinstalls the Command Line Tools if they have no package receipt
- Git from `config/gitconfig` (Beyond Compare as diff and merge tool,
  `git lg`, prune on fetch) plus the global ignore file
- .NET global tools, Claude Code, Rokit, GladiaFlow
- Oh My Zsh with zsh-syntax-highlighting and powerlevel10k, using the finished
  `config/p10k.zsh` so the `p10k configure` wizard never runs
- [Herdr](#herdr): its config, the state hooks for Claude Code, Cursor and
  opencode, zsh completions, and the skill that lets an agent drive Herdr itself
- [Neovim, lazygit and the shell around them](#neovim-lazygit-and-the-shell):
  LazyVim with its plugins installed up front, lazygit with delta diffs, and
  `z`, `^R`, `bat` and `eza` wired into zsh
- System defaults: dark mode, Finder list view with folders first, tap to
  click, auto-hiding Dock, screenshots to Downloads, no auto-capitalisation
- Rectangle shortcuts, Stats, SmoothScroll preferences and the Ghostty config
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

- **Self-updating casks** (`auto_updates true`: Chrome, Ghostty, Claude,
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

## Ghostty

The terminal is [Ghostty](https://ghostty.org), configured by `config/ghostty`:
Fira Code 18 with ligatures, no confirmation when a pane closes, Ghostty's own
fullscreen instead of a macOS Space, undimmed splits that open in the current
directory. Word-wise ⌥← / ⌥→ and ⌥⌫ are bound out of the box, so the key
mappings iTerm needed by hand are gone.

`run.sh` doesn't copy that file. It puts one line at the top of
`~/.config/ghostty/config`:

```
config-file = ~/Code/mac-setup/config/ghostty
```

so a `git pull` reaches this Mac, and anything written below that line here
stays put across runs and overrides the repo. ⌘, opens the local file; ⌘⇧,
reloads both. `ghostty +show-config` prints what's actually in force, and
`run.sh` runs `ghostty +validate-config` after writing the include.

The rest of that file is there for [Herdr](#herdr). ⌘T, ⌘W, ⌘K, ⌘E and ⌘⇧G are
unbound so they reach Herdr instead of the terminal — which means **⌘W no longer
closes a Ghostty surface**, so close the window instead. `macos-option-as-alt`
is set to `right` only: Herdr's ⌥↑ / ⌥↓ need a real Alt, while the left Option
still types `#` (⌥3) and `€` (⌥2) on a British layout. The palette is Atom One
Dark on `#1D1E27`, the exact background the Neovim theme paints, so the editor
sits flush in the terminal with no seam.

## Herdr

[Herdr](https://herdr.dev) is a terminal multiplexer built for coding agents:
one window, a sidebar of workspaces, tabs and panes, and a colour per agent
saying whether it's working, blocked or finished. It outlives the window — close
the terminal, reopen it, run `herdr`, and every agent is still there in the same
layout. The whole setup follows
[Datalumina's Herdr guide](https://learn.datalumina.com/docs/herdr).

`config/herdr.toml` is symlinked to `~/.config/herdr/config.toml`, because Herdr
has no include directive the way Ghostty and git do. That makes the repo file
the only copy — edits here and the ones Herdr writes itself (the onboarding
flag, `herdr config reset-keys`) land in the same file, so there's nothing to
keep in sync. `run.sh` checks it with `herdr config check` and reloads a running
server.

| | |
|---|---|
| New tab | ⌘T |
| Close tab | ⌘W |
| Go to workspace, tab or agent | ⌘K |
| Previous / next tab | ^← / ^→ |
| Previous / next workspace | ^↑ / ^↓ |
| Cycle panes | ⌥↑ / ⌥↓ |
| lazygit over this pane's folder | ⌘⇧G |
| Everything else | `§` then a key |

`§` is the prefix, the key left of 1 on a British keyboard; `§ c`, `§ v`,
`§ -`, `§ z`, `§ q` and the rest are Herdr's defaults.

`run.sh` installs the state hooks for the agents on this Mac — Claude Code,
Cursor and opencode — so the sidebar knows what each one is doing.
`herdr integration status` lists every agent Herdr supports and versions what's
installed, so an outdated hook is replaced on the next run. A hook is written
into the agent's own config directory, which doesn't exist until that agent has
run at least once — `run.sh` asks opencode its version first for exactly that
reason. An agent that still has no config directory is reported as something to
come back to rather than a failed step.

The **herdr skill** is what lets an agent drive Herdr itself: split a pane,
start a second agent in it, hand it work, read back what it said. `run.sh`
installs it at user level rather than per project, so every repo gets it:

```
npx skills add herdrdev/herdr --skill herdr \
  --agent claude-code --agent cursor --agent opencode --global --yes
```

It lands in `~/.agents/skills/herdr`, symlinked to `~/.claude/skills/herdr` for
Claude Code and read in place by Cursor and OpenCode. `--yes` and the explicit
`--agent` list matter: without them it asks about scope and agents, which would
stall an unattended run. `npx skills list -g` shows what's installed. The skill
only activates inside a Herdr pane (it looks for `HERDR_ENV=1`), so it costs
nothing anywhere else. If that npm package ever moves, `herdr --skill` prints
the same instructions to paste into an agent's global instructions instead.

Not installed, because it's one plugin and a 200MB toolchain:
`brew install go && herdr plugin install kryptamine/herdr-auto-title`, which
names each tab after what the agent in it is doing.

## Neovim, lazygit and the shell

The three tools that live inside Herdr's panes. Each is symlinked from `config/`
for the same reason as Herdr: none of them has an include directive.

- **Neovim** (`config/nvim` → `~/.config/nvim`) is
  [LazyVim](https://www.lazyvim.org) set up to be read like VS Code rather than
  driven like vim: neo-tree open on the left, single click previews a file in
  one reused tab, double click or Enter pins it, ^click jumps to a definition,
  `^P` is Quick Open and `/` searches the project (`g/` searches the file).
  Atom One Dark on Ghostty's background. The language servers are C#,
  TypeScript, Python, JSON, TOML and Markdown — the guide's list, with Rust
  swapped for `lang.dotnet`, since Koala2 is 3,000 C# files and no Rust. Note
  omnisharp takes about 20 seconds to load a solution that size before
  ^click starts working. `run.sh` runs
  `nvim --headless "+Lazy! sync" +qa` so the first launch isn't a two-minute
  wait; `:Lazy sync` updates after that. `tree-sitter-cli` is in the `Brewfile`
  because nvim-treesitter requires it — from Homebrew it's upgraded with
  everything else instead of mason keeping a second copy. Mason still fetches
  the language servers and formatters itself, in the background, the first time
  a file of that language is opened; `:Mason` shows where it's got to. LazyVim
  writes its `lazy-lock.json` into `config/nvim`, which is the repo, so plugin
  versions are committed with everything else.
- **lazygit** (`config/lazygit.yml` → `~/Library/Application Support/lazygit/`)
  with [delta](https://github.com/dandavison/delta) rendering the diffs, no
  command log or status bar, and a colour per branch prefix so `claude/`,
  `cursor/` and `feat/` branches are distinguishable at a glance. `b` from the
  files panel checks out a branch. ⌘⇧G opens it as a Herdr popup over whatever
  folder the current pane is in.
- **The shell** (`config/shell.zsh`, sourced from `~/.zshrc`): `z koala2` jumps
  to a folder by name and `zi` picks one with fzf ([zoxide](https://github.com/ajeetdsouza/zoxide)),
  `^R` searches history and `^T` files, `ls`/`ll`/`tree` are `eza` and `cat` is
  `bat`. Both drop back to plain output when piped, so nothing scripted
  changes.

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
  Drive, Docker, `gh auth login`, `az login`, Claude, and a Gladia API key
- **`~/.claude`** holds Claude Code settings, memory and project notes
- **`~/.ollama`** models are large and re-downloadable; skip them
- **`~/Downloads`**, since Finder and screenshots both land there

## Manual steps

Each of these resisted automation for a stated reason. If the reason stops
being true, move it into `run.sh`. The end of a run lists them, ticking the
ones it can detect.

### GladiaFlow permissions and API key

[GladiaFlow](https://github.com/gladiaio/gladiaflow) itself is installed by
`run.sh`: there's no Homebrew cask, but its releases are on GitHub, so the
universal `.dmg` is fetched, mounted and copied to `/Applications`, and a later
run replaces it when the release tag moves past the installed version. It's
notarized under Gladia's Developer ID, so it opens without a Gatekeeper prompt.

What's left can't be scripted: open it once to grant Microphone and
Accessibility, and paste an API key from [app.gladia.io](https://app.gladia.io).
The app is free and MIT-licensed; transcription is billed against that key.
It does the same job as Wispr Flow, which is still in the `Brewfile` — drop
whichever one loses.

### Finder sidebar

Drag `~/Code` into the sidebar. There's no maintained CLI for sidebar items:
`mysides` was the only option and homebrew-cask disabled it on 2025-10-13.

### 1Password

Its preferences aren't exposed through `defaults`, so in Settings > General:
disable `Keep 1Password in the menu bar`, disable the `Show 1Password`
shortcut, and set `Show Quick Access` to ⇧⌘P.

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

- [Herdr, Ghostty, Neovim and lazygit](https://learn.datalumina.com/docs/herdr),
  the guide this terminal setup follows
- [Mac setup for web development](https://www.robinwieruch.de/mac-setup-web-development/)
- [.NET MAUI development environment set up walkthrough](https://khalidabuhakmeh.com/dotnet-maui-development-environment-set-up-walkthrough)
