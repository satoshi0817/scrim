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
swift build -c release --product Sheerpane "${flags[@]}"
bin_path="$(swift build -c release --show-bin-path "${flags[@]}")"
app="build/Sheerpane.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/Sheerpane" "$app/Contents/MacOS/Sheerpane"
cp Resources/Sheerpane/Info.plist "$app/Contents/Info.plist"
cp Sources/SheerpaneAssets/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Sources/SheerpaneAssets/Resources/MenuBarTemplate.pdf "$app/Contents/Resources/"
cp Sources/SheerpaneAssets/Resources/MenuBarWarningTemplate.pdf "$app/Contents/Resources/"
cp -R "$bin_path/Sheerpane_SheerpaneAssets.bundle" "$app/Contents/Resources/"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict --verbose=2 "$app"
echo "Built $app"
