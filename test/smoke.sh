#!/usr/bin/env bash
# Dry-run smoke test: runs every setup with WS_DRY=1 and checks the CLI.
# Works on Linux CI and on your Mac without opening anything.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
ws="$root/bin/ws"
export WS_DRY=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$ws" list | grep -q '^learn'
for f in "$root"/setups/*.sh; do
  n=$(basename "$f" .sh); [ "$n" = _template ] && continue
  out=$("$ws" up "$n" 2>&1); printf '%s\n' "$out" | grep -q '\[dry\]' || { echo "FAIL up $n"; exit 1; }
  "$ws" down "$n" >/dev/null 2>&1
done

# learn specifics: the first queue item reaches VLC, the session reaches Chrome
out=$("$ws" learn 2>&1)
grep -q 'VMj-3S1tku0' <<<"$out"         || { echo "FAIL vlc queue"; exit 1; }
grep -q -- '--new-window' <<<"$out"     || { echo "FAIL chrome"; exit 1; }
grep -q 'working-directory=' <<<"$out"  || { echo "FAIL ghostty"; exit 1; }

# alfred output is valid JSON
"$ws" alfred | python3 -m json.tool >/dev/null

# queue advance on a copy of the repo
cp -R "$root" "$tmp/r"
BORING_HOME="$tmp/r" "$tmp/r/bin/ws" next karpathy 2>/dev/null
grep -q 'PaCmpygFfXo' <(BORING_HOME="$tmp/r" bash -c '. "$BORING_HOME/lib/blocks.sh"; queue_next karpathy')
grep -q 'VMj-3S1tku0' "$tmp/r/queues/karpathy.done.txt"

echo "smoke: ok"
