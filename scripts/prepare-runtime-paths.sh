#!/bin/bash
# Prepare copied executables before signing; --check never changes an artifact.
set -euo pipefail
taskport_check=false
if [[ "${1:-}" == --check ]]; then taskport_check=true; shift; fi
if [[ "$#" == 0 ]]; then
  echo 'Usage: bash scripts/prepare-runtime-paths.sh [--check] EXECUTABLE...' >&2
  exit 2
fi
for taskport_binary in "$@"; do
  [[ -f "$taskport_binary" && ! -L "$taskport_binary" ]] || { echo 'Expected a real Mach-O executable.' >&2; exit 1; }
  taskport_kind="$(file -b "$taskport_binary")"
  [[ "$taskport_kind" == Mach-O* ]] || { echo 'Expected a Mach-O executable.' >&2; exit 1; }
  taskport_commands="$(xcrun otool -l "$taskport_binary" | awk '
    $1 == "cmd" { command = $2 }
    command == "LC_RPATH" && $1 == "path" {
      sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print "rpath\t" $0
    }
    command ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LOAD_UPWARD|LAZY_LOAD)_DYLIB$/ && $1 == "name" {
      sub(/^[[:space:]]*name /, ""); sub(/ \(offset [0-9]+\)$/, ""); print "library\t" $0
    }')"
  while IFS=$'\t' read -r taskport_command taskport_path; do
    [[ -n "$taskport_command" ]] || continue
    if [[ "$taskport_command" == rpath && "$taskport_path" == */Toolchains/*.xctoolchain/* ]]; then
      if [[ "$taskport_check" == true ]]; then
        echo 'Executable contains a developer-toolchain runtime search path.' >&2
        exit 1
      fi
      xcrun install_name_tool -delete_rpath "$taskport_path" "$taskport_binary"
      continue
    fi
    case "$taskport_path" in
      /usr/lib/*|/System/Library/*|@loader_path|@loader_path/*|@executable_path|@executable_path/*) ;;
      @rpath/*) [[ "$taskport_command" == library ]] || { echo 'Recursive runtime search path is not portable.' >&2; exit 1; } ;;
      *) echo 'Executable contains a nonportable runtime search path or library reference.' >&2; exit 1 ;;
    esac
  done <<< "$taskport_commands"
done
