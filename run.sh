#!/bin/bash
# Sets up a Mac from scratch. Safe to re-run: every step is idempotent and
# nothing prompts for input it already has.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=()

# This script is interactive, so sudo should prompt in the terminal. A stale
# askpass helper in the environment (the old autoupdate tap left one behind)
# makes every sudo fail with "no password was provided" instead.
unset SUDO_ASKPASS

# Run a step, but keep going if it fails — a missing cask shouldn't abandon the
# rest of the setup. Anything that failed is listed again at the end.
step() {
  local label="$1"
  shift
  echo
  echo "==> $label"
  if ! "$@"; then
    echo "!!! $label failed"
    FAILED+=("$label")
    return 1
  fi
}

# Append a line to a file unless a line matching the given pattern is already
# there. The pattern is matched loosely so a previously-expanded form of the
# same line (e.g. $HOME already resolved to /Users/you) still counts as present.
append_once() {
  local file="$1" pattern="$2" line="$3"
  [ -f "$file" ] && grep -q "$pattern" "$file" && return 0
  printf '%s\n' "$line" >> "$file"
  echo "    added to ${file/#$HOME/~}: $line"
}

# Append a block read from stdin unless the marker is already in the file.
append_block_once() {
  local file="$1" marker="$2"
  if [ -f "$file" ] && grep -qF "$marker" "$file"; then
    cat >/dev/null   # drain stdin so the caller's heredoc doesn't break
    return 0
  fi
  printf '\n' >> "$file"
  cat >> "$file"
  echo "    added block to ${file/#$HOME/~}: $marker"
}

# ------------------------------------------------------------------------------
# Finder
# ------------------------------------------------------------------------------
echo "==> Finder and Dock"
chflags nohidden ~/Library
defaults write com.apple.finder AppleShowAllFiles YES
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string 'Nlsv'   # list view
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'   # search the current folder
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
# Open new Finder windows in Downloads
defaults write com.apple.finder NewWindowTarget -string 'PfLo'
defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/Downloads/"
# Screenshots go to Downloads too, not the Desktop
defaults write com.apple.screencapture location -string "$HOME/Downloads"
# Finder and Dock are restarted at the very end, not here: relaunching Finder
# opens a window that steals keyboard focus, and doing that before the sudo
# prompt below swallows part of the password being typed.

# Auto-hide the Dock, show/hide it instantly, no recent apps, slightly smaller
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-time-modifier -int 0
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock tilesize -int 52

# System: dark mode, always show scroll bars, show file extensions, and stop
# macOS rewriting what's typed. Dark mode takes effect at the next login.
defaults write NSGlobalDomain AppleInterfaceStyle -string 'Dark'
defaults write NSGlobalDomain AppleShowScrollBars -string 'Always'
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Trackpad: tap to click (all three keys are needed for it to stick everywhere)
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Keep Spotlight out of the menu bar (Cmd-Space still works)
defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1

# Bigger mouse pointer. Needs Full Disk Access for your terminal; if this is a
# no-op, set it by hand in System Settings > Accessibility > Display.
defaults write com.apple.universalaccess mouseDriverCursorSize -float 2 2>/dev/null

