#!/bin/bash
# Sets up a Mac from scratch. Safe to re-run: every step is idempotent and
# nothing prompts for input it already has.
#
#   ./run.sh          run everything
#   ./run.sh -v       stream every step's output instead of folding it away
#   ./run.sh -h       this help
#
# Everything printed is also written to ~/Library/Logs/mac-setup/.
# shellcheck disable=SC2317,SC2329  # several functions are only invoked via step/trap
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ==============================================================================
# Presentation
# ==============================================================================
# Colour, glyphs and animation only when talking to a terminal; plain ASCII
# when piped. NO_COLOR is honoured.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  TTY=1
  BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m'
  CYAN=$'\e[36m' RESET=$'\e[0m'
  G_OK='✔' G_FAIL='✖' G_WARN='⚠' G_INFO='·' G_TODO='☐' G_RULE='─' G_BAR='━'
else
  TTY=0
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
  G_OK='ok  ' G_FAIL='FAIL' G_WARN='warn' G_INFO='-' G_TODO='[ ]' G_RULE='-' G_BAR='#'
fi
# Terminal width, re-read whenever something is drawn to fit it: the window can
# be resized mid-run, and a line that wraps under the spinner breaks the redraw.
COLS=80
measure() {
  local c=''
  [ "$TTY" = 1 ] && c=$(stty size < /dev/tty 2>/dev/null | awk '{ print $2 }')
  [ -z "$c" ] || [ "$c" -lt 20 ] && c=80
  [ "$c" -gt 100 ] && c=100
  COLS=$((c - 1))   # some terminals wrap when the last column is written
}
measure

# Everything shown is also appended to a log (colours included; `less -R`).
LOG_DIR="$HOME/Library/Logs/mac-setup"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y-%m-%d-%H%M%S).log"

START=$SECONDS
FAILED=()
SECTION_NAMES=()
SECTION_SECS=()
SECTION_START=$SECONDS
CURRENT_SECTION=''
INSTALLED_COUNT=0
SHELL_CHANGED=0   # set when ~/.zprofile or ~/.zshrc gains a line

emit() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$LOG"; }
fmt_secs() {   # 125 -> "2m 5s"
  if [ "$1" -ge 60 ]; then echo "$(($1 / 60))m $(($1 % 60))s"; else echo "$1s"; fi
}
repeat() { printf '%*s' "$2" '' | tr ' ' "$1"; }   # repeat <char> <count>
set_title() { [ "$TTY" = 1 ] && printf '\e]0;mac-setup · %s\a' "$1" > /dev/tty; }

# One-line status helpers. Everything the user reads goes through these.
ok()   { emit "  $GREEN$G_OK$RESET $*"; }
info() { emit "  $DIM$G_INFO $*$RESET"; }
warn() { emit "  $YELLOW$G_WARN $*$RESET"; }
todo() { emit "  $YELLOW$G_TODO$RESET $*"; }
fail() { emit "  $RED$G_FAIL $*$RESET"; FAILED+=("$*"); }
ask()  { printf '  %s?%s %s' "$CYAN" "$RESET" "$1"; }   # ask <prompt>; then read

# Section headers. The time each section takes is recorded for the chart at
# the end.
close_section() {
  if [ -n "$CURRENT_SECTION" ]; then
    SECTION_NAMES+=("$CURRENT_SECTION")
    SECTION_SECS+=($((SECONDS - SECTION_START)))
  fi
}
section() {
  close_section
  CURRENT_SECTION="$1"
  SECTION_START=$SECONDS
  emit ''
  emit "$BOLD$1$RESET"
  set_title "$1"
}

# Background renderer for a quiet step: a spinner line, then the last few lines
# of the command's output in grey, redrawn in place. It stops when the caller
# creates the flag file, erasing itself so the one-line result can take its
# place. (A flag rather than a signal: bash 3.2 can print "run_pending_traps"
# warnings when a trapped subshell is killed mid-setup.)
render() {   # render <label> <output-file> <stop-flag>
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 n=0 body label
  while [ ! -e "$3" ]; do
    measure
    label=$(printf '%s' "$1" | cut -c1-$((COLS - 4)))
    body=$(tail -n 6 "$2" 2>/dev/null | tr '\r' '\n' | tail -n 6 |
      sed $'s/\e\\[[0-9;]*[A-Za-z]//g' | expand | cut -c1-$((COLS - 6)))
    {
      [ "$n" -gt 0 ] && printf '\e[%dA' "$n"
      printf '\r\e[J  %s%s%s %s\n' "$CYAN" "${frames[i % 10]}" "$RESET" "$label"
      if [ -n "$body" ]; then
        printf '%s\n' "$body" | sed "s/^/      $DIM/;s/\$/$RESET/"
        n=$((1 + $(printf '%s\n' "$body" | wc -l)))
      else
        n=1
      fi
    } > /dev/tty
    i=$((i + 1))
    sleep 0.12
  done
  [ "$n" -gt 0 ] && printf '\e[%dA\r\e[J' "$n" > /dev/tty
}

