# shellcheck shell=bash
# boring-env blocks: the Lego. Each block is one small function a recipe calls.
# Stock macOS only: bash 3.2, `open`, `osascript`. No yq, no brew deps
# (aerospace and VLC are optional and skipped if missing).
#
# B_DRY=1 prints every side effect instead of doing it. Handy for testing
# a recipe without spawning 9 windows.

: "${BORING_HOME:?BORING_HOME not set (source via bin/b)}"
: "${CHROME_APP:=Google Chrome}"
: "${CHROME_PROFILE:=}"                     # e.g. "Profile 1"; empty = default
: "${GHOSTTY_APP:=Ghostty}"
: "${VLC_BIN:=/Applications/VLC.app/Contents/MacOS/VLC}"
: "${FOCUS_ON_SHORTCUT:=Focus On}"          # names of Apple Shortcuts you create
: "${FOCUS_OFF_SHORTCUT:=Focus Off}"
: "${SETTLE:=0.4}"                          # seconds to let a window appear
: "${STUDY_WS:=S}"                          # AeroSpace workspace for study recipes (alt-s)

# --- plumbing -------------------------------------------------------------

log() { printf '\033[2m[b]\033[0m %s\n' "$*" >&2; }
die() { printf '[b] error: %s\n' "$*" >&2; exit 1; }

# run CMD...: execute, or print in dry mode
run() {
  if [ -n "${B_DRY:-}" ]; then printf '[dry] %s\n' "$*"; else "$@"; fi
}

# osa SCRIPT [ARGS...]: AppleScript via stdin; args land in `on run argv`
osa() {
  local script=$1; shift
  if [ -n "${B_DRY:-}" ]; then
    printf '[dry] osascript (%s) <<%s\n' "$*" "$(printf '%s' "$script" | head -1)"
    return 0
  fi
  printf '%s\n' "$script" | osascript - "$@"
}

settle() { [ -n "${B_DRY:-}" ] || sleep "$SETTLE"; }

has() { command -v "$1" >/dev/null 2>&1; }

# expand a leading ~ (recipe files often say ~/code/x inside quotes)
# shellcheck disable=SC2088  # matching a literal ~ on purpose
expand() { case $1 in "~"|"~/"*) printf '%s%s' "$HOME" "${1#\~}" ;; *) printf '%s' "$1" ;; esac; }

