#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
flags=()
if [[ $# -eq 1 && "$1" == "--trial" ]]; then
    flags=(-Xswiftc -DTRIAL_DIAGNOSTICS)
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--trial]" >&2
    exit 2
fi
# TCC binds Input Monitoring grants to the designated code requirement. An
# ad-hoc signature changes that requirement on every build and breaks grants.
identity="${SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$identity" || "$identity" == "-" ]]; then
    echo "A stable code-signing identity is required. Set SIGNING_IDENTITY to an installed certificate." >&2
    exit 1
fi
swift build -c release --product Scrim "${flags[@]}"
bin_path="$(swift build -c release --show-bin-path "${flags[@]}")"
app="build/Scrim.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/Scrim" "$app/Contents/MacOS/Scrim"
cp Resources/Scrim/Info.plist "$app/Contents/Info.plist"
cp Sources/ScrimAssets/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Sources/ScrimAssets/Resources/MenuBarTemplate.pdf "$app/Contents/Resources/"
cp Sources/ScrimAssets/Resources/MenuBarWarningTemplate.pdf "$app/Contents/Resources/"
cp -R "$bin_path/Scrim_ScrimAssets.bundle" "$app/Contents/Resources/"
codesign --force --sign "$identity" --options runtime --entitlements Resources/Scrim/Scrim.entitlements --timestamp "$app"
codesign --verify --strict --verbose=2 "$app"
echo "Built $app"
