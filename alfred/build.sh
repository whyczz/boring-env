#!/usr/bin/env bash
# Build boring-env.alfredworkflow from info.plist.template, pointing it at
# this checkout's bin/b. Then `open` it and Alfred offers to import.
#   alfred/build.sh            build + open (installs)
#   alfred/build.sh --no-open  just build
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
out="$root/boring-env.alfredworkflow"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# escape for sed replacement (paths may hold & or |)
bin=$(printf '%s' "$root/bin/b" | sed -e 's/[&|\\]/\\&/g')
sed "s|__BIN__|$bin|g" "$here/info.plist.template" > "$tmp/info.plist"
if command -v plutil >/dev/null 2>&1; then plutil -lint -s "$tmp/info.plist"; fi

rm -f "$out"
(cd "$tmp" && zip -q "$out" info.plist)
echo "built $out"
[ "${1:-}" = "--no-open" ] || open "$out"
