#!/bin/bash
set -euo pipefail
taskport_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$taskport_root"
taskport_check=false
if [[ "$#" == 1 && "$1" == --check ]]; then
  taskport_check=true
elif [[ "$#" != 0 ]]; then
  echo 'Usage: bash scripts/build.sh [--check]' >&2
  exit 2
fi
taskport_flags=(--configuration release -debug-info-format none
  -Xswiftc -file-prefix-map -Xswiftc "$taskport_root=/src/taskport"
  -Xswiftc -file-compilation-dir -Xswiftc /src/taskport
  -Xcc "-ffile-prefix-map=$taskport_root=/src/taskport"
  -Xcc -fdebug-compilation-dir=/src/taskport)
bash scripts/swift.sh build "${taskport_flags[@]}"
taskport_bin="$(bash scripts/swift.sh build "${taskport_flags[@]}" --show-bin-path)"
# Fresh staging prevents old resources, logs, or debug artifacts entering the app.
mkdir -p "$taskport_root/build"
taskport_stage="$(mktemp -d "$taskport_root/build/.package.XXXXXX")"
trap 'rm -rf "$taskport_stage"' EXIT
taskport_app="$taskport_stage/Taskport.app"
mkdir -p "$taskport_app/Contents/MacOS" "$taskport_app/Contents/Resources"
cp "$taskport_bin/Taskport" "$taskport_app/Contents/MacOS/Taskport"
cp "$taskport_bin/taskport-cli" "$taskport_app/Contents/MacOS/taskport-cli"
cp Resources/Info.plist "$taskport_app/Contents/Info.plist"
xcrun actool Resources/Taskport-Pills.icon \
    --compile "$taskport_app/Contents/Resources" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist "$taskport_stage/icon-info.plist" \
    --app-icon Taskport-Pills --include-all-app-icons \
    --enable-on-demand-resources NO --development-region en \
    --target-device mac --minimum-deployment-target 14.0 --platform macosx
/usr/libexec/PlistBuddy -c "Merge '$taskport_stage/icon-info.plist'" "$taskport_app/Contents/Info.plist"
ditto "$taskport_bin/GhosttyKit_GhosttyTerminal.bundle" "$taskport_app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle"
cp LICENSE THIRD_PARTY_NOTICES.md "$taskport_app/Contents/Resources/"
ditto LICENSES "$taskport_app/Contents/Resources/LICENSES"
bash scripts/verify-licenses.sh "$taskport_app"
# Strip debug/local symbols before signing; never rewrite binary strings.
strip -S -x "$taskport_app/Contents/MacOS/Taskport" "$taskport_app/Contents/MacOS/taskport-cli"
codesign --force --sign - "$taskport_app"
codesign --verify --deep --strict "$taskport_app"
if [[ "$taskport_check" == true ]]; then
  echo 'Release app verified; check-only mode leaves the installed app and running tasks untouched.'
else
  bash scripts/install.sh "$taskport_app"
fi
