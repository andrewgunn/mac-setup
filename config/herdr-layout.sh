#!/bin/bash
# New Herdr tabs and workspaces for one agent's work: Claude in the tab, with
# Neovim (Cmd+Shift+E) and lazygit (Cmd+Shift+G) as popups over it rather than
# panes beside it, so each gets the whole screen when it's wanted.
#
# Herdr has no tab templates, so config/herdr.toml binds keys to this instead
# of to its own new_tab and new_workspace:
#
#   herdr-layout.sh tab              a tab in the active workspace; in a git
#                                    repo it asks for a branch and puts the
#                                    tab on its own worktree, so agents in
#                                    different tabs never share a checkout
#   herdr-layout.sh workspace [DIR]  a workspace named after DIR, with no DIR
#                                    asking for a repo under ~/Code (most
#                                    visited first, via zoxide)
set -euo pipefail

CODE_DIR="$HOME/Code"

# Starts Claude in the new tab's pane, $1.
lay_out() {
  herdr pane run "$1" claude >/dev/null
}

# Prints the directory a new tab should use: a fresh worktree of the repo $1 is
# in, or $1 itself when it isn't a git repo. Worktrees go where Claude Code puts
# its own, <repo>/.claude/worktrees/<branch>, on a new branch off the main
# checkout's HEAD.
tab_dir() {
  local dir="$1" root branch path
  if ! root=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    echo "$dir"
    return
  fi
  root=$(dirname "$root")
  # fzf with nothing to choose from is just a prompt that Esc can cancel. It
  # asks again until it gets a name, which becomes the branch: "Fix quote
  # form" is fix-quote-form.
  while [ -z "${branch:-}" ]; do
    branch=$(fzf --print-query --height 100% --reverse --no-info --no-separator \
      --prompt "Branch: " --header "New tab in $(basename "$root"): what's it for? · Esc cancels" \
      </dev/null | head -1) || [ $? -eq 1 ] || return 1
    branch=$(tr '[:upper:]' '[:lower:]' <<<"$branch" | sed -E 's/[^a-z0-9/._-]+/-/g; s/^-+|-+$//g')
  done
  path="$root/.claude/worktrees/${branch//\//-}"
  if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$root" worktree add "$path" "$branch" >&2
  else
    git -C "$root" worktree add -b "$branch" "$path" >&2
  fi
  # Keep the worktrees out of the main checkout's `git status`.
  git -C "$root" check-ignore -q "$path" ||
    echo '/.claude/worktrees/' >> "$root/.git/info/exclude"
  echo "$path"
}

pick_repo() {
  {
    zoxide query --list 2>/dev/null | grep -E "^$CODE_DIR/[^/]+$" || true
    fd --type directory --max-depth 1 --absolute-path . "$CODE_DIR" | sed 's:/$::'
  } | awk '!seen[$0]++' | sed "s:^$CODE_DIR/::" \
    | fzf --prompt 'New workspace in ~/Code/' --height 100% --reverse \
    | sed "s:^:$CODE_DIR/:"
}

case "${1:-}" in
  tab)
    cwd=$(tab_dir "${HERDR_ACTIVE_PANE_CWD:-$HOME}") || exit 0   # Esc
    workspace=(${HERDR_ACTIVE_WORKSPACE_ID:+--workspace "$HERDR_ACTIVE_WORKSPACE_ID"})
    main=$(herdr tab create "${workspace[@]}" --cwd "$cwd" --label "$(basename "$cwd")" --focus | jq -r .result.root_pane.pane_id)
    lay_out "$main"
    ;;
  workspace)
    cwd="${2:-$(pick_repo)}"
    [ -d "$cwd" ] || exit 0   # Esc in the picker
    zoxide add "$cwd" 2>/dev/null || true
    created=$(herdr workspace create --cwd "$cwd" --label "$(basename "$cwd")" --focus)
    # Name the first tab after the branch, so "claude finished" reads
    # "koala · main" rather than "koala · 1".
    if branch=$(git -C "$cwd" branch --show-current 2>/dev/null) && [ -n "$branch" ]; then
      herdr tab rename "$(jq -r .result.tab.tab_id <<<"$created")" "$branch" >/dev/null
    fi
    lay_out "$(jq -r .result.root_pane.pane_id <<<"$created")"
    ;;
  *)
    echo "usage: $(basename "$0") tab | workspace [DIR]" >&2
    exit 2
    ;;
esac
