#!/bin/bash
# Run before SwiftPM resolution so unsupported toolchains fail without downloads.
set -euo pipefail
taskport_toolchain_error() {
  echo "Taskport build requires full Xcode 27.x with Apple Swift 6.4.x: $1" >&2
  echo 'Install/open Xcode 27, then retry with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build.sh' >&2
  echo 'This build does not change the system Xcode selection.' >&2
  exit 1
}
[[ "$#" == 0 ]] || { echo 'Usage: bash scripts/check-toolchain.sh' >&2; exit 2; }
command -v xcrun >/dev/null 2>&1 || taskport_toolchain_error 'Apple developer tools are unavailable.'
taskport_xcode="$(xcrun xcodebuild -version 2>/dev/null)" || taskport_toolchain_error 'Command Line Tools alone are not supported.'
[[ "$taskport_xcode" =~ ^Xcode[[:space:]]+27([.[:space:]]|$) ]] || taskport_toolchain_error 'The selected Xcode version is unsupported.'
taskport_swift="$(xcrun swift --version 2>/dev/null)" || taskport_toolchain_error 'The selected Swift compiler is unavailable.'
[[ "$taskport_swift" =~ Apple[[:space:]]Swift[[:space:]]version[[:space:]]6[.]4([.[:space:]]|$) ]] || taskport_toolchain_error 'The selected Swift compiler is unsupported.'
xcrun --find actool >/dev/null 2>&1 || taskport_toolchain_error 'The Xcode icon compiler is unavailable.'
echo 'Toolchain verified: Xcode 27.x / Apple Swift 6.4.x.'
