#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/local
./scripts/swiftc.sh -O -module-name MacBar Sources/MacBar/*.swift -o .build/local/MacBar
app="$PWD/build/MacBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/local/MacBar "$app/Contents/MacOS/MacBar"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacBar</string>
<key>CFBundleIdentifier</key><string>dev.local.MacBar</string>
<key>CFBundleName</key><string>MacBar</string>
<key>CFBundleDisplayName</key><string>MacBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.10</string>
<key>CFBundleVersion</key><string>16</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
./scripts/sign.sh "$app"
print -r -- "$app"