# step [-i] <label> <command...>
#
# Runs a command and reports one line: a tick or a cross, and how long it took.
# By default the output is folded away — shown live in grey while it runs,
# then replaced by the result line — and kept in full in the log. It's printed
# in full only when the step fails (or with -v). A failure is listed again at
# the end, but the script keeps going: a missing cask shouldn't abandon the
# rest of the setup.
#
# -i marks a genuinely interactive command (the Homebrew installer's "press
# RETURN", ssh-keygen's passphrase, the GitHub sign-in) whose output can't be
# captured. It gets a dim lead-in line, streams as-is, then gets its result
# line. Everything else folds, including the long Homebrew steps: sudo prompts
# go to /dev/tty regardless, so capturing stdout doesn't get in their way.
step() {
  local live=0
  [ "$1" = -i ] && { live=1; shift; }
  local label="$1" start=$SECONDS rc out='' sp=''
  shift
  if [ "$live" = 1 ] || [ "$VERBOSE" = 1 ]; then
    emit "  $DIM$G_INFO $label$RESET"
    "$@"
    rc=$?
  else
    out=$(mktemp "${TMPDIR:-/tmp}/mac-setup.XXXXXX")
    if [ "$TTY" = 1 ]; then render "$label" "$out" "$out.done" & sp=$!; fi
    "$@" > "$out" 2>&1
    rc=$?
    if [ -n "$sp" ]; then touch "$out.done"; wait "$sp" 2>/dev/null; rm -f "$out.done"; fi
    { echo "--- $label"; cat "$out"; } >> "$LOG"
  fi
  local secs=$((SECONDS - start)) dur=''
  [ "$secs" -ge 2 ] && dur=" $DIM$(fmt_secs "$secs")$RESET"
  if [ "$rc" -eq 0 ]; then
    emit "  $GREEN$G_OK$RESET $label$dur"
  else
    emit "  $RED$G_FAIL $label failed$RESET$dur"
    if [ -n "$out" ] && [ -s "$out" ]; then
      tail -n 25 "$out" | sed "s/^/      $DIM/;s/\$/$RESET/"
    fi
    FAILED+=("$label")
  fi
  [ -n "$out" ] && rm -f "$out"
  return "$rc"
}

# pref [-currentHost] <domain> <key> <type> <value>
#
# `defaults write`, but it reads first and only writes when the value differs,
# so a re-run can say "all already set" instead of silently rewriting. Booleans
# are compared as 1/0, which is how `defaults read` prints them.
PREF_TOTAL=0
PREF_CHANGED=()
pref() {
  local host=()
  [ "$1" = -currentHost ] && { host=(-currentHost); shift; }
  local domain="$1" key="$2" type="$3" value="$4" cur want
  cur=$(defaults ${host[@]+"${host[@]}"} read "$domain" "$key" 2>/dev/null)
  case "$type" in
    -bool) case "$value" in true|TRUE|yes|YES|1) want=1 ;; *) want=0 ;; esac ;;
    *) want="$value" ;;
  esac
  PREF_TOTAL=$((PREF_TOTAL + 1))
  [ "$cur" = "$want" ] && return 0
  if defaults ${host[@]+"${host[@]}"} write "$domain" "$key" "$type" "$value" 2>/dev/null; then
    PREF_CHANGED+=("$key: ${cur:-unset} → $value")
  else
    return 1
  fi
}
# prefs_done <label>: report the batch of pref calls since the last report.
prefs_done() {
  local n=${#PREF_CHANGED[@]}
  if [ "$n" -eq 0 ]; then
    ok "$1 ${DIM}· already set$RESET"
  else
    ok "$1 ${DIM}· $n changed$RESET"
    local c; for c in "${PREF_CHANGED[@]}"; do info "$c"; done
  fi
  PREF_TOTAL=0
  PREF_CHANGED=()
}

# Append a line to a file unless a line matching the given pattern is already
# there. The pattern is matched loosely so a previously-expanded form of the
# same line (e.g. $HOME already resolved to /Users/you) still counts as present.
append_once() {
  local file="$1" pattern="$2" line="$3"
  [ -f "$file" ] && grep -q "$pattern" "$file" && return 0
  printf '%s\n' "$line" >> "$file"
  case "$file" in "$HOME"/.zprofile|"$HOME"/.zshrc) SHELL_CHANGED=1 ;; esac
  ok "added to ${file/#$HOME/~}: $DIM$line$RESET"
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
  case "$file" in "$HOME"/.zprofile|"$HOME"/.zshrc) SHELL_CHANGED=1 ;; esac
  ok "added block to ${file/#$HOME/~}: $DIM$marker$RESET"
}

