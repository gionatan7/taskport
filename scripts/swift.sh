#!/bin/bash
set -euo pipefail

# Keep all SwiftPM and Clang caches inside the repository.
taskport_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$taskport_root"
export CLANG_MODULE_CACHE_PATH="$taskport_root/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$taskport_root/.build/swift-module-cache"
exec swift "$@" --cache-path "$taskport_root/.build/cache" \
    --config-path "$taskport_root/.build/config" \
    --security-path "$taskport_root/.build/security" \
    --manifest-cache local --disable-dependency-cache
