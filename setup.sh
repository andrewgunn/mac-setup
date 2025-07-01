# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update
brew upgrade
brew bundle
brew tap homebrew/autoupdate
brew autoupdate delete
brew autoupdate start 43200 --upgrade --cleanup --immediate

# NPM
npm install -g @anthropic-ai/claude-code
