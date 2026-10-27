#!/bin/bash
set -euo pipefail
taskport_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$taskport_root"
taskport_check=false
taskport_package=
taskport_restore=false
taskport_restore_flags=()
if [[ "$#" == 1 && "$1" == --check ]]; then
  taskport_check=true
elif [[ "$#" == 2 && "$1" == --package && -n "$2" ]]; then
  taskport_package="$2"
  [[ "$taskport_package" == /* ]] || taskport_package="$taskport_root/$taskport_package"
  if [[ -e "$taskport_package" || -L "$taskport_package" ]]; then
    echo 'The package destination already exists; choose a fresh path.' >&2
    exit 1
  fi
elif [[ "$#" -ge 1 && "$1" == --restore ]]; then
  taskport_restore=true
  shift
  for taskport_flag in "$@"; do
    case "$taskport_flag" in
      --include-one-offs|--include-tunnels) taskport_restore_flags+=("$taskport_flag") ;;
      *) echo 'Unsupported restore option; use --include-one-offs or --include-tunnels.' >&2; exit 2 ;;
    esac
  done
elif [[ "$#" != 0 ]]; then
  echo 'Usage: bash scripts/build.sh [--check | --package OUTPUT_APP | --restore [--include-one-offs] [--include-tunnels]]' >&2
  exit 2
fi
bash scripts/check-toolchain.sh
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
# SwiftPM adds an Xcode-only RPATH that can trip Gatekeeper on recipients' Macs.
# Remove it only from staged copies, before any app signature is produced.
bash scripts/prepare-runtime-paths.sh "$taskport_app/Contents/MacOS/Taskport" "$taskport_app/Contents/MacOS/taskport-cli"
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
taskport_sparkle="$taskport_bin/Sparkle.framework"
test -d "$taskport_sparkle"
mkdir -p "$taskport_app/Contents/Frameworks"
ditto "$taskport_sparkle" "$taskport_app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$taskport_app/Contents/MacOS/Taskport"
cp LICENSE THIRD_PARTY_NOTICES.md "$taskport_app/Contents/Resources/"
ditto LICENSES "$taskport_app/Contents/Resources/LICENSES"
mkdir -p "$taskport_app/Contents/Resources/AgentSkills/taskport"
cp skills/taskport/SKILL.md "$taskport_app/Contents/Resources/AgentSkills/taskport/SKILL.md"
bash scripts/verify-licenses.sh "$taskport_app"
# Finder tags, quarantine/download locations, and other local metadata are not release inputs.
chmod -R u+w "$taskport_app"
xattr -cr "$taskport_app"
# Strip debug/local symbols before signing; never rewrite binary strings.
strip -S -x "$taskport_app/Contents/MacOS/Taskport" "$taskport_app/Contents/MacOS/taskport-cli"
# Re-sign nested updater helpers inside-out, with no paid certificate or local identity.
taskport_framework="$taskport_app/Contents/Frameworks/Sparkle.framework"
for taskport_helper in "$taskport_framework/Versions/B/XPCServices/Downloader.xpc" \
                       "$taskport_framework/Versions/B/XPCServices/Installer.xpc" \
                       "$taskport_framework/Versions/B/Updater.app" \
                       "$taskport_framework/Versions/B/Autoupdate"; do
  codesign --force --sign - "$taskport_helper"
done
codesign --force --sign - "$taskport_framework"
codesign --force --sign - "$taskport_app"
codesign --verify --deep --strict "$taskport_app"
bash scripts/prepare-runtime-paths.sh --check "$taskport_app/Contents/MacOS/Taskport" "$taskport_app/Contents/MacOS/taskport-cli"
if [[ "$taskport_check" == true ]]; then
  echo 'Release app verified; check-only mode leaves the installed app and running tasks untouched.'
elif [[ -n "$taskport_package" ]]; then
  mkdir -p "$(dirname "$taskport_package")"
  mv "$taskport_app" "$taskport_package"
  echo 'Packaged app verified; the installed app and running tasks were not changed.'
else
  if [[ "$taskport_restore" == true ]]; then
    # Finish compilation/signing/preflight first, then keep the interruption short.
    bash scripts/install.sh --check "$taskport_app"
    "$taskport_app/Contents/MacOS/taskport-cli" quit --save-session ${taskport_restore_flags[@]+"${taskport_restore_flags[@]}"}
  fi
  bash scripts/install.sh "$taskport_app"
  if [[ "$taskport_restore" == true ]]; then
    /Applications/Taskport.app/Contents/MacOS/taskport-cli launch --restore
  fi
fi
