# desc: describe __NAME__ in one line (shows up in Alfred)
# shellcheck shell=bash
# Blocks: term_at, chrome_window, chrome_session, vlc_play, queue_next,
# notes_open, app_open, app_quit, aero_workspace, aero_pull, aero_layout, focus_on,
# focus_off, kill_distractions, osa (raw AppleScript). See lib/blocks.sh.

up() {
  aero_workspace "$LEARN_WS"   # or any letter you reach with alt-<letter>
  term_at ~/code/__NAME__
  chrome_window "https://example.com"
}

down() {
  :
}
