# desc: Karpathy lectures + code + Learning Log, distractions off
# shellcheck shell=bash
# A recipe is plain bash. Define up() and (optionally) down() using blocks
# from lib/blocks.sh. Read top to bottom: that's the order things happen.

LEARN_DIR=~/code/learn

up() {
  kill_distractions                    # b kill, but automatic
  aero_workspace "$LEARN_WS"                   # new windows land on AeroSpace workspace S (alt-s)
  term_at "$LEARN_DIR"                 # Ghostty, cd'd in
  chrome_session learn                 # tabs from sessions/learn.txt
  vlc_play "$(queue_next karpathy)"    # top of queues/karpathy.txt
  aero_pull "$LEARN_WS"                # drag VLC over if its window lived elsewhere
  notes_open "Learning Log" --stamp    # Apple Note with today's heading
  aero_pull "$LEARN_WS"
  focus_on                             # Shortcut "Focus On" -> Do Not Disturb
}

down() {
  app_quit VLC
  focus_off
  log "watched it all? run: b next karpathy"
}
