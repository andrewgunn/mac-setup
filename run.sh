#!/bin/bash
# Sets up a Mac from scratch. Safe to re-run: every step is idempotent and
# nothing prompts for input it already has.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=()

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
# Open new Finder windows in Downloads
defaults write com.apple.finder NewWindowTarget -string 'PfLo'
defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/Downloads/"
killall Finder 2>/dev/null

# Show/hide the Dock instantly
defaults write com.apple.dock autohide-time-modifier -int 0
killall Dock 2>/dev/null

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
  CLT_LABEL=$(softwareupdate --list 2>/dev/null |
    awk '/\* Label: Command Line Tools/ { sub(/^ *\* Label: /, ""); print; exit }')
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

step "brew update" brew update
step "brew upgrade" brew upgrade
step "brew bundle" brew bundle --file="$REPO_DIR/Brewfile"

# Background auto-updates (formulae + casks) every 12 hours.
# NOTE: `brew autoupdate start` with no flags only refreshes metadata; --upgrade
# is what actually installs the new versions. --sudo (needs pinentry-mac, in the
# Brewfile) lets casks that require root upgrade unattended.
# Add --greedy to also upgrade casks that ship their own updater.
echo
echo "==> Homebrew auto-updates"
brew untap homebrew/autoupdate 2>/dev/null    # legacy duplicate of domt4/autoupdate
brew tap domt4/autoupdate
brew trust domt4/autoupdate
brew autoupdate delete
step "brew autoupdate start" brew autoupdate start 12h \
  --upgrade --cleanup --immediate --sudo --notify-on-error

# autoupdate's notifier is a background-only (LSUIElement) app whose binary is
# executed directly rather than launched through LaunchServices, so macOS always
# refuses its notification permission request and it never appears in System
# Settings > Notifications. That makes failed runs completely silent. Warn at
# login shell startup instead, which needs no permissions.
append_block_once ~/.zprofile 'brew-autoupdate: warn when the last run failed' <<'EOF'
# brew-autoupdate: warn when the last run failed
if [ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ]; then
  _bau_exit=$(launchctl list com.github.domt4.homebrew-autoupdate 2>/dev/null \
    | awk -F'= ' '/LastExitStatus/ { gsub(/[; ]/, "", $2); print $2 }')
  if [ -n "$_bau_exit" ] && [ "$_bau_exit" != "0" ]; then
    printf '\033[33mbrew autoupdate: last run failed (exit %s) — run `brew autoupdate logs`\033[0m\n' "$_bau_exit"
  fi
  unset _bau_exit
fi
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
git config --global init.defaultBranch main
git config --global pull.rebase false
# Beyond Compare. Requires its CLI tools: open Beyond Compare and choose
# Install Command Line Tools from the app menu (installs `bcomp`).
git config --global diff.tool bc
git config --global difftool.bc.trustExitCode true
git config --global difftool.prompt false
git config --global merge.tool bc
git config --global mergetool.bc.trustExitCode true
git config --global mergetool.keepBackup false
git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

# ------------------------------------------------------------------------------
# .NET
# ------------------------------------------------------------------------------
if command -v dotnet >/dev/null 2>&1; then
  echo
  echo "==> .NET"
  step "dotnet dev-certs" dotnet dev-certs https --trust
  step "Aspire templates" dotnet new install Aspire.ProjectTemplates --force
  step "dotnet-ef" dotnet tool update --global dotnet-ef
  step "dotnet-reportgenerator" dotnet tool update --global dotnet-reportgenerator-globaltool
  step "Verify.Tool" dotnet tool update --global Verify.Tool
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
step "Install Claude Code" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
# shellcheck disable=SC2016  # $HOME is deliberately written literally
append_once ~/.zprofile '\.local/bin' 'export PATH="$PATH:$HOME/.local/bin"'

# ------------------------------------------------------------------------------
# Oh My Zsh (unattended: don't switch shell or launch zsh mid-script)
# ------------------------------------------------------------------------------
echo
echo "==> Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  step "Install Oh My Zsh" env RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
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
fi

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