# notify <title> <body>. iTerm posts notifications itself when asked via its
# escape sequence, so they carry its icon; anywhere else a bare osascript
# notification (credited to Script Editor) is the best available.
notify() {
  if [ "$TTY" = 1 ] && [ "${TERM_PROGRAM:-}" = iTerm.app ]; then
    printf '\e]777;notify;%s;%s\a' "$1" "$2" > /dev/tty
  else
    osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null
  fi
}

SUDO_KEEPALIVE=''
cleanup() { [ -n "$SUDO_KEEPALIVE" ] && kill "$SUDO_KEEPALIVE" 2>/dev/null; set_title ''; }
on_interrupt() {
  [ "$TTY" = 1 ] && printf '\r\e[J' > /dev/tty
  emit ''
  warn "interrupted after $(fmt_secs $((SECONDS - START))); log: ${LOG/#$HOME/~}"
  cleanup
  exit 130
}
trap cleanup EXIT
trap on_interrupt INT TERM

# ==============================================================================
# Preflight
# ==============================================================================
emit ''
emit "$BOLD${CYAN}mac-setup$RESET  $DIM${REPO_DIR/#$HOME/~} · $(date '+%a %d %b %H:%M')$RESET"
emit "${DIM}preferences, Command Line Tools, Homebrew, background upgrades, git, .NET,$RESET"
emit "${DIM}Claude Code, Oh My Zsh, app preferences, iTerm, editors, Rokit, GitHub$RESET"
section "Preflight"
info "macOS $(sw_vers -productVersion) on $(uname -m), $(scutil --get ComputerName 2>/dev/null || hostname)"
info "log: ${LOG/#$HOME/~}"
if [ ! -t 0 ]; then
  fail "no terminal attached; sudo and the prompts below need one"
  exit 1
fi
if curl -fsI --max-time 5 https://github.com >/dev/null 2>&1; then
  ok "online"
else
  fail "no internet connection"
  exit 1
fi
FREE_GB=$(df -g / | awk 'NR == 2 { print $4 }')
if [ "${FREE_GB:-0}" -ge 20 ]; then
  ok "${FREE_GB}GB free on disk"
else
  warn "only ${FREE_GB}GB free; the casks alone need more than that"
fi
if pmset -g batt 2>/dev/null | grep -q 'AC Power'; then
  ok "on mains power"
else
  warn "on battery: this downloads a lot, plug in if you can"
fi

# This script is interactive, so sudo should prompt in the terminal. A stale
# askpass helper in the environment (the old autoupdate tap left one behind)
# makes every sudo fail with "no password was provided" instead.
unset SUDO_ASKPASS
# Ask for the password once, up front, and keep the sudo ticket alive until the
# script exits. Otherwise Homebrew, each .pkg cask and the keychain each prompt
# in turn, minutes apart, and a missed prompt fails that step.
info "your password is needed once, for sudo (Homebrew, .pkg installers)"
if sudo -p "  $CYAN?$RESET Password: " -v; then
  ok "sudo ticket held for the rest of the run"
else
  fail "sudo refused"
  exit 1
