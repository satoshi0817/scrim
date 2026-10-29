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
swift build -c release --product Chira "${flags[@]}"
bin_path="$(swift build -c release --show-bin-path "${flags[@]}")"
app="build/Chira.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/Chira" "$app/Contents/MacOS/Chira"
cp Resources/Chira/Info.plist "$app/Contents/Info.plist"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict --verbose=2 "$app"
echo "Built $app"
