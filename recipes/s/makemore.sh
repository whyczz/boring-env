# desc: makemore: Jupyter in makeless + next lecture in VLC + its Apple Note
# shellcheck shell=bash
# The next video comes from queues/makemore.txt (by YouTube id, so renames
# are fine). When you finish one: `b next makemore`.

CODE_DIR=~/s/karpathy/makeless
VIDEO_DIR=~/s/karpathy/videos
NOTES_FOLDER="Karpathy, Zero To Hero"

up() {
  kill_distractions
  aero_workspace "$STUDY_WS"   # auto: first empty one, banner says which

  # A: Ghostty in the repo, Jupyter server running (Ctrl-C drops you to a shell)
  term_at "$CODE_DIR" "uv run --with jupyter jupyter lab"

  # B: the next lecture in VLC (VLC offers "continue playback" where you left off)
  local video
  video=$(video_find "$(queue_next makemore)" "$VIDEO_DIR")
  vlc_play "$video"
  aero_pull    # activating VLC jumps to its window's workspace; drag it here

  # C: find or create the note for this lecture in the Karpathy folder
  notes_open "$(video_title "$video")" --folder "$NOTES_FOLDER" --stamp
  aero_pull

  focus_on
}

down() {
  app_quit VLC
  focus_off
  log "finished the video? b next makemore"
}
