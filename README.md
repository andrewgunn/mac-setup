# Mac Setup

## Terminal

1. Open Terminal
1. Install Homebrew `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
1. Update brew `brew update`
1. Upgrade brew `brew update`
1. Download the contents of `Brewfile` from this repository
1. Change directory to Downloads `cd Downloads`
1. Install the bundle `brew bundle install`

## Rectangle

1. Open Rectangle
1. Disable all shortcuts
1. Set the following shortcuts:

    1. Left Half `^⌥←`
    2. Right Half `^⌥→`
    2. Centre Half `^⌥↓`
    2. First Third `^⌥1`
    2. Centre Third `^⌥2`
    2. Last Third `^⌥3`
    2. Maximuse `^⌥↑`
    2. Centre `^⌥↩`

## 1Password

1. Open 1Password
1. Go to settings `1Password > Settings...`
1. Disable the `Show 1Password` shortcut
1. Change the `Show Quick Access` shortcut to ⇧⌘P

## iTerm

1. Open iTerm
1. Go to settings `iTerm > Settings...`
1. Disable `General > Closing > Confirm closing multiple sessions`
1. Disable `General > Closing > Confirm "Quit iTerm2 (⌘Q)"`
1. Change the font to Fira Code `Profiles > Text > Font`
1. Change the font weight to Retina `Profiles > Text > Font`
1. Change the font size to 18 `Profiles > Text > Font`
1. Enable `Profiles > Text > Font > Use ligatures`
1. Load natural text editing key mappings `Profiles > Keys > Key Mappings > Presets... > Natural Text Editing`

## Oh My Zsh

1. Open iTerm
1. Install Oh My Zsh `sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
1. Install Powerlevel10k `git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"`
1. Open the `~./zshrc` file using Zed
1. Change `ZSH_THEME` to `powerlevel10k/powerlevel10k`
1. Open iTerm
1. Configure Powerlevel10k
1. Configure zsh-syntax-highlighting  `echo "source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ${ZDOTDIR:-$HOME}/.zshrc` 
3. Restart iTerm
4. 
