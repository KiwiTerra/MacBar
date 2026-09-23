#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/.build/ZoomFixture.app"
mkdir -p "$app/Contents/MacOS"
./scripts/swiftc.sh Tests/Integration/ZoomFixture.swift -o "$app/Contents/MacOS/ZoomFixture"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ZoomFixture</string>
<key>CFBundleIdentifier</key><string>dev.local.MacBar.ZoomFixture</string>
<key>CFBundleName</key><string>MacBar Zoom Test</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
