# Kitty Keys

> be me
> see a ticker on X at 1am
> open 7 tabs, type it 7 times
> "eh, tomorrow"

Type a ticker once, get every research tab you care about in one named tab group.
Plain MV3 Chrome extension, no build step. Which sites open is config, not code.

## Install (1 min)

1. `chrome://extensions` → toggle **Developer mode** → **Load unpacked** → pick this `chrome/` folder.
2. Pin it. Open its **Options** and load a profile (below), or keep Starter.

## Use

| do | get |
|---|---|
| `k GME` in the address bar | the default preset for GME, as a tab group titled GME |
| `k GME rk` / `k rk GME` | a named preset (any order) |
| `k GME 10k` | one site |
| highlight a ticker → right-click → **Kitty Keys** | any preset or site for the selection |
| <kbd>⌥⇧K</kbd> on a page any configured site URL matches | default preset for that page's ticker |
| <kbd>⌥⇧S</kbd> (or the toolbar icon) | popup: type a ticker, save the current tab group/window as a session, reopen it, copy it |

Rebind keys at `chrome://extensions/shortcuts`.

## Profiles

A profile is a JSON file of sites and presets. **Replace** swaps your config for it; **Merge** adds its sites and presets to yours, so you can stack them.

| profile | where it comes from |
|---|---|
| `profiles/starter.json` | neutral four-site setup |
| `profiles/roaring-kitty.json` | Keith Gill's own walkthrough, [Tools Part 2 of 3](https://www.youtube.com/watch?v=x2CBcthRVKE): his "All" sites, insider/13F checks, `#anchor` URLs |
| `profiles/shkreli.json` | inferred from [martinshkreli/models](https://github.com/martinshkreli/models): filings + three statements to build a model, plus a lookup of his model for the ticker |

Write your own:

```json
{
  "name": "Mine",
  "about": "what it's for",
  "defaultPreset": "quick",
  "sites": { "fv": { "name": "Finviz", "url": "https://finviz.com/quote.ashx?t={TICKER}" } },
  "presets": { "quick": ["fv"] }
}
```

`{TICKER}` upper case, `{ticker}` lower case, `{q}` as typed. Put `#element-id` at the end of a URL and the page lands scrolled there (find the id with Inspect). Load it with **Load your own profile** in Options, or drop it in `profiles/` and add it to `profiles/index.json`.

The options page also prints every site as a Chrome site-search line, if you'd rather skip the extension for single sites.

## Sessions

Saved sessions export as plain text, one URL per line with a `# name` header (the Session Buddy-style format). Paste one back in through the popup's import box.

## Dev

```sh
cd chrome && npm test      # node --test, no deps
```

`lib.js` is the pure logic and is what the tests cover. `background.js`, `popup.js` and `options.js` are thin wrappers around Chrome APIs. Config lives in `chrome.storage.sync`, which caps one item at 8 KB.