# lines FILE: non-blank, non-comment lines
lines() { [ -f "$1" ] || die "no such file: $1"; grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1"; }

app_running() {
  [ -n "${B_DRY:-}" ] && return 1
  [ "$(osascript -e "application \"$1\" is running" 2>/dev/null)" = "true" ]
}

# --- apps -----------------------------------------------------------------

# app_open NAME: launch or focus any .app
app_open() { log "open $1"; run open -a "$1"; }

# app_quit NAME...: politely quit apps that are running (no-op otherwise)
app_quit() {
  local a
  for a in "$@"; do
    if [ -n "${B_DRY:-}" ] || app_running "$a"; then
      log "quit $a"
      osa 'on run argv
  tell application (item 1 of argv) to quit
end run' "$a"
    fi
  done
}

# --- terminal -------------------------------------------------------------

# term_at DIR [CMD...]: new Ghostty window in DIR, optionally running CMD
# (drops you into your shell after CMD exits).
term_at() {
  local dir; dir=$(expand "$1"); shift
  [ -n "${B_DRY:-}" ] || [ -d "$dir" ] || { log "creating $dir"; mkdir -p "$dir"; }
  log "ghostty @ $dir"
  if [ $# -gt 0 ]; then
    run open -na "$GHOSTTY_APP" --args --working-directory="$dir" \
      -e "${SHELL:-/bin/zsh}" -lc "$*; exec ${SHELL:-/bin/zsh} -l"
  else
    run open -na "$GHOSTTY_APP" --args --working-directory="$dir"
  fi
  settle
}

# --- browser --------------------------------------------------------------

# chrome_window URL...: one NEW Chrome window holding all URLs as tabs
chrome_window() {
  [ $# -gt 0 ] || return 0
  log "chrome: $# tab(s)"
  local profile=()
  [ -n "$CHROME_PROFILE" ] && profile=(--profile-directory="$CHROME_PROFILE")
  run open -na "$CHROME_APP" --args ${profile[@]+"${profile[@]}"} --new-window "$@"
  settle
}

# chrome_session NAME: open sessions/NAME.txt (one URL per line) as a window.
# This is the git-tracked replacement for Session Buddy: export a session
# from Session Buddy as plain URLs and paste it into the file.
chrome_session() {
  local f="$BORING_HOME/sessions/$1.txt" urls=() u
  while IFS= read -r u; do urls+=("$u"); done < <(lines "$f")
  chrome_window ${urls[@]+"${urls[@]}"}
}

# chrome_close_matching PATTERN...: close every Chrome tab whose URL contains
# any PATTERN (e.g. x.com reddit.com). Distraction killer.
chrome_close_matching() {
  [ $# -gt 0 ] || return 0
  if [ -z "${B_DRY:-}" ] && ! app_running "$CHROME_APP"; then return 0; fi
  log "chrome: closing tabs matching $*"
  osa 'on run argv
  tell application "Google Chrome"
    repeat with w in windows
      repeat with i from (count of tabs of w) to 1 by -1
        set u to URL of tab i of w
        repeat with p in argv
          if u contains (p as text) then
            close tab i of w
            exit repeat
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run' "$@"
}

# --- video ----------------------------------------------------------------

# vlc_play SRC [START_SECONDS]: play a file or URL in VLC.
# VLC also remembers where you stopped in local files ("Continue playback?").
vlc_play() {
  local src start=${2:-0}
  src=$(expand "$1")
  [ -n "$src" ] || { log "vlc: nothing to play (queue empty?)"; return 0; }
  if [ -z "${B_DRY:-}" ] && [ ! -x "$VLC_BIN" ]; then
    log "VLC not found at $VLC_BIN; opening in default app instead"
    run open "$src"; return 0
  fi
  log "vlc: $src"
  # AppleScript, not the binary: a running VLC plays it instead of a second
  # instance spawning next to it.
  osa 'on run argv
  set src to item 1 of argv
  set t to (item 2 of argv) as integer
  tell application "VLC"
    if src contains "://" then
      OpenURL src
    else
      open (POSIX file src)
    end if
    activate
    if t > 0 then
      repeat 20 times
        if playing then exit repeat
        delay 0.25
      end repeat
      set current time to t
    end if
  end tell
end run' "$src" "$start"
  settle
}

# video_find KEY [DIR]: KEY is a path/URL (returned as is) or any piece of a
# filename in DIR (default $VIDEO_DIR), e.g. a YouTube id like q8SA3rM6ckI.
# Ids survive renames as long as the [id] stays in the name.
video_find() {
  local key dir=${2:-${VIDEO_DIR:-}} hit=""
  key=$(expand "$1")
  case $key in ""|*://*|/*) printf '%s' "$key"; return 0 ;; esac
  [ -e "$key" ] && { printf '%s' "$key"; return 0; }
  dir=$(expand "$dir")
  [ -d "$dir" ] && hit=$(find "$dir" -maxdepth 2 -type f -name "*$key*" | sort | head -1)
  if [ -n "$hit" ]; then printf '%s' "$hit"
  else log "video_find: nothing matching '$key' in ${dir:-<no VIDEO_DIR>}"; printf '%s' "$key"
  fi
}

# video_title FILE: "Building makemore Part 4： Becoming a Backprop Ninja [q8SA3rM6ckI].webm"
#   -> "Building makemore Part 4: Becoming a Backprop Ninja"
video_title() {
  basename "$1" | sed -e 's/\.[A-Za-z0-9]*$//' -e 's/ \[[A-Za-z0-9_-]\{11\}\]$//' -e 's/：/:/g'
}

# --- queues: "what do I watch next" ----------------------------------------
# queues/NAME.txt: one item per line, top = next. `b next NAME` marks the
# top item done (moves it to queues/NAME.done.txt with a date).

queue_next() {
  local f="$BORING_HOME/queues/$1.txt"
  [ -f "$f" ] || { log "no queue $f"; return 0; }
  lines "$f" | head -1 | sed 's/[[:space:]]\{1,\}#.*$//'
}

queue_done() {
  local f="$BORING_HOME/queues/$1.txt" top tmp
  top=$(queue_next "$1")
  [ -n "$top" ] || die "queue $1 is empty"
  tmp=$(mktemp)
  # drop the first line that starts with the top item, keep everything else
  awk -v t="$top" 'done || index($0, t) != 1 { print; next } { done = 1 }' "$f" > "$tmp"
  mv "$tmp" "$f"
  printf '%s\t%s\n' "$(date +%F)" "$top" >> "$BORING_HOME/queues/$1.done.txt"
  log "done: $top"
  log "next: $(queue_next "$1")"
}

# --- notes ----------------------------------------------------------------

# notes_open TITLE [--stamp] [--folder NAME]: show the Apple Note TITLE,
# creating it if missing. --folder looks in (or creates in) that folder,
# searched by name at any depth, so nested folders like
# Scholar > Machine Learning > Karpathy just need the leaf name.
# --stamp appends today's date as a heading so you start writing right away.
notes_open() {
  local title=$1 stamp="" folder=""
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      --stamp)  stamp=$(date '+%a %F %H:%M') ;;
      --folder) folder=${2:-}; shift ;;
      *) log "notes_open: ignoring '$1'" ;;
    esac
    shift
  done
  log "notes: ${folder:+$folder / }$title${stamp:+ (+$stamp)}"
  osa 'on findFolder(fs, target)
  tell application "Notes"
    repeat with f in fs
      if name of f is target then return f
      set r to my findFolder(folders of f, target)
      if r is not missing value then return r
    end repeat
  end tell
  return missing value
end findFolder

on run argv
  set t to item 1 of argv
  set s to item 2 of argv
  set fname to item 3 of argv
  tell application "Notes"
    if fname is "" then
      -- skip notes sitting in Recently Deleted (their container errors out)
      set hits to {}
      repeat with n in (notes whose name is t)
        try
          if name of container of n is not "Recently Deleted" then set end of hits to contents of n
        end try
      end repeat
      set dest to missing value
    else
      set dest to missing value
      repeat with a in accounts
        set dest to my findFolder(folders of a, fname)
        if dest is not missing value then exit repeat
      end repeat
      if dest is missing value then set dest to make new folder with properties {name:fname}
      set hits to (notes of dest whose name is t)
    end if
    if (count of hits) is 0 then
      if dest is missing value then
        set n to make new note with properties {body:"<h1>" & t & "</h1>"}
      else
        set n to make new note at dest with properties {body:"<h1>" & t & "</h1>"}
      end if
    else
      set n to item 1 of hits
    end if
    if s is not "" then set body of n to (body of n) & "<h2>" & s & "</h2><div><br></div>"
    try
      show n
    end try
    activate
  end tell
end run' "$title" "$stamp" "$folder"
  settle
}

# --- window manager: AeroSpace ---------------------------------------------

# aero_workspace NAME: jump to an AeroSpace workspace so new windows land there
aero_workspace() {
  if [ -z "${B_DRY:-}" ] && ! has aerospace; then log "aerospace not installed, skipping"; return 0; fi
  log "aerospace workspace $1"
  run aerospace workspace "$1"
}

# aero_pull NAME: move the focused window to workspace NAME and follow it.
# Activating an app whose window lives elsewhere (VLC, Notes) makes AeroSpace
# jump to that window's workspace; call this right after to drag it back.
aero_pull() {
  if [ -z "${B_DRY:-}" ] && ! has aerospace; then return 0; fi
  log "aerospace pull focused window -> $1"
  run aerospace move-node-to-workspace --focus-follows-window "$1"
}

# aero_layout LAYOUT...: e.g. `aero_layout tiles horizontal` on focused window
aero_layout() {
  if [ -z "${B_DRY:-}" ] && ! has aerospace; then return 0; fi
  run aerospace layout "$@"
}

# --- focus / distractions ---------------------------------------------------

# focus_on / focus_off: run the Apple Shortcuts named in FOCUS_*_SHORTCUT.
# Make them once in Shortcuts.app: action "Set Focus" -> Do Not Disturb On/Off.
focus_on()  { _shortcut "$FOCUS_ON_SHORTCUT"; }
focus_off() { _shortcut "$FOCUS_OFF_SHORTCUT"; }
_shortcut() {
  if [ -z "${B_DRY:-}" ] && ! shortcuts list 2>/dev/null | grep -qx "$1"; then
    log "no Shortcut named \"$1\" (see README), skipping"; return 0
  fi
  log "shortcut: $1"
  run shortcuts run "$1"
}

# kill_distractions: quit apps + close tabs listed in distractions.txt
#   app:Slack         quit an app
#   tab:x.com         close Chrome tabs whose URL contains x.com
kill_distractions() {
  local f="$BORING_HOME/distractions.txt" line apps=() tabs=()
  [ -f "$f" ] || { log "no distractions.txt, nothing to kill"; return 0; }
  while IFS= read -r line; do
    case $line in
      app:*) apps+=("${line#app:}") ;;
      tab:*) tabs+=("${line#tab:}") ;;
      *) log "distractions.txt: ignoring '$line'" ;;
    esac
  done < <(lines "$f")
  app_quit ${apps[@]+"${apps[@]}"}
  chrome_close_matching ${tabs[@]+"${tabs[@]}"}
}
