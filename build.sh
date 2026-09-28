#!/bin/zsh
# Regenerate the Xcode project, build, install to /Applications and relaunch.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project DesktopPet.xcodeproj -scheme DesktopPet -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build

pkill -x DesktopPet 2>/dev/null || true
rm -rf /Applications/DesktopPet.app
cp -R build/Build/Products/Release/DesktopPet.app /Applications/
open /Applications/DesktopPet.app
echo "Installed and launched /Applications/DesktopPet.app"
