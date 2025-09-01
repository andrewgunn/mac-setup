#!/bin/bash

# Finder
chflags nohidden ~/Library
defaults write com.apple.finder AppleShowAllFiles YES
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
killall Finder

# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update
brew upgrade
brew bundle
brew tap homebrew/autoupdate
brew autoupdate delete
brew autoupdate start

# Git
git config --global user.name "Andrew Gunn"
git config --global user.email "hello@andrewgunn.co.uk"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global diff.tool bc
git config --global difftool.bc.trustExitCode true
git config --global difftool.prompt false
git config --global merge.tool bc
git config --global mergetool.bc.trustExitCode true
git config --global mergetool.keepBackup false
git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

# NPM
npm install -g npm@latest
npm install -g @anthropic-ai/claude-code

# OhMyZsh
[ ! -d "$HOME/.oh-my-zsh" ] && sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
[ ! -d "$P10K_DIR" ] && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
