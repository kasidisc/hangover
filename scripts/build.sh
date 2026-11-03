#!/bin/bash
# Builds build/Hangover.app as a universal (Apple silicon + Intel) app with plain swiftc.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Hangover.app
rm -rf "$APP" .build/arch && mkdir -p .build/arch "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" Sources/Core/*.swift Sources/App/*.swift \
        -o ".build/arch/Hangover-$arch" 2>&1 | grep -v "libswiftCompatibilityPacks" || true
    [ -f ".build/arch/Hangover-$arch" ] || { echo "build failed for $arch"; exit 1; }
done
lipo -create .build/arch/Hangover-arm64 .build/arch/Hangover-x86_64 -output "$APP/Contents/MacOS/Hangover"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for f in ui.html AppIcon.icns; do [ -f "Resources/$f" ] && cp "Resources/$f" "$APP/Contents/Resources/"; done
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Hangover Self-Signed"; then
    codesign --force --options runtime --sign "Hangover Self-Signed" "$APP"
else
    echo "warning: 'Hangover Self-Signed' identity not found; signing ad-hoc (run scripts/make-signing-cert.sh)"
    codesign --force --sign - "$APP"
fi
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/Hangover"))"
