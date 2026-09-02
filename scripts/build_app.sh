#!/usr/bin/env bash
# Build eduCLIMBER Converter.app from the Swift package.
#   ./scripts/build_app.sh            universal (Apple Silicon + Intel)
#   ARCHS=native ./scripts/build_app.sh   this Mac's architecture only (faster)
#
# Requires Xcode (or the Command Line Tools). Output: build/eduCLIMBER Converter.app
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="eduCLIMBER Converter"
BINARY_NAME="eduCLIMBER-Converter"
BUNDLE_ID="net.whittiercity.educlimberconverter"
VERSION="1.1.0"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This builds a Mac app and must run on macOS." >&2
    exit 1
fi

if [[ "${ARCHS:-universal}" == "universal" ]]; then
    BUILD_FLAGS=(--arch arm64 --arch x86_64)
else
    BUILD_FLAGS=()
fi

echo "==> Testing"
swift test

echo "==> Building (release)"
swift build -c release "${BUILD_FLAGS[@]}"
BINARY="$(swift build -c release "${BUILD_FLAGS[@]}" --show-bin-path)/$BINARY_NAME"
test -x "$BINARY" || { echo "Build produced no binary at $BINARY" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$BINARY_NAME"
cp Resources/Data_Table.csv "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Without one, recent macOS refuses to open the app with
# "is damaged and can't be opened" rather than the normal unidentified-developer
# prompt. This is not an Apple Developer signature -- see README for first launch.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature OK"

echo "==> Zipping"
ZIP="$OUT_DIR/eduCLIMBER-Converter-macos.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Done:"
echo "  App: $APP"
echo "  Zip: $ZIP"
echo "Drag the app into /Applications. On first launch, right-click it and choose"
echo "Open, then click Open in the dialog (once per Mac)."
