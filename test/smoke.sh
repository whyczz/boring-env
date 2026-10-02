#!/usr/bin/env bash
# Dry-run smoke test: runs every setup with B_DRY=1 and checks the CLI.
# Works on Linux CI and on your Mac without opening anything.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
b="$root/bin/b"
export B_DRY=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$b" list | grep -q '^learn'
for f in "$root"/setups/*.sh; do
  n=$(basename "$f" .sh); [ "$n" = _template ] && continue
  out=$("$b" up "$n" 2>&1); printf '%s\n' "$out" | grep -q '\[dry\]' || { echo "FAIL up $n"; exit 1; }
  "$b" down "$n" >/dev/null 2>&1
done

# learn specifics: the first queue item reaches VLC, the session reaches Chrome
out=$("$b" learn 2>&1)
grep -q 'VMj-3S1tku0' <<<"$out"         || { echo "FAIL vlc queue"; exit 1; }
grep -q -- '--new-window' <<<"$out"     || { echo "FAIL chrome"; exit 1; }
grep -q 'working-directory=' <<<"$out"  || { echo "FAIL ghostty"; exit 1; }

# alfred output is valid JSON
"$b" alfred | python3 -m json.tool >/dev/null

# queue advance on a copy of the repo
cp -R "$root" "$tmp/r"
BORING_HOME="$tmp/r" "$tmp/r/bin/b" next karpathy 2>/dev/null
grep -q 'PaCmpygFfXo' <(BORING_HOME="$tmp/r" bash -c '. "$BORING_HOME/lib/blocks.sh"; queue_next karpathy')
grep -q 'VMj-3S1tku0' "$tmp/r/queues/karpathy.done.txt"

# alfred workflow builds and points at this checkout's bin/b
if command -v zip >/dev/null; then
  "$root/alfred/build.sh" --no-open >/dev/null
  unzip -p "$root/boring-env.alfredworkflow" info.plist | grep -q "$root/bin/b"
  rm -f "$root/boring-env.alfredworkflow"
fi

echo "smoke: ok"
