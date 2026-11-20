#!/bin/sh
set -eu
cd "$(dirname "$0")"

app="myBro.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" ".build/modules"
swiftc -parse-as-library -O -module-cache-path .build/modules Sources/*.swift \
  -target "$(uname -m)-apple-macos14.0" -o "$app/Contents/MacOS/myBro"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Search*.png "$app/Contents/Resources/"
codesign --force --sign - "$app"
