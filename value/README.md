# value: an investor's lens as a CSV

Turns a ticker list into a spreadsheet of fundamentals, two fair values, a reverse-DCF growth rate and a score, through a **lens** (Shkreli, Roaring Kitty, or your own JSON). Stdlib Python, free data (SEC EDGAR XBRL + a public price feed).

```sh
export SEC_USER_AGENT="Your Name you@example.com"   # SEC wants a contact; falls back to git's email
python3 value/value.py --lens shkreli AAPL NVDA VRTX -o shk.csv
python3 value/value.py --lens roaring-kitty --watchlist value/watchlist.example.csv -o rk.csv
```

Open the CSV in Numbers or Google Sheets (File > Import), tweak assumptions, save the watchlist, rerun.

## The loop

1. Put tickers in a watchlist CSV. Optional columns override the lens per ticker: `growth`, `discount`, `terminal_multiple`, `price`.
2. Any other column you add (notes, short interest, drug odds) is carried through to the output.
3. Rerun. SEC responses are cached for 12h in `~/.cache/boring-value`.

## Columns

| column | meaning |
| --- | --- |
| `revenue`, `ebitda`, `fcf` | trailing twelve months (last FY + this YTD - last YTD) |
| `revenue_growth`, `dilution` | TTM vs the year before; dilution uses diluted share count |
| `net_cash` | cash + short-term investments - debt |
| `runway_q` | quarters of cash left at the current FCF burn (blank if FCF positive) |
| `dcf_value`, `dcf_upside` | 5-year DCF on the lens base (FCF or FCF - SBC) + terminal multiple + net cash, per share |
| `implied_growth` | reverse DCF: growth the current price needs |
| `multiple_value` | "auction test": lens multiple x EBIT/EBITDA + net cash, per share |
| `score`, `flags` | sum of the lens rules that fired, and which ones |

## Config, not code

- `lenses/*.json`: columns, DCF defaults, target multiple, scoring rules. Copy one to make your own: `--lens path/to/mine.json`.
- `sources.json`: SEC URLs, price feeds (tried in order) and the XBRL tags behind each number. When a company reports under an odd tag, add it there.

XBRL is messy: tags differ by company and debt can double count. A weird number means open the 10-K, which is what both lenses would tell you anyway.

Tests: `python3 -m unittest discover -s value/test`