fi
( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
SUDO_KEEPALIVE=$!

# ==============================================================================
# System preferences
# ==============================================================================
section "System preferences"
chflags nohidden ~/Library
pref com.apple.finder AppleShowAllFiles -bool true
pref com.apple.finder ShowPathbar -bool true
pref com.apple.finder ShowStatusBar -bool true
pref com.apple.finder FXPreferredViewStyle -string 'Nlsv'   # list view
pref com.apple.finder _FXSortFoldersFirst -bool true
pref com.apple.finder FXDefaultSearchScope -string 'SCcf'   # search the current folder
pref com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
# Open new Finder windows in Downloads
pref com.apple.finder NewWindowTarget -string 'PfLo'
pref com.apple.finder NewWindowTargetPath -string "file://$HOME/Downloads/"
# Screenshots go to Downloads too, not the Desktop
pref com.apple.screencapture location -string "$HOME/Downloads"
prefs_done "Finder: list view, folders first, hidden files, opens in Downloads"
# Finder and Dock are restarted at the very end, not here: relaunching Finder
# opens a window that steals keyboard focus, which mangles anything being typed.

# Auto-hide the Dock, show/hide it instantly, no recent apps, slightly smaller
pref com.apple.dock autohide -bool true
pref com.apple.dock autohide-time-modifier -int 0
pref com.apple.dock show-recents -bool false
pref com.apple.dock tilesize -int 52
prefs_done "Dock: auto-hides instantly, no recents, size 52"

# Dark mode, always show scroll bars, show file extensions, stop macOS
# rewriting what's typed, and keep Spotlight out of the menu bar (Cmd-Space
# still works). Dark mode takes effect at the next login.
pref NSGlobalDomain AppleInterfaceStyle -string 'Dark'
pref NSGlobalDomain AppleShowScrollBars -string 'Always'
pref NSGlobalDomain AppleShowAllExtensions -bool true
pref NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
pref NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
pref -currentHost com.apple.Spotlight MenuItemHidden -int 1
prefs_done "System: dark mode, scroll bars, extensions, no auto-capitalise, no Spotlight icon"

# Trackpad: tap to click (all three keys are needed for it to stick everywhere)
pref com.apple.AppleMultitouchTrackpad Clicking -bool true
pref com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
pref -currentHost NSGlobalDomain com.apple.mouse.tapBehavior -int 1
prefs_done "Trackpad: tap to click"

# Bigger mouse pointer. Needs Full Disk Access for your terminal; if this is a
# no-op, set it by hand in System Settings > Accessibility > Display.
if pref com.apple.universalaccess mouseDriverCursorSize -float 2; then
  prefs_done "Pointer: larger"
else
  PREF_TOTAL=0; PREF_CHANGED=()
  warn "pointer size not set: the terminal lacks Full Disk Access (see README)"
fi

# The Finder sidebar entry stays manual. The only practical CLI for it, mysides,
# was disabled in homebrew-cask on 2025-10-13 for being unmaintained, and an
# installed-but-disabled package makes `brew upgrade` exit non-zero — which is
# what silently skipped every cask upgrade before.
mkdir -p "$HOME/Code"
ok "code directory: ${HOME/#$HOME/~}/Code"

# ==============================================================================
# Xcode Command Line Tools
# ==============================================================================
# Software Update can only offer CLT updates when the install is receipted. An
# unreceipted install — the directory exists but pkgutil has no record of it —
# is invisible to Software Update and silently never updates, while brew doctor
# keeps reporting a newer release is available. Reinstall only in that case;
# when the receipt is present this whole block is a no-op.
section "Command Line Tools"
if [ ! -d /Library/Developer/CommandLineTools ]; then
  info "not installed yet; the Homebrew installer takes care of that"
elif pkgutil --pkg-info=com.apple.pkg.CLTools_Executables >/dev/null 2>&1; then
  ok "installed and receipted; Software Update keeps them current"
else
  warn "no package receipt, so they never update; reinstalling (about 1GB)"
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
    xcode-select --install 2>/dev/null || true
    fail "Software Update offered no CLT package; finish the xcode-select dialog by hand"
  fi
  sudo rm -f "$CLT_MARKER"
fi

# Note: macOS updates are deliberately NOT installed here. `softwareupdate
# --install` on a macOS release reboots the machine, which would abandon the
# rest of this script. The auto-update settings in System Settings handle them;
# see the Command Line Tools section of the README.

# ==============================================================================
# Homebrew
# ==============================================================================
section "Homebrew"
if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
  step -i "Install Homebrew" /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Put brew on PATH for this session (Apple Silicon, then Intel fallback)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is not available; nothing after this can run"
  exit 1
fi
info "$(brew --version | head -1) at $(brew --prefix)"

# The Homebrew installer prints this line but doesn't add it; without it, new
# terminals on a fresh Mac have no `brew` on PATH.
append_once ~/.zprofile 'brew shellenv' "eval \"\$($(command -v brew) shellenv)\""

# Some casks (Steam, for one) are Intel-only and need Rosetta on Apple Silicon.
if [ "$(uname -m)" = arm64 ]; then
  if pgrep -q oahd; then
    ok "Rosetta 2 installed"
  else
    step "Install Rosetta 2" softwareupdate --install-rosetta --agree-to-license
  fi
fi

step "brew update" brew update
step "brew upgrade (formulae)" brew upgrade --formula

# App Store apps (the `mas` lines) need a signed-in App Store, and there's no
# way to check that from the command line any more, so ask. A quick "y" is the
# only cost when already signed in; otherwise the store is opened to sign in.
MAS_APPS=$(sed -n "s/^mas '\([^']*\)'.*/\1/p" "$REPO_DIR/Brewfile" | tr '\n' ' ')
if [ -n "$MAS_APPS" ]; then
  ask "Signed in to the App Store? Needed for: ${MAS_APPS% }[Y/n] "; read -r reply
  case "$reply" in
    n|N|no|NO)
      open -a "App Store"
      ask "Sign in there, then press Enter to continue "; read -r _
      ;;
  esac
