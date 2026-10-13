#!/usr/bin/env python3
"""Turn an investor's lens into a CSV you can iterate on.

  python3 value/value.py --lens shkreli AAPL NVDA > out.csv
  python3 value/value.py --lens roaring-kitty --watchlist value/watchlist.example.csv -o rk.csv

Data: SEC EDGAR XBRL company facts (free) + a price source from sources.json.
What gets computed, scored and flagged lives in lenses/*.json. Stdlib only.
"""
import argparse, csv, io, json, os, subprocess, sys, time, urllib.request
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.expanduser(os.environ.get("BORING_VALUE_CACHE", "~/.cache/boring-value"))


def load_json(path):
    with open(path) as f:
        return json.load(f)


# --- fetching -------------------------------------------------------------

def user_agent():
    # SEC wants "name email" in the UA; fall back to git's identity.
    ua = os.environ.get("SEC_USER_AGENT")
    if ua:
        return ua
    try:
        email = subprocess.run(["git", "config", "user.email"], capture_output=True, text=True).stdout.strip()
    except OSError:
        email = ""
    if not email:
        sys.exit("set SEC_USER_AGENT='Your Name you@example.com' (SEC requires a contact in the User-Agent)")
    return f"boring-env value {email}"


def fetch(url, max_age_h):
    key = os.path.join(CACHE, "".join(c if c.isalnum() else "_" for c in url)[-180:])
    if os.path.exists(key) and time.time() - os.path.getmtime(key) < max_age_h * 3600:
        with open(key, "rb") as f:
            return f.read()
    req = urllib.request.Request(url, headers={"User-Agent": user_agent(), "Accept-Encoding": "identity"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    os.makedirs(CACHE, exist_ok=True)
    with open(key, "wb") as f:
        f.write(body)
    time.sleep(0.15)  # SEC fair-access limit is 10 req/s
    return body


def cik_map(src):
    rows = json.loads(fetch(src["sec"]["tickers"], 24 * 7)).values()
    return {r["ticker"].upper(): (str(r["cik_str"]).zfill(10), r["title"]) for r in rows}


def price_for(ticker, src):
    for p in src["price"]:
        url = p["url"].replace("{TICKER}", ticker.upper()).replace("{ticker}", ticker.lower())
        try:
            body = fetch(url, 1)
            if "json" in p:
                v = json.loads(body)
                for k in p["json"]:
                    v = v[k]
            else:
                v = next(csv.DictReader(io.StringIO(body.decode())))[p["csv"]]
            return float(v)
        except Exception:
            continue
    return None


# --- XBRL -----------------------------------------------------------------

def _days(f):
    return (date.fromisoformat(f["end"]) - date.fromisoformat(f["start"])).days


def _facts(facts, tag, unit=None):
    ns, _, name = tag.rpartition(":")
    units = facts.get("facts", {}).get(ns or "us-gaap", {}).get(name, {}).get("units", {})
    if unit:
        return units.get(unit, [])
    return units.get("USD") or units.get("shares") or next(iter(units.values()), [])


def _dedupe(rows):
    # The same period shows up in every later filing; keep the latest-filed value.
    out = {}
    for f in sorted(rows, key=lambda f: f.get("filed", "")):
        out[(f.get("start"), f["end"])] = f
    return list(out.values())


def flow(facts, tag):
    """(ttm, prior_year) for a duration concept, or None if the tag has no annual data."""
    rows = _dedupe([f for f in _facts(facts, tag) if "start" in f])
    annual = sorted([f for f in rows if 350 <= _days(f) <= 380], key=lambda f: f["end"])
    if not annual:
        return None
    fy = annual[-1]
    prior = next((f for f in reversed(annual[:-1]) if 350 <= (date.fromisoformat(fy["end"]) - date.fromisoformat(f["end"])).days <= 380), None)
    ttm, prior_ttm = fy["val"], (prior["val"] if prior else None)
    # TTM = last FY + this year's YTD - last year's YTD, when a 10-Q is newer than the 10-K.
    ytd = [f for f in rows if f["end"] > fy["end"] and _days(f) < 350
           and abs((date.fromisoformat(f["start"]) - date.fromisoformat(fy["end"])).days) <= 10]
    if ytd:
        cur = max(ytd, key=lambda f: f["end"])
        base = _year_before(rows, cur)
        if base:
            ttm = fy["val"] + cur["val"] - base["val"]
            older = _year_before(rows, base)
            if prior and older:
                prior_ttm = prior["val"] + base["val"] - older["val"]
            elif prior and fy["val"]:
                prior_ttm = ttm * prior["val"] / fy["val"]  # no older YTD: reuse FY-over-FY growth
    return ttm, prior_ttm


def _year_before(rows, f):
    """The same-length period ending ~one year before f."""
    end = date.fromisoformat(f["end"])
    return next((g for g in rows if abs((end - date.fromisoformat(g["end"])).days - 365) <= 10
                 and abs(_days(g) - _days(f)) <= 10), None)


def instant(facts, tag, sum_classes=False):
    rows = [f for f in _facts(facts, tag) if "start" not in f]
    if not rows:
        return None
    end = max(f["end"] for f in rows)
    latest = [f for f in rows if f["end"] == end]
    accn = max(latest, key=lambda f: f.get("filed", ""))["accn"]
    vals = [f["val"] for f in latest if f["accn"] == accn]  # one per share class
    return sum(vals) if sum_classes else max(latest, key=lambda f: f.get("filed", ""))["val"]


def resolve(facts, spec, kind):
    if isinstance(spec, dict) and "sum" in spec:
        parts = [resolve(facts, s, kind) for s in spec["sum"]]
        parts = [p for p in parts if p is not None]
        return sum(parts) if parts else None
    if isinstance(spec, dict) and "classes" in spec:
        for tag in spec["classes"]:
            v = instant(facts, tag, sum_classes=True)
            if v:
                return v
        return None
    # Companies switch tags over the years; try the most recently reported one first.
    for tag in sorted(spec, key=lambda t: max((f["end"] for f in _facts(facts, t)), default=""), reverse=True):
        v = flow(facts, tag) if kind == "flow" else instant(facts, tag)
        if v is not None:
            return v
    return None


# --- metrics --------------------------------------------------------------

def div(a, b):
    return a / b if a is not None and b not in (None, 0) else None


def dcf(base, shares, net_cash, years, growth, discount, terminal_multiple):
    if base is None or base <= 0 or not shares:
        return None
    pv, cf = 0.0, base
    for t in range(1, years + 1):
        cf *= 1 + growth
        pv += cf / (1 + discount) ** t
    pv += cf * terminal_multiple / (1 + discount) ** years
    return (pv + (net_cash or 0)) / shares


def metrics(facts, src, price, lens, overrides=None):
    o = overrides or {}
    raw = {k: resolve(facts, spec, "flow") for k, spec in src["flows"].items()}
    ttm = {k: (v[0] if v else None) for k, v in raw.items()}
    prior = {k: (v[1] if v else None) for k, v in raw.items()}
    bs = {k: resolve(facts, spec, "instant") for k, spec in src["instants"].items()}

    m = dict(ttm)
    m.update(bs)
    rev, ebit = ttm["revenue"], ttm["operating_income"]
    m["ebitda"] = ebit + ttm["da"] if ebit is not None and ttm["da"] is not None else None
    m["fcf"] = ttm["cfo"] - (ttm["capex"] or 0) if ttm["cfo"] is not None else None
    m["fcf_minus_sbc"] = m["fcf"] - (ttm["sbc"] or 0) if m["fcf"] is not None else None
    m["revenue_growth"] = div(rev, prior["revenue"]) - 1 if div(rev, prior["revenue"]) else None
    m["dilution"] = div(ttm["diluted_shares"], prior["diluted_shares"]) - 1 if div(ttm["diluted_shares"], prior["diluted_shares"]) else None
    m["gross_margin"] = div(ttm["gross_profit"], rev)
    m["op_margin"] = div(ebit, rev)
    m["net_margin"] = div(ttm["net_income"], rev)
    m["rnd_pct_rev"] = div(ttm["rnd"], rev)
    m["sbc_pct_rev"] = div(ttm["sbc"], rev)
    cash = (bs["cash"] or 0) + (bs["st_investments"] or 0)
    m["net_cash"] = cash - (bs["debt"] or 0)
    m["debt_to_ebitda"] = div(bs["debt"], m["ebitda"]) if (m["ebitda"] or 0) > 0 else None
    m["runway_q"] = cash / (-m["fcf"] / 4) if m["fcf"] is not None and m["fcf"] < 0 else None

    m["price"] = price
    shares = bs["shares"] or ttm["diluted_shares"]
    m["market_cap"] = price * shares if price and shares else None
    mc = m["market_cap"]
    m["ev"] = mc - m["net_cash"] if mc else None
    m["net_cash_pct_mcap"] = div(m["net_cash"], mc)
    m["ev_sales"] = div(m["ev"], rev)
    m["ev_ebit"] = div(m["ev"], ebit) if (ebit or 0) > 0 else None
    m["ev_ebitda"] = div(m["ev"], m["ebitda"]) if (m["ebitda"] or 0) > 0 else None
    m["pe"] = div(mc, ttm["net_income"]) if (ttm["net_income"] or 0) > 0 else None
    m["pb"] = div(mc, bs["equity"]) if (bs["equity"] or 0) > 0 else None
    m["fcf_yield"] = div(m["fcf"], mc)

    d = dict(lens["dcf"])
    for k in ("growth", "discount", "terminal_multiple"):
        if o.get(k) not in (None, ""):
            d[k] = float(o[k])
    m["dcf_value"] = dcf(m[d["base"]], shares, m["net_cash"], int(d["years"]), d["growth"], d["discount"], d["terminal_multiple"])
    m["implied_growth"] = implied_growth(price, m[d["base"]], shares, m["net_cash"], int(d["years"]), d["discount"], d["terminal_multiple"])
    mult = lens["multiple"]
    base = m.get(mult["metric"])
    m["multiple_value"] = (base * mult["target"] + m["net_cash"]) / shares if base and base > 0 and shares else None
    m["dcf_upside"] = div(m["dcf_value"], price) - 1 if div(m["dcf_value"], price) else None
    m["multiple_upside"] = div(m["multiple_value"], price) - 1 if div(m["multiple_value"], price) else None
    return m


def implied_growth(price, base, shares, net_cash, years, discount, terminal_multiple):
    """Reverse DCF: the growth rate that makes dcf() equal today's price."""
    if not price or base is None or base <= 0 or not shares:
        return None
    lo, hi = -0.5, 1.0
    if dcf(base, shares, net_cash, years, hi, discount, terminal_multiple) < price:
        return hi  # market wants 100%+/yr: off the chart
    for _ in range(60):
        mid = (lo + hi) / 2
        if dcf(base, shares, net_cash, years, mid, discount, terminal_multiple) < price:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


OPS = {">": lambda a, b: a > b, ">=": lambda a, b: a >= b, "<": lambda a, b: a < b, "<=": lambda a, b: a <= b}


def score(m, rules):
    pts, flags = 0, []
    for r in rules:
        v = m.get(r["metric"])
        if v is not None and OPS[r["op"]](v, r["value"]):
            pts += r["points"]
            flags.append(r["flag"])
    return pts, "; ".join(flags)


def fmt(v):
    if isinstance(v, float):
        return f"{v:.4g}" if abs(v) < 1e4 else f"{v:.0f}"
    return "" if v is None else v


# --- main -----------------------------------------------------------------

def read_watchlist(path):
    with open(path, newline="") as f:
        return [r for r in csv.DictReader(f) if r.get("ticker", "").strip()]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tickers", nargs="*")
    ap.add_argument("--lens", default="shkreli", help="name in value/lenses/ or a path to a lens JSON")
    ap.add_argument("--watchlist", help="CSV with a ticker column; growth/discount/terminal_multiple/price columns override the lens")
    ap.add_argument("--sources", default=os.path.join(HERE, "sources.json"))
    ap.add_argument("-o", "--out", help="write CSV here instead of stdout")
    a = ap.parse_args(argv)

    lens_path = a.lens if a.lens.endswith(".json") else os.path.join(HERE, "lenses", a.lens + ".json")
    lens, src = load_json(lens_path), load_json(a.sources)
    rows = read_watchlist(a.watchlist) if a.watchlist else []
    rows += [{"ticker": t} for t in a.tickers]
    if not rows:
        ap.error("give tickers or --watchlist")

    ciks = cik_map(src)
    out = open(a.out, "w", newline="") if a.out else sys.stdout
    extra = [c for c in (rows[0].keys() if a.watchlist else []) if c not in lens["columns"]]
    w = csv.writer(out)
    w.writerow(lens["columns"] + extra)
    for r in rows:
        t = r["ticker"].strip().upper()
        if t not in ciks:
            print(f"skip {t}: not in SEC ticker list", file=sys.stderr)
            continue
        cik, name = ciks[t]
        try:
            facts = json.loads(fetch(src["sec"]["facts"].format(cik=cik), src["cache_hours"]))
        except Exception as e:
            print(f"skip {t}: {e}", file=sys.stderr)
            continue
        price = float(r["price"]) if r.get("price") else price_for(t, src)
        m = metrics(facts, src, price, lens, r)
        m["ticker"], m["name"] = t, name
        m["score"], m["flags"] = score(m, lens["rules"])
        w.writerow([fmt(m.get(c)) for c in lens["columns"]] + [r.get(c, "") for c in extra])
        print(f"{t}: score {m['score']}  {m['flags']}", file=sys.stderr)
    if a.out:
        out.close()


if __name__ == "__main__":
    main()
