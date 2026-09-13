#!/bin/sh
# Background Homebrew upgrades. run.sh installs this to
# ~/Library/Application Support/brew-autoupdate/ and schedules it with a
# LaunchAgent (com.andrewgunn.brew-autoupdate) every 12 hours and at login.
#
# Two things are deliberately left alone:
#
#   - Casks marked `auto_updates true` (Chrome, iTerm, Claude, 1Password...).
#     Homebrew 6 upgrades these by default whenever the tap is ahead of the
#     installed app, and does it by quitting the running app to swap the
#     bundle. HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS restores the old
#     behaviour: those apps update themselves, in their own time.
#
#   - Casks in SUDO_CASKS. Their installers need root, and a launchd job has no
#     keyboard to ask for a password on. run.sh reads this list (via
#     --print-sudo-casks) and upgrades them while someone is at the machine.
#
# Exits non-zero if any stage failed. ~/.zprofile checks launchd for that and
# prints a warning at the next shell start.
set -u

SUDO_CASKS="dotnet-sdk"
LOG="$HOME/Library/Logs/brew-autoupdate.log"

if [ "${1:-}" = "--print-sudo-casks" ]; then
  printf '%s\n' "$SUDO_CASKS"
  exit 0
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1
export HOMEBREW_NO_AUTO_UPDATE=1   # `brew update` is run explicitly below
export HOMEBREW_NO_ENV_HINTS=1

if ! command -v brew >/dev/null 2>&1; then
  echo "!!! brew is not on PATH"
  exit 1
fi

# launchd appends to the log forever; keep the last ~1MB once it passes 5MB.
# Done before printing anything so this run's own output isn't discarded.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 5000000 ]; then
  tail -c 1000000 "$LOG" > "$LOG.tmp" && cat "$LOG.tmp" > "$LOG"
  rm -f "$LOG.tmp"
fi

status=0
echo
echo "==> brew autoupdate: $(date)"
brew update            || status=1
brew upgrade --formula || status=1

# Everything outdated except the sudo casks. Self-updating casks are already
# excluded from this list by HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS.
casks=""
for cask in $(brew outdated --cask --quiet); do
  case " $SUDO_CASKS " in
    *" $cask "*) echo "==> Skipping $cask: needs sudo, run ./run.sh to upgrade it" ;;
    *)           casks="$casks $cask" ;;
  esac
done
if [ -n "$casks" ]; then
  # shellcheck disable=SC2086  # word-splitting the list is the point
  brew upgrade --cask $casks || status=1
fi

brew cleanup || status=1

if [ "$status" -ne 0 ]; then
  echo "!!! brew autoupdate finished with errors"
  # Best effort: launchd jobs can usually post via osascript, but it's not
  # guaranteed, hence the ~/.zprofile warning as the reliable channel.
  osascript -e 'display notification "See ~/Library/Logs/brew-autoupdate.log" with title "brew autoupdate failed"' 2>/dev/null
fi
exit "$status"