fi

# brew bundle prints "Using <x>" for everything already installed; only the
# installs are interesting, so those lines are dropped from the live window
# and the installs counted. --adopt is implied, so apps already sitting in
# /Applications are taken over rather than refused.
BUNDLE_OUT=$(mktemp "${TMPDIR:-/tmp}/mac-setup.XXXXXX")
brew_bundle() {
  brew bundle --file="$REPO_DIR/Brewfile" --no-upgrade 2>&1 | tee "$BUNDLE_OUT" |
    grep --line-buffered -v '^Using '
  return "${PIPESTATUS[0]}"
}
step "brew bundle ($(grep -cE "^(brew|cask|mas) " "$REPO_DIR/Brewfile") entries)" brew_bundle
INSTALLED_COUNT=$(grep -c '^Installing ' "$BUNDLE_OUT" || true)
rm -f "$BUNDLE_OUT"

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
  step "brew upgrade sudo casks: ${SUDO_CASKS[*]}" brew upgrade --cask "${SUDO_CASKS[@]}"
fi

# ==============================================================================
# Homebrew background upgrades
# ==============================================================================
# A LaunchAgent runs config/brew-autoupdate.sh every 12 hours and at login. It
# replaces the domt4/autoupdate tap, which had no way to stop Homebrew 6 from
# upgrading self-updating casks (quitting iTerm, Claude, 1Password... to do
# it), and whose --sudo option was the source of the background password
# prompts. The script explains what it skips and why.
section "Background upgrades"
BAU_LABEL=com.andrewgunn.brew-autoupdate
BAU_DIR="$HOME/Library/Application Support/brew-autoupdate"
BAU_PLIST="$HOME/Library/LaunchAgents/$BAU_LABEL.plist"
BAU_LOG="$HOME/Library/Logs/brew-autoupdate.log"

# Retire the tap-based agent if it's still around, along with the ~/.zprofile
# warning that referenced its launchd label (a fresh one is appended below).
if brew tap 2>/dev/null | grep -qx 'domt4/autoupdate'; then
  brew autoupdate delete >/dev/null 2>&1
  brew untap domt4/autoupdate >/dev/null 2>&1
  brew untrust domt4/autoupdate >/dev/null 2>&1
  ok "removed the old domt4/autoupdate agent and tap"
fi
if [ -f ~/.zprofile ] && grep -qF 'launchctl list com.github.domt4.homebrew-autoupdate' ~/.zprofile; then
  sed -i '' '/^# brew-autoupdate: warn when the last run failed$/,/^fi$/d' ~/.zprofile
  ok "removed the old warning block from ~/.zprofile"
fi

mkdir -p "$BAU_DIR" "$HOME/Library/LaunchAgents"
install -m 755 "$REPO_DIR/config/brew-autoupdate.sh" "$BAU_DIR/brew-autoupdate"
cat > "$BAU_PLIST" <<PLIST
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
PLIST
ok "agent script and plist installed"

# (Re)load the agent. bootout kills a run in progress, so leave a running one
# alone: the script path is unchanged, so it picks up script changes next run,
# but plist changes wait for the next run.sh.
if launchctl print "gui/$(id -u)/$BAU_LABEL" 2>/dev/null | grep -q 'state = running'; then
  fail "brew-autoupdate agent not reloaded: a run is in progress, re-run later"
else
  launchctl bootout "gui/$(id -u)/$BAU_LABEL" 2>/dev/null
  step "Load the LaunchAgent (12-hourly and at login)" launchctl bootstrap "gui/$(id -u)" "$BAU_PLIST"
fi

# Failed runs would otherwise be silent. Warn at login shell startup instead;
# launchd keeps the last exit status, and reading it needs no permissions.
append_block_once ~/.zprofile 'brew-autoupdate (mac-setup): warn when the last run failed' <<ZPROFILE
# brew-autoupdate (mac-setup): warn when the last run failed
_bau_exit=\$(launchctl list $BAU_LABEL 2>/dev/null |
  awk -F'= ' '/LastExitStatus/ { gsub(/[; ]/, "", \$2); print \$2 }')
