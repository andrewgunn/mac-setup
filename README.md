# Mac Setup

## OS

1. Open Terminal
1. Show/hide the dock instantly `defaults write com.apple.dock autohide-time-modifier -int 0; killall Dock`
1. Open System Settings
2. Go to Accessibility
3. Increase the pointer size

## Homebrew

1. Install Homebrew `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
1. Update brew `brew update`
1. Upgrade brew `brew update`
1. Download the contents of `Brewfile` from this repository
1. Change directory `cd ~/Downloads`
1. Install the bundle `
1. Install the Auto-Update tap `brew tap homebrew/autoupdate`
1. Configure the Auto-Update tap `brew autoupdate start 43200 --upgrade --cleanup --immediate`

## 1Password

1. Open 1Password
1. Go to settings `1Password > Settings...`
1. Go to General
    1. Disable `Keep 1Password in the menu bar`
    1. Disable the `Show 1Password` shortcut
    1. Change the `Show Quick Access` shortcut to ⇧⌘P

## AltTab

1. Open AltTab
1. Go to General
    1. Disable `Menubar icon`
1. Go to Controls
    1. Change keyboard shortcut to select previous window to ⇧⇥ `Shortcuts when active... > Select previous window`

## Finder

1. Open iTerm
1. Show Library folder `chflags nohidden ~/Library`
1. Show hidden files `defaults write com.apple.finder AppleShowAllFiles YES`
1. Show path bar `defaults write com.apple.finder ShowPathbar -bool true`
1. Show status bar `defaults write com.apple.finder ShowStatusBar -bool true`
1. Close all Finder wondows `killall Finder;`
1. Open Finder 
1. Go to Settings `Finder > Settings...`
1. Go to General
1. Change `New Finder window show` to Downloads

https://www.robinwieruch.de/mac-setup-web-development/

## Rectangle

1. Open Rectangle
1. Go to shortcuts
    1. Disable all shortcuts
    1. Set the following shortcuts:
        1. Left Half `^⌥←`
        1. Right Half `^⌥→`
        1. Centre Half `^⌥↓`
        1. First Third `^⌥1`
        1. Centre Third `^⌥2`
        1. Last Third `^⌥3`
        1. Maximuse `^⌥↑`
        1. Centre `^⌥↩`
1. Go to settings
    1.  Enable `Launch on login`
    1.  Enable `Hide menu bar icon`
  
## SmoothScroll

1. Open SmoothScroll
1. Disable `Show menu bar icon`
1. Enable `Reverse Wheel Direction`

## Stats

1. Open Stats
1. Go to Battery
    1. Disablebrew bundle install`

## iTerm

1. Open iTerm
1. Go to settings `iTerm > Settings...`
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

## Oh My Zsh

1. Open iTerm
1. Install Oh My Zsh `sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
1. Install Powerlevel10k `git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"`
1. Open the `~./zshrc` file using Zed
1. Change `ZSH_THEME` to `powerlevel10k/powerlevel10k`
1. Open iTerm
1. Configure Powerlevel10k
1. Configure zsh-syntax-highlighting  `echo "source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ${ZDOTDIR:-$HOME}/.zshrc` 
1. Close iTerm
1. Configure Pyenv (add to the bottom of `.zshrc`)
    ```
    eval "$(pyenv init -)"
    if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi
    ```
1. Open iTerm

## Git

1. Open iTerm
1. Set commiter name `git config --global user.name "Andrew Gunn"`
1. Set committer email address `git config --global user.email "hello@andrewgunn.co.uk"`
1. Set default branch `git config --global init.defaultBranch main`
1. Set improved log `git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"`

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
1. Add publick key to GitHub `gh auth login`

## Code

1. Open iTerm
1. Make the code directory `mkdir ~/code`
1. Open Finder
1. Navigate to $USER
3. Add `Code` folder to the Finder sidebar

## Rider

TODO

## Visual Studio Code

TODO

https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter

## .NET MAUI

https://khalidabuhakmeh.com/dotnet-maui-development-environment-set-up-walkthrough
