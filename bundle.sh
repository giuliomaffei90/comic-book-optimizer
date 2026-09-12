#!/bin/sh
# Builds "Comic Book Optimizer.app" — SwiftUI needs a real bundle to behave like an app.
set -e
swift build -c release
APP="Comic Book Optimizer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ComicOptimizer "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Comic Book Optimizer</string>
  <key>CFBundleExecutable</key><string>ComicOptimizer</string>
  <key>CFBundleIdentifier</key><string>local.comic-book-optimizer</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "→ $APP"
