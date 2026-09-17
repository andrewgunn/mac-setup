# Interactive shell setup for the terminal tools in the Brewfile. run.sh adds a
# single `source` line for this file to ~/.zshrc, so a `git pull` reaches the
# machine and anything added to ~/.zshrc by hand still wins (it's sourced before
# the rest of the file finishes).
#
# PATH isn't set here: ~/.zprofile already has Homebrew, ~/.local/bin,
# ~/.dotnet/tools and Rokit.

# Atom One Dark, the same palette Neovim and lazygit's delta use.
export BAT_THEME="TwoDark"

# fzf searches files with fd, so .gitignore and .git are respected.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --cycle'

# ^R history, ^T files, ⌥C directories. Only in a real interactive shell: the
# process substitution upsets anything sourcing this file non-interactively.
if [[ -t 0 && -t 1 ]] && command -v fzf >/dev/null; then
  source <(fzf --zsh)
fi

# `z koala2` jumps to the folder you mean; `zi` picks from history with fzf.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# eza for listings (git status, icons, tree), bat for files (syntax, paging).
# Both behave like ls/cat when piped, so scripts are unaffected.
alias ls="eza"
alias ll="eza -la"
alias tree="eza --tree"
alias cat="bat"