# ------------------------------------------------------------------------------
# Xcode Command Line Tools
# ------------------------------------------------------------------------------
# Software Update can only offer CLT updates when the install is receipted. An
# unreceipted install — the directory exists but pkgutil has no record of it —
# is invisible to Software Update and silently never updates, while brew doctor
# keeps reporting a newer release is available. Reinstall only in that case;
# when the receipt is present this whole block is a no-op.
if [ -d /Library/Developer/CommandLineTools ] &&
   ! pkgutil --pkg-info=com.apple.pkg.CLTools_Executables >/dev/null 2>&1; then
  echo
  echo "==> Command Line Tools have no package receipt; reinstalling"
  echo "    This needs sudo and downloads roughly 1GB."
  sudo rm -rf /Library/Developer/CommandLineTools

  # This marker makes the CLT update appear in `softwareupdate --list`, which
  # lets it install headlessly instead of via the GUI dialog that
  # `xcode-select --install` puts up.
  CLT_MARKER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  sudo touch "$CLT_MARKER"
  # Software Update often offers several CLT releases at once. Take the highest
  # version, not the first one listed.
  CLT_LABEL=$(softwareupdate --list 2>/dev/null |
    sed -n 's/^ *\* Label: \(Command Line Tools.*\)$/\1/p' |
    sort -V | tail -1)
  if [ -n "$CLT_LABEL" ]; then
    step "Install $CLT_LABEL" sudo softwareupdate --install "$CLT_LABEL"
  else
    echo "!!! Software Update offered no CLT package; falling back to"
    echo "    xcode-select --install, which needs you to click through a dialog."
    xcode-select --install 2>/dev/null || true
    FAILED+=("Command Line Tools (finish the xcode-select dialog by hand)")
  fi
  sudo rm -f "$CLT_MARKER"
fi

# Note: macOS updates are deliberately NOT installed here. `softwareupdate
# --install` on a macOS release reboots the machine, which would abandon the
# rest of this script. The auto-update settings in System Settings handle them;
# see the Command Line Tools section of the README.

# ------------------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
  step "Install Homebrew" /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Put brew on PATH for this session (Apple Silicon, then Intel fallback)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "!!! Homebrew is not available; skipping everything that depends on it."
  exit 1
fi

# The Homebrew installer prints this line but doesn't add it; without it, new
# terminals on a fresh Mac have no `brew` on PATH.
append_once ~/.zprofile 'brew shellenv' "eval \"\$($(command -v brew) shellenv)\""

# Some casks (Steam, for one) are Intel-only and need Rosetta on Apple Silicon.
if [ "$(uname -m)" = arm64 ] && ! pgrep -q oahd; then
  step "Install Rosetta 2" softwareupdate --install-rosetta --agree-to-license
fi

step "brew update" brew update
step "brew upgrade" brew upgrade --formula
step "brew bundle" brew bundle --file="$REPO_DIR/Brewfile" --no-upgrade
# Casks whose installers need root are skipped by the background updater (a
# launchd job has nowhere to ask for a password), so upgrade them here, where
# someone is at the keyboard. The list lives in config/brew-autoupdate.sh; the
# other casks are the background updater's job.
SUDO_CASKS=()
for cask in $("$REPO_DIR/config/brew-autoupdate.sh" --print-sudo-casks); do
  # Only the ones that are installed: bundle may have just failed to add one.
  [ -d "$(brew --caskroom)/$cask" ] && SUDO_CASKS+=("$cask")
