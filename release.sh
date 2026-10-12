#!/bin/zsh
# Build a universal (Apple Silicon + Intel) Release, zip it, and publish it as a GitHub release.
# Usage: ./release.sh   (the version comes from MARKETING_VERSION in project.yml)
set -euo pipefail
cd "$(dirname "$0")"

version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
tag="v$version"
zip="build/DesktopPet-$version.zip"

if gh release view "$tag" >/dev/null 2>&1; then
  echo "Release $tag already exists. Bump MARKETING_VERSION in project.yml first." >&2
  exit 1
fi

xcodegen generate --quiet
# Ad-hoc signed: there's no Developer ID certificate, so the app can't be notarized.
xcodebuild -project DesktopPet.xcodeproj -scheme DesktopPet -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build/release -quiet \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  clean build

app=build/release/Build/Products/Release/DesktopPet.app
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

gh release create "$tag" "$zip" --title "Desktop Pet $version" --generate-notes
echo "Published $tag"
