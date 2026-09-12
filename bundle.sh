#!/bin/sh
# Builds "Comic Book Optimizer.app" — SwiftUI needs a real bundle to behave like an app.
set -e
swift build -c release
APP="Comic Book Optimizer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ComicOptimizer "$APP/Contents/MacOS/"

# Liquid Glass icon: actool renders AppIcon.icon into Assets.car (macOS 26 does the
# glass material at runtime) plus a flat AppIcon.icns fallback for older systems.
actool --output-format human-readable-text --notices --warnings \
  --app-icon AppIcon --platform macosx --target-device mac \
  --minimum-deployment-target 26.0 \
  --output-partial-info-plist "$APP/Contents/Resources/icon.plist" \
  --compile "$APP/Contents/Resources" AppIcon.icon > /dev/null
rm "$APP/Contents/Resources/icon.plist"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Comic Book Optimizer</string>
  <key>CFBundleExecutable</key><string>ComicOptimizer</string>
  <key>CFBundleIdentifier</key><string>local.comic-book-optimizer</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "→ $APP"
