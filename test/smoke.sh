#!/usr/bin/env bash
# Dry-run smoke test: runs every recipe with B_DRY=1 and checks the CLI.
# Works on Linux CI and on your Mac without opening anything.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
b="$root/bin/b"
export B_DRY=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$b" list | grep -q '^l makemore'
for f in $(cd "$root/recipes" && find . -name '*.sh' ! -name '_template.sh'); do
  words=$(printf '%s' "${f#./}" | sed 's/\.sh$//' | tr / ' ')
  # shellcheck disable=SC2086  # split "l makemore" into words on purpose
  out=$("$b" up $words 2>&1); grep -q '\[dry\]' <<<"$out" || { echo "FAIL up $words"; exit 1; }
  # shellcheck disable=SC2086
  "$b" down $words >/dev/null 2>&1
done

# l karpathy: first queue item reaches VLC, the session reaches Chrome
out=$("$b" l karpathy 2>&1)
grep -q 'VMj-3S1tku0' <<<"$out"         || { echo "FAIL vlc queue"; exit 1; }
grep -q -- '--new-window' <<<"$out"     || { echo "FAIL chrome"; exit 1; }
grep -q 'working-directory=' <<<"$out"  || { echo "FAIL ghostty"; exit 1; }

# l makemore: id in the queue resolves to the local file, note gets its title
mkdir -p "$tmp/videos"
touch "$tmp/videos/Building makemore Part 4： Becoming a Backprop Ninja [q8SA3rM6ckI].webm"
out=$(cd "$root" && BORING_HOME="$root" bash -c '
  . lib/blocks.sh; . recipes/l/makemore.sh; VIDEO_DIR='"'$tmp/videos'"'; up' 2>&1)
grep -q 'Backprop Ninja \[q8SA3rM6ckI\].webm' <<<"$out"            || { echo "FAIL makemore video"; exit 1; }
grep -q 'notes: Karpathy, Zero To Hero / Building makemore Part 4: Becoming a Backprop Ninja' <<<"$out" \
  || { echo "FAIL makemore note"; exit 1; }
grep -q 'jupyter lab' <<<"$out"                                    || { echo "FAIL makemore jupyter"; exit 1; }

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
