#!/bin/zsh
# Builds "DaVinci Storage.app" into ~/Applications (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product DaVinciStorageApp
BIN="$(swift build -c release --show-bin-path)/DaVinciStorageApp"

APP="$HOME/Applications/DaVinci Storage.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP.tmp"
mkdir -p "$APP.tmp/Contents/MacOS" "$APP.tmp/Contents/Resources"
cp "$BIN" "$APP.tmp/Contents/MacOS/DaVinciStorageApp"
cp Resources/Info.plist "$APP.tmp/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP.tmp/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP.tmp"

# Replace the previous build (old copy goes to the Trash, not rm).
if [ -d "$APP" ]; then
  osascript -e "tell application \"Finder\" to delete POSIX file \"$APP\"" >/dev/null
fi
mv "$APP.tmp" "$APP"
codesign --verify --verbose=1 "$APP"
touch "$APP"   # let Finder/Dock pick up the new icon
echo "Installed: $APP"
