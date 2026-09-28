#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")"
app_path="WallpaperNoDim.app"
sdk_path="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ ! -d "$sdk_path" ]]; then
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fi
mkdir -p "$app_path/Contents/MacOS"
xcrun --sdk macosx clang -isysroot "$sdk_path" -fobjc-arc \
  -framework AppKit -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework ServiceManagement \
  WallpaperNoDimTest.m WallpaperImage.m -o "$app_path/Contents/MacOS/WallpaperNoDim"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
