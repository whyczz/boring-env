# Alfred wiring (Powerpack)

No GUI clicking. The workflow is generated from `info.plist.template`:

```sh
alfred/build.sh      # builds boring-env.alfredworkflow for this checkout and opens it
```

Alfred pops an import dialog. Hit Import and you're done.

What you get:
- **`b` keyword**: lists your recipes (from `b alfred`). Enter runs `up`,
  ⌥+Enter runs `down`, and the last row is `kill`.
- **⌃⌥L hotkey**: `b l makemore`, no typing at all.

Moved the repo or added hotkeys? Edit the template and re-run `build.sh`.
Re-importing replaces the old copy, because the bundle id stays the same.
Logs go to `/tmp/b.log`.

Sidebar: the hotkey keycode lives in the template (`hotkey` 37 = L,
`hotmod` 786432 = ⌃⌥). If ⌃⌥L clashes with AeroSpace, change it there,
or rebind it once in Alfred's UI (that change survives until you re-import).
