#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
destination="$HOME/Applications/MacBar.app"
if [[ -e "$destination" ]]; then
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
  if [[ "$bundle_id" != dev.local.MacBar ]]; then
    print -u2 'Refusing to replace a different application named MacBar.'
    exit 1
  fi
  if pgrep -f "$destination/Contents/MacOS/MacBar" >/dev/null; then
    print -u2 'Quit MacBar from its menu, then run this command again.'
    exit 1
  fi
fi
mkdir -p "$HOME/Applications"
ditto build/MacBar.app "$destination"
print -r -- "Installed: $destination"