done
if [ ${#SUDO_CASKS[@]} -gt 0 ]; then
  step "brew upgrade sudo casks" brew upgrade --cask "${SUDO_CASKS[@]}"
fi

# ------------------------------------------------------------------------------
# Homebrew background upgrades
# ------------------------------------------------------------------------------
# A LaunchAgent runs config/brew-autoupdate.sh every 12 hours and at login. It
# replaces the domt4/autoupdate tap, which had no way to stop Homebrew 6 from
# upgrading self-updating casks (quitting iTerm, Claude, 1Password... to do
# it), and whose --sudo option was the source of the background password
# prompts. The script explains what it skips and why.
echo
echo "==> Homebrew background upgrades"
BAU_LABEL=com.andrewgunn.brew-autoupdate
BAU_DIR="$HOME/Library/Application Support/brew-autoupdate"
BAU_PLIST="$HOME/Library/LaunchAgents/$BAU_LABEL.plist"
BAU_LOG="$HOME/Library/Logs/brew-autoupdate.log"

# Retire the tap-based agent if it's still around, along with the ~/.zprofile
# warning that referenced its launchd label (a fresh one is appended below).
if brew tap 2>/dev/null | grep -qx 'domt4/autoupdate'; then
  echo "    removing the domt4/autoupdate agent"
  brew autoupdate delete >/dev/null 2>&1
  brew untap domt4/autoupdate >/dev/null 2>&1
  brew untrust domt4/autoupdate >/dev/null 2>&1
fi
if [ -f ~/.zprofile ] && grep -qF 'launchctl list com.github.domt4.homebrew-autoupdate' ~/.zprofile; then
  sed -i '' '/^# brew-autoupdate: warn when the last run failed$/,/^fi$/d' ~/.zprofile
  echo "    removed the old warning block from ~/.zprofile"
fi

mkdir -p "$BAU_DIR" "$HOME/Library/LaunchAgents"
install -m 755 "$REPO_DIR/config/brew-autoupdate.sh" "$BAU_DIR/brew-autoupdate"
cat > "$BAU_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$BAU_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BAU_DIR/brew-autoupdate</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>43200</integer>
  <key>StandardOutPath</key>
  <string>$BAU_LOG</string>
  <key>StandardErrorPath</key>
  <string>$BAU_LOG</string>
  <key>LowPriorityIO</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF

# (Re)load the agent. bootout kills a run in progress, so leave a running one
# alone: the script path is unchanged, so it picks up script changes next run,
# but plist changes wait for the next run.sh.
if launchctl print "gui/$(id -u)/$BAU_LABEL" 2>/dev/null | grep -q 'state = running'; then
  echo "!!! a brew autoupdate run is in progress; not reloading the agent"
  FAILED+=("Reload the brew-autoupdate agent (re-run once the current run finishes)")
else
  launchctl bootout "gui/$(id -u)/$BAU_LABEL" 2>/dev/null
  step "Load $BAU_LABEL" launchctl bootstrap "gui/$(id -u)" "$BAU_PLIST"
fi

# Failed runs would otherwise be silent. Warn at login shell startup instead;
# launchd keeps the last exit status, and reading it needs no permissions.
append_block_once ~/.zprofile 'brew-autoupdate (mac-setup): warn when the last run failed' <<EOF
# brew-autoupdate (mac-setup): warn when the last run failed
_bau_exit=\$(launchctl list $BAU_LABEL 2>/dev/null |
  awk -F'= ' '/LastExitStatus/ { gsub(/[; ]/, "", \$2); print \$2 }')
if [ -n "\$_bau_exit" ] && [ "\$_bau_exit" != "0" ]; then
  printf '\033[33mbrew autoupdate: last run failed (launchd status %s) — see ${BAU_LOG/#$HOME/~}\033[0m\n' "\$_bau_exit"
fi
unset _bau_exit
EOF

# ------------------------------------------------------------------------------
# Git
# ------------------------------------------------------------------------------
echo
echo "==> Git"
if [ -z "$(git config --global user.name || true)" ]; then
  read -rp "Enter your git user name: " git_user_name
  git config --global user.name "$git_user_name"
fi
if [ -z "$(git config --global user.email || true)" ]; then
  read -rp "Enter your git email address: " git_email_address
  git config --global user.email "$git_email_address"
fi
# Everything except the identity lives in config/gitconfig and is pulled in by
# reference, so editing the repo file is enough. Settings this script used to
# write directly into ~/.gitconfig would shadow the include, so drop them.
git config --global include.path "$REPO_DIR/config/gitconfig"
for key in init.defaultBranch pull.rebase fetch.prune alias.lg diff.tool difftool.prompt \
           difftool.bc.trustExitCode merge.tool mergetool.keepBackup mergetool.bc.trustExitCode; do
  git config --file ~/.gitconfig --unset-all "$key" 2>/dev/null || true
done
git config --global --includes --get init.defaultBranch >/dev/null ||
  { echo "!!! config/gitconfig is not being read"; FAILED+=("git include.path"); }
# ~/.config/git/ignore is read by git with no further configuration.
mkdir -p ~/.config/git
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  append_once ~/.config/git/ignore "^$(printf '%s' "$line" | sed 's/[.*[\]/\\&/g')\$" "$line"
done < "$REPO_DIR/config/gitignore"

# ------------------------------------------------------------------------------
# .NET
# ------------------------------------------------------------------------------
if command -v dotnet >/dev/null 2>&1; then
  echo
  echo "==> .NET"
  step "dotnet dev-certs" dotnet dev-certs https --trust
  step "Aspire templates" dotnet new install Aspire.ProjectTemplates --force
  for tool in dotnet-ef dotnet-reportgenerator-globaltool dotnet-sonarscanner \
              ilspycmd Microsoft.Playwright.CLI Verify.Tool; do
    step "$tool" dotnet tool update --global "$tool"
  done
  # shellcheck disable=SC2016  # $HOME is deliberately written literally
  append_once ~/.zprofile '\.dotnet/tools' 'export PATH="$PATH:$HOME/.dotnet/tools"'
else
  echo "!!! dotnet not found (did the dotnet-sdk cask install?); skipping .NET setup."
  FAILED+=(".NET setup (dotnet not on PATH)")
fi

# ------------------------------------------------------------------------------
# Claude Code (native installer — no Node/npm, auto-updates itself)
# ------------------------------------------------------------------------------
echo
echo "==> Claude Code"
if [ -x "$HOME/.local/bin/claude" ] || command -v claude >/dev/null 2>&1; then
  echo "    already installed; it updates itself"
else
  step "Install Claude Code" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi
# shellcheck disable=SC2016  # $HOME is deliberately written literally
append_once ~/.zprofile '\.local/bin' 'export PATH="$PATH:$HOME/.local/bin"'

# ------------------------------------------------------------------------------
# Oh My Zsh (unattended: don't switch shell or launch zsh mid-script)
# ------------------------------------------------------------------------------
echo
echo "==> Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  step "Install Oh My Zsh" env RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  step "Clone powerlevel10k" git clone --depth=1 \
    https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# Activate the powerlevel10k theme in .zshrc
if [ -f "$HOME/.zshrc" ]; then
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
    sed -i '' 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$HOME/.zshrc"
  fi
  append_once "$HOME/.zshrc" 'zsh-syntax-highlighting\.zsh' \
    "source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

  # `p10k configure` is an interactive wizard, but all it produces is ~/.p10k.zsh
  # — so ship the finished file instead of making this a manual step. Only
  # copied when absent, so later tweaks made by the wizard are never clobbered.
  if [ ! -f "$HOME/.p10k.zsh" ] && [ -f "$REPO_DIR/config/p10k.zsh" ]; then
    cp "$REPO_DIR/config/p10k.zsh" "$HOME/.p10k.zsh"
    echo "    installed ~/.p10k.zsh from the repo"
  fi
  append_once "$HOME/.zshrc" '\.p10k\.zsh' \
    '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
fi

# ------------------------------------------------------------------------------
# Code directory
# ------------------------------------------------------------------------------
# The Finder sidebar entry stays manual. The only practical CLI for it, mysides,
# was disabled in homebrew-cask on 2025-10-13 for being unmaintained, and an
# installed-but-disabled package makes `brew upgrade` exit non-zero — which is
# what silently skipped every cask upgrade before.
echo
echo "==> Code directory"
mkdir -p "$HOME/Code"

# ------------------------------------------------------------------------------
# Rectangle
# ------------------------------------------------------------------------------
echo
echo "==> Rectangle"
# modifierFlags are the sum of Cocoa modifier masks: control 262144 + option
# 524288 = 786432 (^⌥), plus shift 131072 = 917504 (^⌥⇧).
RECT_CTRL_OPT=786432
RECT_CTRL_OPT_SHIFT=917504
rect_bind() {   # rect_bind <action> <keyCode> <modifierFlags>
  defaults write com.knollsoft.Rectangle "$1" -dict \
    keyCode -int "$2" modifierFlags -int "$3"
}
rect_unbind() { defaults write com.knollsoft.Rectangle "$1" -dict; }

# Left/right half are deliberately left unset: alternateDefaultShortcuts already
# maps them to ^⌥← and ^⌥→.
defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
defaults write com.knollsoft.Rectangle allowAnyShortcut -bool true
defaults write com.knollsoft.Rectangle launchOnLogin -bool true
defaults write com.knollsoft.Rectangle hideMenubarIcon -bool true

rect_bind centerHalf      125 "$RECT_CTRL_OPT"        # ^⌥↓
rect_bind maximize        126 "$RECT_CTRL_OPT"        # ^⌥↑
rect_bind center           36 "$RECT_CTRL_OPT"        # ^⌥↩
rect_bind firstThird       18 "$RECT_CTRL_OPT"        # ^⌥1
rect_bind centerThird      19 "$RECT_CTRL_OPT"        # ^⌥2
rect_bind lastThird        20 "$RECT_CTRL_OPT"        # ^⌥3
rect_bind firstTwoThirds  123 "$RECT_CTRL_OPT_SHIFT"  # ^⌥⇧←
rect_bind lastTwoThirds   124 "$RECT_CTRL_OPT_SHIFT"  # ^⌥⇧→

# Everything else off, so no stray default shortcuts remain bound.
for action in bottomHalf bottomLeft bottomRight topHalf topLeft topRight \
              firstFourth lastFourth firstThreeFourths lastThreeFourths \
              maximizeHeight nextDisplay previousDisplay restore larger smaller; do
  rect_unbind "$action"
done

# ------------------------------------------------------------------------------
# Stats and SmoothScroll
# ------------------------------------------------------------------------------
echo
echo "==> Stats and SmoothScroll"
defaults write eu.exelban.Stats Battery_state -bool false
defaults write eu.exelban.Stats LaunchAtLoginNext -bool true

# Only these two behavioural keys: the SmoothScroll licence lives outside this
# repo on purpose, so nothing here reads or writes it.
defaults write com.galambalazs.SmoothScroll showMenuBarIcon -bool false
defaults write com.galambalazs.SmoothScroll reverseWheelDirection -bool true
defaults write com.galambalazs.SmoothScroll launchOnLogin -bool true

# ------------------------------------------------------------------------------
# iTerm
# ------------------------------------------------------------------------------
echo
echo "==> iTerm"
if pgrep -xq iTerm2 || pgrep -xq iTerm; then
  echo "!!! iTerm is running; it would overwrite these on quit."
  echo "    Quit iTerm (run this from Terminal.app) and re-run to apply them."
  FAILED+=("iTerm settings (was running)")
else
  defaults write com.googlecode.iterm2 PromptOnQuit -bool false
  defaults write com.googlecode.iterm2 OnlyWhenMoreTabs -bool false
  defaults write com.googlecode.iterm2 UseLionStyleFullscreen -bool false
  defaults write com.googlecode.iterm2 ShowFullScreenTabBar -bool false
  defaults write com.googlecode.iterm2 DimInactiveSplitPanes -bool false

  # Font and ligatures live inside the profile dict, so edit the plist directly,
  # locating the default profile by its GUID rather than assuming index 0.
  ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  ITERM_GUID=$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null)
  if [ -n "$ITERM_GUID" ] && [ -f "$ITERM_PLIST" ]; then
    idx=0
    while g=$(/usr/libexec/PlistBuddy -c "Print :\"New Bookmarks\":$idx:Guid" \
              "$ITERM_PLIST" 2>/dev/null); do
      if [ "$g" = "$ITERM_GUID" ]; then
        /usr/libexec/PlistBuddy \
          -c "Set :\"New Bookmarks\":$idx:\"Normal Font\" FiraCode-Retina 18" \
          -c "Set :\"New Bookmarks\":$idx:\"ASCII Ligatures\" true" \
          "$ITERM_PLIST" 2>/dev/null && echo "    set Fira Code 18 with ligatures"
        break
      fi
      idx=$((idx + 1))
    done
    killall cfprefsd 2>/dev/null
  else
    echo "!!! iTerm has no preferences yet (never launched?); font not set."
    FAILED+=("iTerm font (open iTerm once, quit it, and re-run)")
  fi
fi

# ------------------------------------------------------------------------------
# Visual Studio Code
# ------------------------------------------------------------------------------
# Both CLIs accept repeated --install-extension flags, so one call per editor.
# --force upgrades an already-installed extension rather than skipping it.
VSCODE_EXTENSIONS=(
  bradlc.vscode-tailwindcss
  docker.docker
  mechatroner.rainbow-csv
  ms-azuretools.vscode-bicep
  ms-azuretools.vscode-containers
  ms-azuretools.vscode-docker
  ms-dotnettools.vscode-dotnet-runtime
  ms-python.debugpy
  ms-python.python
  ms-python.vscode-pylance
  ms-python.vscode-python-envs
  ms-toolsai.jupyter
  ms-vscode-remote.remote-containers
  saoudrizwan.claude-dev
)
CURSOR_EXTENSIONS=(
  docker.docker
  mechatroner.rainbow-csv
  ms-azuretools.vscode-containers
  ms-azuretools.vscode-docker
  ms-python.debugpy
  ms-python.python
  ms-python.vscode-pylance
  ms-toolsai.jupyter
  ms-vscode-remote.remote-containers
)
install_extensions() {   # install_extensions <cli> <extension>...
  local cli="$1" args=()
  shift
  for ext; do args+=(--install-extension "$ext"); done
  "$cli" "${args[@]}" --force
}
if command -v code >/dev/null 2>&1; then
  echo
  echo "==> Visual Studio Code"
  step "VS Code extensions" install_extensions code "${VSCODE_EXTENSIONS[@]}"
fi
if command -v cursor >/dev/null 2>&1; then
  echo
  echo "==> Cursor"
  step "Cursor extensions" install_extensions cursor "${CURSOR_EXTENSIONS[@]}"
fi

# ------------------------------------------------------------------------------
# Rokit (Roblox toolchain manager; its installer also wires up ~/.zshenv)
# ------------------------------------------------------------------------------
echo
echo "==> Rokit"
if [ -x "$HOME/.rokit/bin/rokit" ]; then
  echo "    already installed; it updates itself with \`rokit self-update\`"
else
  step "Install Rokit" bash -c \
    'curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash'
fi

# ------------------------------------------------------------------------------
# GitHub SSH key
# ------------------------------------------------------------------------------
echo
echo "==> GitHub SSH"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/github" ]; then
  echo "    Generating an ed25519 key; you'll be asked for a passphrase."
  ssh-keygen -t ed25519 -C github -f "$HOME/.ssh/github"
fi
append_block_once "$HOME/.ssh/config" 'IdentityFile ~/.ssh/github' <<'EOF'
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/github
EOF
chmod 600 "$HOME/.ssh/config"
ssh-add --apple-use-keychain "$HOME/.ssh/github" 2>/dev/null ||
  echo "    (add the key to the agent later with: ssh-add --apple-use-keychain ~/.ssh/github)"

# ------------------------------------------------------------------------------
# Apply the Finder and Dock settings written at the top. Done last, on purpose:
# relaunching Finder opens a window that takes keyboard focus, which mangles any
# password being typed if it happens mid-script.
# ------------------------------------------------------------------------------
echo
echo "==> Restarting Finder, Dock and the menu bar"
killall Finder 2>/dev/null
killall Dock 2>/dev/null
killall SystemUIServer 2>/dev/null   # picks up the screenshot location

# ------------------------------------------------------------------------------
echo
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "==> Finished with ${#FAILED[@]} failed step(s):"
  printf '      - %s\n' "${FAILED[@]}"
else
  echo "==> Finished with no failures."
fi
echo
echo "Next: open a new terminal, run \`p10k configure\`, then work through the"
echo "manual steps in README.md."
