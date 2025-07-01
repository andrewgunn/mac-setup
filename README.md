# Mac Setup

## Code

1. Open iTerm
    1. Make the code directory `mkdir ~/code`
1. Open Finder
    1. Navigate to $USER
    1. Add `Code` directory to the Finder sidebar

## Setup most of the things (Homebrew, NPM, Git, etc)

1. Clone this repository to the Code directory
1. Open a CLI
    1. Run `sh setup.sh`

## OS

1. Open a CLI
    1. Show/hide the dock instantly `defaults write com.apple.dock autohide-time-modifier -int 0; killall Dock`
1. Open System Settings
    1. Go to Accessibility
        3. Increase the pointer size
    1. Go to `Control Centre`
        1. Go to `Menu Bar Only`
            1. Set `Spotlight` to `Don't Show in Menu Bar`

## Finder

1. Open Finder 
    1. Go to Settings
    1. Go to General
        1. Change `New Finder window show` to Downloads

https://www.robinwieruch.de/mac-setup-web-development/

## 1Password

1. Open 1Password
    1. Go to Settings
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

## Rectangle

1. Open Rectangle
    1. Go to Keyboard Shortcuts
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

## Oh My Zsh

1. Open the `~./zshrc` file using a text editor
    1. Change `ZSH_THEME` to `powerlevel10k/powerlevel10k`
    1. Configure zsh-syntax-highlighting (add to the bottom of `.zshrc`) 
    ```
    echo "source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ${ZDOTDIR:-$HOME}/.zshrc
    ```
    1. Configure Pyenv (add to the bottom of `.zshrc`)
    ```
    eval "$(pyenv init -)"
    if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi
    ```

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

## Rider

TODO

## Visual Studio Code

1. Install [Jupyter Extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)

## .NET MAUI

https://khalidabuhakmeh.com/dotnet-maui-development-environment-set-up-walkthrough