if [ -n "\$_bau_exit" ] && [ "\$_bau_exit" != "0" ]; then
  printf '\033[33mbrew autoupdate: last run failed (launchd status %s) — see ${BAU_LOG/#$HOME/~}\033[0m\n' "\$_bau_exit"
fi
unset _bau_exit
ZPROFILE

# ==============================================================================
# Git
# ==============================================================================
section "Git"
if [ -z "$(git config --global user.name || true)" ]; then
  ask "Git user name: "; read -r git_user_name
  git config --global user.name "$git_user_name"
fi
if [ -z "$(git config --global user.email || true)" ]; then
  ask "Git email address: "; read -r git_email_address
  git config --global user.email "$git_email_address"
fi
ok "identity: $(git config --global user.name) <$(git config --global user.email)>"
# Everything except the identity lives in config/gitconfig and is pulled in by
# reference, so editing the repo file is enough. Settings this script used to
# write directly into ~/.gitconfig would shadow the include, so drop them.
git config --global include.path "$REPO_DIR/config/gitconfig"
for key in init.defaultBranch pull.rebase fetch.prune alias.lg diff.tool difftool.prompt \
           difftool.bc.trustExitCode merge.tool mergetool.keepBackup mergetool.bc.trustExitCode; do
  git config --file ~/.gitconfig --unset-all "$key" 2>/dev/null || true
done
if git config --global --includes --get init.defaultBranch >/dev/null; then
  ok "config/gitconfig included (Beyond Compare, git lg, prune)"
else
  fail "config/gitconfig is not being read"
fi
# ~/.config/git/ignore is read by git with no further configuration.
mkdir -p ~/.config/git
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  append_once ~/.config/git/ignore "^$(printf '%s' "$line" | sed 's/[.*[\]/\\&/g')\$" "$line"
done < "$REPO_DIR/config/gitignore"
ok "global ignore file in place"

# ==============================================================================
# .NET
# ==============================================================================
section ".NET"
if command -v dotnet >/dev/null 2>&1; then
  info "SDK $(dotnet --version 2>/dev/null)"
  step "Trust the HTTPS development certificate" dotnet dev-certs https --trust
  step "Aspire project templates" dotnet new install Aspire.ProjectTemplates --force
  for tool in dotnet-ef dotnet-reportgenerator-globaltool dotnet-sonarscanner \
              ilspycmd Microsoft.Playwright.CLI Verify.Tool; do
    step "$tool" dotnet tool update --global "$tool"
  done
  # shellcheck disable=SC2016  # $HOME is deliberately written literally
  append_once ~/.zprofile '\.dotnet/tools' 'export PATH="$PATH:$HOME/.dotnet/tools"'
else
  fail ".NET skipped: dotnet not on PATH (did the dotnet-sdk cask install?)"
fi

# ==============================================================================
# Claude Code (native installer — no Node/npm, auto-updates itself)
# ==============================================================================
section "Claude Code"
if [ -x "$HOME/.local/bin/claude" ] || command -v claude >/dev/null 2>&1; then
  ok "installed, $(claude --version 2>/dev/null | awk '{ print $1; exit }'); it updates itself"
else
  step "Install Claude Code" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi
# shellcheck disable=SC2016  # $HOME is deliberately written literally
append_once ~/.zprofile '\.local/bin' 'export PATH="$PATH:$HOME/.local/bin"'

# ==============================================================================
# Oh My Zsh (unattended: don't switch shell or launch zsh mid-script)
# ==============================================================================
section "Oh My Zsh"
if [ -d "$HOME/.oh-my-zsh" ]; then
  ok "installed"
else
  step "Install Oh My Zsh" env RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ -d "$P10K_DIR" ]; then
  ok "powerlevel10k theme present"
else
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
    ok "installed the finished p10k config from the repo"
  fi
  append_once "$HOME/.zshrc" '\.p10k\.zsh' \
    '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
  ok "zshrc: powerlevel10k theme, syntax highlighting, p10k config sourced"
else
  fail "zshrc is missing; the Oh My Zsh install should have created it"
fi

# ==============================================================================
# App preferences: Rectangle, Stats, SmoothScroll
# ==============================================================================
section "App preferences"
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
pref com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
pref com.knollsoft.Rectangle allowAnyShortcut -bool true
pref com.knollsoft.Rectangle launchOnLogin -bool true
pref com.knollsoft.Rectangle hideMenubarIcon -bool true
prefs_done "Rectangle: launches at login, no menu bar icon, any shortcut allowed"

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
ok "Rectangle shortcuts: ^⌥ halves/maximise, ^⌥1-3 thirds, ^⌥⇧ two-thirds"

