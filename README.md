# boring-env

> be me
> want to watch Karpathy
> 30 seconds of opening Ghostty, Chrome, VLC, Notes
> "eh, tomorrow"
> never

One keystroke to a ready workspace. Plain bash + AppleScript, stock macOS,
zero required deps. The hard part of a habit is starting; this deletes it.

```
b l makemore       # Ghostty in ~/s/karpathy/makeless running Jupyter, next
                   # lecture from ~/s/karpathy/videos in VLC, its Apple Note
                   # in "Karpathy, Zero To Hero", Slack/X gone, Focus on
b down l makemore  # tear down
b next makemore    # mark the lecture watched; next run plays the next one
b kill         # just nuke distractions
```

## Install (2 min)

```sh
git clone https://github.com/whyczz/boring-env ~/code/boring-env
ln -s ~/code/boring-env/bin/b ~/.local/bin/b     # or anywhere on PATH
B_DRY=1 b l makemore                             # dry run: prints, opens nothing
~/code/boring-env/alfred/build.sh                # install Alfred workflow (`b` keyword, ⌃⌥L)
b l makemore                                      # the real thing
```

First real run: macOS asks "allow Terminal/Alfred to control Notes / Chrome /
System Events". Click Allow once. That's the TCC tax.

Optional bits (each block skips itself if missing):
- **Focus mode**: in Shortcuts.app make `Focus On` (Set Focus → Do Not Disturb → On)
  and `Focus Off`. Names configurable in `local.sh`.
- **AeroSpace**: `aero_workspace L` jumps there first so new windows land on it; `aero_pull L` after an app that already has a window elsewhere (VLC, Notes) drags it over.

## Layout

| path | what |
|---|---|
| `bin/b` | the CLI |
| `lib/blocks.sh` | the Lego: one function per action |
| `recipes/l/*.sh` | one recipe per workspace, grouped by letter (`l` = learn): `recipes/l/makemore.sh` is `b l makemore`. Each defines `up()` / `down()` |
| `sessions/*.txt` | Chrome tab lists, one URL per line (Session Buddy replacement) |
| `queues/*.txt` | "what's next" lists, top line plays next |
| `distractions.txt` | `app:Slack`, `tab:x.com` lines for `b kill` |
| `local.sh` | per-machine overrides, gitignored (see `local.sh.example`) |
| `alfred/` | `build.sh` generates + installs the Alfred workflow |

## Blocks

| block | does |
|---|---|
| `term_at DIR [CMD]` | new Ghostty window in DIR, optionally runs CMD |
| `chrome_window URL...` | new Chrome window with those tabs |
| `chrome_session NAME` | `sessions/NAME.txt` as a window |
| `chrome_close_matching TEXT...` | close tabs whose URL contains TEXT |
| `vlc_play SRC [START_SEC]` | play file/URL in the running VLC (no second instance) |
| `queue_next NAME` | print top of `queues/NAME.txt` |
| `notes_open TITLE [--stamp] [--folder NAME]` | find or create an Apple Note, optionally in a (nested) folder, optionally with a dated heading |
| `video_find KEY [DIR]`, `video_title FILE` | resolve a queue id to a local video, derive a note title |
| `app_open APP` / `app_quit APP...` | launch / politely quit |
| `aero_workspace NAME`, `aero_pull NAME`, `aero_layout ...` | AeroSpace |
| `focus_on` / `focus_off` | run your Focus Shortcuts |
| `kill_distractions` | apply `distractions.txt` |
| `osa 'SCRIPT' ARGS...` | raw AppleScript escape hatch (`on run argv`) |

New recipe: `b new l deepwork` copies `recipes/_template.sh` to `recipes/l/deepwork.sh` and opens it.

Videos: `video_find ID DIR` matches a YouTube id (or any piece of the filename)
in DIR, so queues can list ids and you can rename files freely as long as the
`[id]` stays. `video_title FILE` turns the filename into the note title.

## Sidebar: VLC + YouTube

VLC plays YouTube URLs through a Lua script that breaks whenever YouTube
changes things. If a URL won't play: update VLC, or download once and queue
the local file (VLC also remembers where you stopped in local files):

```sh
brew install yt-dlp
yt-dlp -o '~/Videos/learn/%(title)s.%(ext)s' 'https://www.youtube.com/watch?v=VMj-3S1tku0'
```

## Known quirks

- `open -na Ghostty` starts a fresh Ghostty process per call (extra dock icon).
  Harmless; if it bugs you, swap `term_at` for an AppleScript keystroke version.
- Re-running `b l makemore` opens a second set of windows. Use `b down` first.
- Alfred runs with a bare PATH; `b` adds `/opt/homebrew/bin` itself.

## Test

`test/smoke.sh` dry-runs every recipe and checks the CLI. CI runs it on Linux
and on macOS's ancient bash 3.2.
