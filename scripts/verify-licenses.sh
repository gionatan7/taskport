#!/bin/bash
# Verify notice packaging, not legal completeness or source/relinking compliance.
set -euo pipefail
if [[ "$#" != 1 || -z "$1" ]]; then
  echo 'Usage: bash scripts/verify-licenses.sh APP_BUNDLE' >&2
  exit 2
fi
taskport_root="$(cd "$(dirname "$0")/.." && pwd)"
taskport_resources="$1/Contents/Resources"
taskport_licenses="$taskport_root/LICENSES"
taskport_fail() { echo "License verification failed: $1" >&2; exit 1; }
for taskport_dir in "$1" "$1/Contents" "$taskport_resources" "$taskport_licenses" "$taskport_resources/LICENSES"; do
  [[ -d "$taskport_dir" && ! -L "$taskport_dir" ]] || taskport_fail 'missing or linked resource directory'
done
for taskport_dir in "$taskport_licenses" "$taskport_resources/LICENSES"; do
  [[ -z "$(find "$taskport_dir" ! -type f ! -type d -print)" ]] || taskport_fail 'unexpected non-file license entry'
done
[[ -s "$taskport_licenses/SHA256SUMS" ]] || taskport_fail 'missing license manifest'
taskport_entries=0
while read -r taskport_hash taskport_file; do
  [[ "$taskport_hash" =~ ^[a-f0-9]{64}$ && "$taskport_file" =~ ^[A-Za-z0-9_-]+(/[A-Za-z0-9_.-]+)+$ && "$taskport_file" != */../* && "$taskport_file" != */./* && "$taskport_file" != */.. && "$taskport_file" != */. ]] || taskport_fail 'invalid manifest entry'
  [[ -s "$taskport_licenses/$taskport_file" ]] || taskport_fail "missing or empty license: $taskport_file"
  [[ -s "$taskport_resources/LICENSES/$taskport_file" ]] || taskport_fail "missing or empty bundled license: $taskport_file"
  cmp -s "$taskport_licenses/$taskport_file" "$taskport_resources/LICENSES/$taskport_file" || taskport_fail "bundled license differs: $taskport_file"
  taskport_entries=$((taskport_entries + 1))
done < "$taskport_licenses/SHA256SUMS"
[[ "$taskport_entries" -gt 0 && "$(awk '{print $2}' "$taskport_licenses/SHA256SUMS" | sort -u | wc -l)" -eq "$taskport_entries" ]] || taskport_fail 'empty or duplicate manifest entries'
for taskport_dir in "$taskport_licenses" "$taskport_resources/LICENSES"; do
  [[ "$(find "$taskport_dir" -type f | wc -l)" -eq "$((taskport_entries + 1))" ]] || taskport_fail 'unlisted or missing license files'
done
(cd "$taskport_licenses" && shasum -a 256 -c SHA256SUMS >/dev/null) || taskport_fail 'canonical license checksum mismatch'
for taskport_file in LICENSE THIRD_PARTY_NOTICES.md LICENSES/SHA256SUMS; do
  [[ -f "$taskport_root/$taskport_file" && -s "$taskport_root/$taskport_file" && ! -L "$taskport_root/$taskport_file" && -f "$taskport_resources/$taskport_file" && ! -L "$taskport_resources/$taskport_file" ]] || taskport_fail "missing or linked notice: $taskport_file"
  cmp -s "$taskport_root/$taskport_file" "$taskport_resources/$taskport_file" || taskport_fail "bundled notice differs: $taskport_file"
done
taskport_preexec="$taskport_resources/GhosttyKit_GhosttyTerminal.bundle/Contents/Resources/Ghostty/shell-integration/bash/LICENSE-bash-preexec.md"
[[ -f "$taskport_preexec" && ! -L "$taskport_preexec" ]] || taskport_fail 'missing bash-preexec resource notice'
cmp -s "$taskport_licenses/bash-preexec/LICENSE.md" "$taskport_preexec" || taskport_fail 'bash-preexec resource notice differs'
echo 'License files verified (source/relinking compliance requires a separate review).'
