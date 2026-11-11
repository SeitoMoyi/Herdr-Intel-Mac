#!/bin/bash
# Installs or updates Herdr from this repo's latest GitHub release, then
# updates herdr-core from the official server.
#
#   ./update-herdr.sh              install or update now
#   ./update-herdr.sh schedule     also check every day at 10:00 (and at login)
#   ./update-herdr.sh unschedule   stop the daily check
#
# Set REPO below (or HERDR_INTEL_REPO) to your GitHub "owner/name".
set -euo pipefail

REPO="${HERDR_INTEL_REPO:-SeitoMoyi/Herdr-Intel-Mac}"

app="$HOME/Applications/Herdr.app"
bin="$HOME/.local/bin"
label=local.herdr-intel.update
agent="$HOME/Library/LaunchAgents/$label.plist"
log="$HOME/Library/Logs/herdr-intel-update.log"

say() { printf '%s\n' "$*"; }
fail() { say "error: $*" >&2; exit 1; }
notify() { osascript -e "display notification \"$1\" with title \"Herdr\"" >/dev/null 2>&1 || true; }

case "${1:-update}" in
  schedule)
    self="$bin/herdr-intel-update"
    mkdir -p "$bin" "$(dirname "$agent")" "$(dirname "$log")"
    [ "$0" -ef "$self" ] || cp "$0" "$self"
    chmod +x "$self"
    cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$self</string></array>
  <key>EnvironmentVariables</key><dict><key>HERDR_INTEL_REPO</key><string>$REPO</string></dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log</string>
  <key>StandardErrorPath</key><string>$log</string>
</dict></plist>
PLIST
    launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$agent"
    say "Daily check scheduled ($self). Log: $log"
    exit 0 ;;
  unschedule)
    launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
    rm -f "$agent"
    say "Daily check removed."
    exit 0 ;;
  update) ;;
  *) fail "usage: $0 [update|schedule|unschedule]" ;;
esac

case $REPO in OWNER/* | "") fail "set REPO in $0 (or HERDR_INTEL_REPO) to your GitHub owner/name" ;; esac

update_core() {
  local hc=""
  if [ -x "$bin/hc" ]; then hc="$bin/hc"; elif command -v hc >/dev/null 2>&1; then hc=$(command -v hc); fi
  if [ -z "$hc" ]; then
    say "herdr-core isn't installed; Herdr offers to install it when it opens."
    return 0
  fi
  "$hc" update || say "note: hc update failed (a package manager may own the core)."
}

say "$(date '+%F %T') checking $REPO"
latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") \
  || fail "cannot reach github.com/$REPO"
tag=${latest##*/}
case $tag in v[0-9]*) ;; *) fail "$REPO has no release yet" ;; esac
version=${tag#v}
have=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)

if [ "$have" = "$version" ] && [ "${FORCE:-0}" != 1 ]; then
  say "Herdr $have is up to date."
  update_core
  exit 0
fi

say "Installing Herdr $version (have: ${have:-none})"
mkdir -p "$HOME/Applications" "$bin"
# Stage beside the app so the final swap is a same-volume rename.
stage="$HOME/Applications/.herdr-intel-staging"
rm -rf "$stage"
mkdir -p "$stage"
trap 'rm -rf "$stage"' EXIT

base="https://github.com/$REPO/releases/download/$tag"
curl -fsSL --retry 2 "$base/herdr-app-macos-x86_64.tar.gz" -o "$stage/herdr-app-macos-x86_64.tar.gz"
curl -fsSL --retry 2 "$base/SHA256SUMS" -o "$stage/SHA256SUMS"
(cd "$stage" && shasum -a 256 -c SHA256SUMS) || fail "checksum mismatch; not installing"
tar -xzf "$stage/herdr-app-macos-x86_64.tar.gz" -C "$stage"
new="$stage/Herdr.app"
out=$("$new/Contents/MacOS/Herdr" --version) || fail "the downloaded app doesn't run on this Mac"
[ "$out" = "herdr-app $version" ] || fail "the download says '$out', expected $version"

# Finder doesn't inherit a shell's PATH; hc must still be found (as upstream's installer does).
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:PATH string $bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" "$new/Contents/Info.plist"
codesign --force --sign - "$new"
codesign --verify --strict "$new"

# Swap: a running Herdr keeps its old files until it quits.
if [ -e "$app" ]; then mv "$app" "$stage/Herdr.old.app"; fi
mv "$new" "$app"
ln -sfn "$app/Contents/MacOS/Herdr" "$bin/herdr-app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" || true

update_core
say "Installed Herdr $version in $app."
if pgrep -f "$app/Contents/MacOS/Herdr" >/dev/null 2>&1; then
  notify "Herdr $version is installed. Quit and reopen Herdr to use it."
else
  notify "Herdr $version is installed."
fi
