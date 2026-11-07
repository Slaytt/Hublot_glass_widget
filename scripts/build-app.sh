#!/bin/sh
# Builds build/Hublot.app from the Swift package.
set -e

cd "$(dirname "$0")/.."
swift build -c release

app="build/Hublot.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Hublot" "$app/Contents/MacOS/Hublot"
cp Resources/Info.plist "$app/Contents/Info.plist"
# codesign refuses files carrying extended attributes such as Finder information.
xattr -cr "$app"
codesign --force --sign - "$app"

echo "Built $app"
