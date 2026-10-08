#!/bin/bash
# Build and audit a local candidate. This does not publish or establish source/relinking compliance.
set -euo pipefail
[[ "$#" == 0 ]] || { echo 'Usage: bash scripts/prepare-release.sh' >&2; exit 2; }
taskport_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$taskport_root"
command -v bun >/dev/null || { echo 'Bun is required for the release privacy audit.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required to inspect ZIP metadata.' >&2; exit 1; }
taskport_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$taskport_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
taskport_output="$taskport_root/build/release-candidate"
taskport_name="Taskport-$taskport_version-macos-arm64.zip"
if [[ -e "$taskport_output/$taskport_name" || -L "$taskport_output/$taskport_name" || -L "$taskport_output" ]]; then
  echo 'The release candidate already exists or its path is linked; inspect it before replacing it.' >&2
  exit 1
fi
mkdir -p "$taskport_root/build"
taskport_stage="$(mktemp -d "$taskport_root/build/.release.XXXXXX")"
trap 'rm -rf "$taskport_stage"' EXIT
bash scripts/build.sh --package "$taskport_stage/Taskport.app"
taskport_arch="$(lipo -archs "$taskport_stage/Taskport.app/Contents/MacOS/Taskport")"
[[ "$taskport_arch" == arm64 ]] || { echo 'This release recipe currently requires an arm64 build.' >&2; exit 1; }
bun scripts/check-app-privacy.mjs "$taskport_stage/Taskport.app" --local-identities
# Keep local build/source modification times out of the ZIP's mandatory DOS timestamps.
/usr/bin/find "$taskport_stage/Taskport.app" -exec /usr/bin/touch -t 200001010000 {} +
# -X omits Unix UID/GID and extra attributes; a ZIP contains neither ACLs nor resource forks.
# macOS can retain its protected provenance xattr locally; inspect the archive itself for metadata.
(cd "$taskport_stage" && COPYFILE_DISABLE=1 /usr/bin/zip -X -q -r "$taskport_name" Taskport.app)
python3 scripts/check-release-archive.py "$taskport_stage/$taskport_name"
mkdir "$taskport_stage/extracted"
/usr/bin/unzip -q "$taskport_stage/$taskport_name" -d "$taskport_stage/extracted"
bun scripts/check-app-privacy.mjs "$taskport_stage/extracted/Taskport.app" --local-identities
bash scripts/verify-licenses.sh "$taskport_stage/extracted/Taskport.app"
codesign --verify --deep --strict "$taskport_stage/extracted/Taskport.app"
diff -qr "$taskport_stage/Taskport.app" "$taskport_stage/extracted/Taskport.app" >/dev/null
mkdir -p "$taskport_output"
mv "$taskport_stage/$taskport_name" "$taskport_output/$taskport_name"
(cd "$taskport_output" && shasum -a 256 "$taskport_name" > "$taskport_name.sha256")
echo "Local candidate prepared: build/release-candidate/$taskport_name"
echo 'Publish only with the matching verified source/relink archive and after clean-machine testing.'
