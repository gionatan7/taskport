#!/bin/bash
set -euo pipefail
taskport_root="$(cd "$(dirname "$0")/.." && pwd)"
taskport_check=false
if [[ "$#" == 2 && "$1" == --check ]]; then taskport_check=true; shift; fi
if [[ "$#" != 1 || -z "$1" ]]; then echo 'Usage: bash scripts/install.sh [--check] APP_BUNDLE' >&2; exit 2; fi
taskport_source="$1"
taskport_destination="/Applications/Taskport.app"
if [[ "$taskport_source" == "$taskport_destination" ]]; then
  echo 'The install source must not be the installed app.' >&2
  exit 1
fi

if [[ "$taskport_check" == false ]]; then
if pgrep -x Taskport >/dev/null; then
  echo 'Quit all Taskport instances before installing. Running tasks will not be stopped automatically.' >&2
  exit 1
else
  taskport_process_status=$?
  if [[ "$taskport_process_status" != 1 ]]; then
    echo 'Cannot verify whether Taskport is running. Check process-access permissions.' >&2
    exit 1
  fi
fi
fi

for taskport_bundle in "$taskport_source" "$taskport_destination"; do
  if [[ -L "$taskport_bundle" ]]; then
    echo "Refusing to replace a symlink: $taskport_bundle" >&2
    exit 1
  fi
  if [[ -e "$taskport_bundle" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$taskport_bundle/Contents/Info.plist")" == app.taskport.desktop ]] || exit 1
  fi
done
test -x "$taskport_source/Contents/MacOS/Taskport"
test -x "$taskport_source/Contents/MacOS/taskport-cli"
codesign --verify --deep --strict "$taskport_source"

# Keep the previous install recoverable until the new bundle passes verification.
taskport_backup="$taskport_root/build/Taskport.previous"
if [[ -e "$taskport_backup" || -L "$taskport_backup" ]]; then
  echo "A previous installation backup exists at $taskport_backup; inspect it before retrying." >&2
  exit 1
fi
if [[ ! -w /Applications || ( -e "$taskport_destination" && ! -w "$taskport_destination" ) ]]; then
  echo 'Installation needs write access to /Applications/Taskport.app. Request execution approval before stopping tasks.' >&2
  exit 1
fi
if [[ "$taskport_check" == true ]]; then
  echo 'Installation preflight passed; no app or tasks were changed.'
  exit 0
fi
if [[ -e "$taskport_destination" ]]; then mv "$taskport_destination" "$taskport_backup"; fi
if mv "$taskport_source" "$taskport_destination"; then
  if codesign --verify --deep --strict "$taskport_destination"; then
    if [[ -d "$taskport_backup" ]]; then rm -rf "$taskport_backup"; fi
    echo "$taskport_destination"
    exit 0
  fi
  mv "$taskport_destination" "$taskport_source"
fi
if [[ -d "$taskport_backup" ]]; then mv "$taskport_backup" "$taskport_destination"; fi
echo 'Installation failed; the previous app was restored.' >&2
exit 1
