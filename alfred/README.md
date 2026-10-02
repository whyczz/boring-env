# Alfred wiring (Powerpack)

Alfred → Settings → Workflows → `+` → Blank Workflow, name it `boring-env`.

## 1. Keyword picker: type `ws`, pick a setup

1. Add **Inputs → Script Filter**
   - Keyword: `ws`, "Argument Optional"
   - Language: `/bin/bash`
   - Script: `~/code/boring-env/bin/ws alfred`
   - Tick "Alfred filters results"
2. Add **Actions → Run Script**, connect the Script Filter to it
   - Language: `/bin/bash`, input: **with input as argv**
   - Script: `~/code/boring-env/bin/ws $1 >/tmp/ws.log 2>&1`
     (`$1` is unquoted on purpose: the arg is `up learn` and must split)

Enter runs `up`. Hold ⌥ (alt) and Enter runs `down`. Last row is `kill`.

## 2. True one keystroke

Add **Triggers → Hotkey** (e.g. ⌃⌥L) → **Run Script**:
`~/code/boring-env/bin/ws learn >/tmp/ws.log 2>&1`

Something didn't open? `cat /tmp/ws.log`.
