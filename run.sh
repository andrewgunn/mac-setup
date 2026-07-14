#!/bin/bash
set -uo pipefail

# Finder
chflags nohidden ~/Library
defaults write com.apple.finder AppleShowAllFiles YES
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
killall Finder

# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Put brew on PATH for this session (Apple Silicon, then Intel fallback)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

brew update
brew upgrade
brew bundle
brew tap homebrew/autoupdate
brew trust domt4/autoupdate
brew autoupdate delete
brew autoupdate start

# Git
echo "Enter your git user name:"
read -r git_user_name
echo "Enter your git email address:"
read -r git_email_address
git config --global user.name "$git_user_name"
git config --global user.email "$git_email_address"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global diff.tool bc
git config --global difftool.bc.trustExitCode true
git config --global difftool.prompt false
git config --global merge.tool bc
git config --global mergetool.bc.trustExitCode true
git config --global mergetool.keepBackup false
git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

# .NET
dotnet dev-certs https --trust
dotnet new install Aspire.ProjectTemplates --force
dotnet tool update --global dotnet-ef
dotnet tool update --global dotnet-reportgenerator-globaltool
dotnet tool update --global Verify.Tool

grep -qxF 'export PATH="$PATH:$HOME/.dotnet/tools"' ~/.zprofile 2>/dev/null || cat << \EOF >> ~/.zprofile
export PATH="$PATH:$HOME/.dotnet/tools"
EOF

# NPM
npm install -g npm@latest

# Claude Code (native installer — no Node/npm, auto-updates)
curl -fsSL https://claude.ai/install.sh | bash

grep -qxF 'export PATH="$PATH:$HOME/.local/bin"' ~/.zprofile 2>/dev/null || cat << \EOF >> ~/.zprofile
export PATH="$PATH:$HOME/.local/bin"
EOF

# OhMyZsh (unattended: don't switch shell or launch zsh mid-script)
[ ! -d "$HOME/.oh-my-zsh" ] && RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
[ ! -d "$P10K_DIR" ] && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"

# Activate the powerlevel10k theme in .zshrc
if [ -f "$HOME/.zshrc" ]; then
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
    sed -i '' 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$HOME/.zshrc"
  fi
fi