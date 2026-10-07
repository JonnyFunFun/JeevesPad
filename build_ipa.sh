#!/bin/bash
# Build script for Jeeves - creates IPA for jailbroken devices

set -e

echo "Building Jeeves..."
make clean
make

APP_PATH=".theos/obj/debug/Jeeves.app"

echo "Signing with ldid..."
ldid -Sentitlements.plist "$APP_PATH/Jeeves"

echo "Copying resources..."
cp -r Resources/* "$APP_PATH/" 2>/dev/null || true

echo "Creating IPA..."
rm -rf Payload
mkdir -p Payload
cp -r "$APP_PATH" Payload/
rm -f Jeeves.ipa
zip -r Jeeves.ipa Payload

echo "Cleaning up..."
rm -rf Payload

echo ""
echo "Done! Jeeves.ipa created."
echo ""
echo "To install on jailbroken iPad with AppSync Unified:"
echo "  Option 1: Use Filza to install the IPA"
echo "  Option 2: SCP to device and use 'appinst' or 'ipainstaller'"
echo "  Option 3: Use iOS App Signer (Mac) + Apple Configurator"
echo ""
echo "DO NOT use Sideloadly - it re-signs and breaks updates!"