pref eu.exelban.Stats Battery_state -bool false
pref eu.exelban.Stats LaunchAtLoginNext -bool true
prefs_done "Stats: launches at login, battery hidden"

# Only these two behavioural keys: the SmoothScroll licence lives outside this
# repo on purpose, so nothing here reads or writes it.
pref com.galambalazs.SmoothScroll showMenuBarIcon -bool false
pref com.galambalazs.SmoothScroll reverseWheelDirection -bool true
pref com.galambalazs.SmoothScroll launchOnLogin -bool true
prefs_done "SmoothScroll: login item, reversed wheel, no menu bar icon"

# ==============================================================================
# iTerm
# ==============================================================================
section "iTerm"
if pgrep -xq iTerm2 || pgrep -xq iTerm; then
  fail "iTerm settings skipped: it's running and would overwrite them (use Terminal.app)"
else
  pref com.googlecode.iterm2 PromptOnQuit -bool false
  pref com.googlecode.iterm2 OnlyWhenMoreTabs -bool false
  pref com.googlecode.iterm2 UseLionStyleFullscreen -bool false
  pref com.googlecode.iterm2 ShowFullScreenTabBar -bool false
  pref com.googlecode.iterm2 DimInactiveSplitPanes -bool false
  prefs_done "iTerm: no quit prompt, own fullscreen, no pane dimming"

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
          "$ITERM_PLIST" 2>/dev/null && ok "default profile: Fira Code 18 with ligatures"
        break
      fi
      idx=$((idx + 1))
    done
    killall cfprefsd 2>/dev/null
  else
    fail "iTerm font not set: no preferences yet (open iTerm once, quit, re-run)"
  fi
fi

# ==============================================================================
# Editors
# ==============================================================================
# Both CLIs accept repeated --install-extension flags, so one call per editor.
# --force upgrades an already-installed extension rather than skipping it.
section "Editors"
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
  step "VS Code: ${#VSCODE_EXTENSIONS[@]} extensions" install_extensions code "${VSCODE_EXTENSIONS[@]}"
else
  info "VS Code not on PATH; extensions skipped"
fi
if command -v cursor >/dev/null 2>&1; then
  step "Cursor: ${#CURSOR_EXTENSIONS[@]} extensions" install_extensions cursor "${CURSOR_EXTENSIONS[@]}"
else
  info "Cursor not on PATH; extensions skipped"
fi

# ==============================================================================
# Rokit (Roblox toolchain manager; its installer also wires up ~/.zshenv)
# ==============================================================================
section "Rokit"
if [ -x "$HOME/.rokit/bin/rokit" ]; then
  ok "installed; it updates itself with ${DIM}rokit self-update${RESET}"
else
  step "Install Rokit" bash -c \
    'curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash'
fi

# ==============================================================================
# GitHub: SSH key, CLI sign-in, key upload
# ==============================================================================
section "GitHub"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ -f "$HOME/.ssh/github" ]; then
  ok "key exists: ${HOME/#$HOME/~}/.ssh/github"
else
  info "generating an ed25519 key; choose a passphrase when asked"
  step -i "Generate the GitHub SSH key" ssh-keygen -t ed25519 -C github -f "$HOME/.ssh/github"
fi
append_block_once "$HOME/.ssh/config" 'IdentityFile ~/.ssh/github' <<'SSHCONFIG'
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/github
SSHCONFIG
chmod 600 "$HOME/.ssh/config"
if ssh-add --apple-use-keychain "$HOME/.ssh/github" 2>/dev/null; then
  ok "key loaded into the agent and keychain"
else
  warn "key not added to the agent; later: ssh-add --apple-use-keychain ~/.ssh/github"
fi

# The browser OAuth flow can't be scripted, but it can be started from here so
# it isn't left as homework. The key is uploaded once signed in, unless the
# account already has it.
GH_USER=''
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GH_USER=$(gh api user -q .login 2>/dev/null)
    ok "GitHub CLI signed in as ${GH_USER:-?}"
  else
    ask "Sign in to GitHub in the browser now? [Y/n] "; read -r reply
    case "$reply" in
      n|N|no|NO) info "skipped; later: gh auth login" ;;
      *)
        if step -i "gh auth login" gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key; then
          GH_USER=$(gh api user -q .login 2>/dev/null)
        fi
        ;;
    esac
  fi
  if [ -n "$GH_USER" ] && [ -f "$HOME/.ssh/github.pub" ]; then
    KEY_BODY=$(awk '{ print $2 }' "$HOME/.ssh/github.pub")
    if gh ssh-key list 2>/dev/null | grep -qF "$KEY_BODY"; then
      ok "this key is on the $GH_USER account"
    else
      step "Upload the key to GitHub" gh ssh-key add "$HOME/.ssh/github.pub" --title "$(scutil --get ComputerName 2>/dev/null || hostname)"
    fi
  fi
