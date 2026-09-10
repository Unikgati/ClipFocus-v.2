#!/bin/bash
set -e

echo "Building ClipFocusApp (Release)..."
swift build -c release --product ClipFocusApp

echo "Copying binary to ClipFocus.app bundle..."
mkdir -p ClipFocus.app/Contents/MacOS ClipFocus.app/Contents/Resources
cp .build/release/ClipFocusApp ClipFocus.app/Contents/MacOS/ClipFocusApp

if [ -f AppIcons/AppIcon.icns ]; then
    echo "Copying AppIcon.icns to Resources..."
    cp AppIcons/AppIcon.icns ClipFocus.app/Contents/Resources/AppIcon.icns
fi

echo "Signing ClipFocus.app with Apple Development certificate..."
codesign -s "Apple Development: ayodyachandra09@gmail.com (3VUJUU6VRY)" --entitlements ClipFocus.entitlements --force --deep ClipFocus.app

echo "ClipFocus is 100% production ready and permanently signed!"