else
  info "gh not on PATH; sign in later with gh auth login"
fi
close_section

# ==============================================================================
# Apply the Finder and Dock settings written at the top. Done last, on purpose:
# relaunching Finder opens a window that takes keyboard focus, which mangles any
# password being typed if it happens mid-script.
# ==============================================================================
killall Finder 2>/dev/null
killall Dock 2>/dev/null
killall SystemUIServer 2>/dev/null   # picks up the screenshot location

# ==============================================================================
# Summary
# ==============================================================================
ELAPSED=$(fmt_secs $((SECONDS - START)))
emit ''
emit "$DIM$(repeat "$G_RULE" "$COLS")$RESET"
if [ ${#FAILED[@]} -gt 0 ]; then
  emit "  $RED$G_FAIL$RESET $BOLD${#FAILED[@]} failed$RESET · $ELAPSED · $INSTALLED_COUNT installed"
  for f in "${FAILED[@]}"; do emit "      $RED$G_FAIL$RESET $f"; done
  info "details: ${LOG/#$HOME/~}"
  SUMMARY="${#FAILED[@]} step(s) failed in $ELAPSED"
else
  emit "  $GREEN$G_OK$RESET ${BOLD}All done$RESET · $ELAPSED · $INSTALLED_COUNT installed · 0 failed"
  SUMMARY="All done in $ELAPSED"
fi

# Where the time went: one bar per section, scaled to the slowest, only for
# sections that took a noticeable amount of time.
MAX_SECS=1
for s in "${SECTION_SECS[@]}"; do [ "$s" -gt "$MAX_SECS" ] && MAX_SECS=$s; done
if [ "$MAX_SECS" -ge 5 ]; then
  measure
  BAR_MAX=$((COLS - 36)); [ "$BAR_MAX" -gt 30 ] && BAR_MAX=30; [ "$BAR_MAX" -lt 8 ] && BAR_MAX=8
  emit ''
  emit "  ${BOLD}Where the time went$RESET"
  i=0
  while [ "$i" -lt "${#SECTION_NAMES[@]}" ]; do
    s=${SECTION_SECS[$i]}
    if [ "$s" -ge 2 ]; then
      bar=$((s * BAR_MAX / MAX_SECS)); [ "$bar" -lt 1 ] && bar=1
      emit "$(printf '    %-20s %6s  %s%s%s' "${SECTION_NAMES[$i]}" "$(fmt_secs "$s")" "$CYAN" "$(repeat "$G_BAR" "$bar")" "$RESET")"
    fi
    i=$((i + 1))
  done
fi

emit ''
emit "  ${BOLD}Still yours to do$RESET $DIM(see Manual steps in the README)$RESET"
if [ -n "$GH_USER" ]; then
  ok "GitHub: signed in as $GH_USER, SSH key on the account"
else
  todo "sign in to GitHub and upload the key: ${DIM}gh auth login && gh ssh-key add ~/.ssh/github.pub${RESET}"
fi
if command -v bcomp >/dev/null 2>&1; then
  ok "Beyond Compare command line tools installed"
else
  todo "Beyond Compare > Install Command Line Tools (for git diff)"
fi
if [ "$(defaults read com.apple.universalaccess mouseDriverCursorSize 2>/dev/null)" = 2 ]; then
  ok "pointer size set"
else
  todo "System Settings > Accessibility > Display: larger pointer"
fi
[ -f "$HOME/.p10k.zsh" ] || todo "run ${DIM}p10k configure${RESET} in a new terminal"
todo "drag ~/Code into the Finder sidebar"
todo "1Password, iTerm key mappings, Rider settings"
emit ''
if [ "$SHELL_CHANGED" = 1 ]; then
  info "shell config changed: run ${RESET}exec zsh${DIM} here, or open a new terminal"
  emit ''
fi

# A fresh-Mac run is 20-40 minutes of downloads and nobody watches all of it;
# ring and notify so they know it's done. A quick re-run doesn't need either.
if [ $((SECONDS - START)) -ge 120 ]; then
  [ "$TTY" = 1 ] && printf '\a'
  notify "mac-setup" "$SUMMARY"
fi
exit 0
