// Pure logic, no chrome.* calls, so node can test it.
// Everything a user would want to change lives in the config (see defaults.json).

export const PLACEHOLDER = /\{(TICKER|ticker|q)\}/g;

export function validateConfig(cfg) {
  const errors = [];
  if (!cfg || typeof cfg !== 'object') return ['config must be a JSON object'];
  const sites = cfg.sites || {};
  const presets = cfg.presets || {};
  if (typeof sites !== 'object' || !Object.keys(sites).length) errors.push('"sites" needs at least one entry');
  for (const [key, s] of Object.entries(sites)) {
    if (!s || typeof s.url !== 'string') { errors.push(`site "${key}" needs a "url"`); continue; }
    if (!/^https?:\/\//.test(s.url)) errors.push(`site "${key}" url must start with http(s)://`);
    if (!s.url.match(PLACEHOLDER)) errors.push(`site "${key}" url has no {TICKER}, {ticker} or {q}`);
  }
  for (const [key, list] of Object.entries(presets)) {
    if (sites[key]) errors.push(`"${key}" is both a site and a preset`);
    if (!Array.isArray(list) || !list.length) { errors.push(`preset "${key}" must be a non-empty list of site keys`); continue; }
    for (const k of list) if (!sites[k]) errors.push(`preset "${key}" names unknown site "${k}"`);
  }
  if (cfg.defaultPreset && !presets[cfg.defaultPreset] && !sites[cfg.defaultPreset])
    errors.push(`defaultPreset "${cfg.defaultPreset}" is not a preset or site`);
  try { tickerRegex(cfg); } catch { errors.push('tickerPattern is not a valid regex'); }
  return errors;
}

export function tickerRegex(cfg) {
  return new RegExp(cfg.tickerPattern || '^[A-Z][A-Z0-9.\\-]{0,9}$');
}

// "$gme " -> "GME"; returns null if it doesn't look like a ticker
export function normalizeTicker(raw, cfg) {
  const t = String(raw || '').trim().replace(/^\$/, '').toUpperCase();
  return tickerRegex(cfg).test(t) ? t : null;
}

export function buildUrl(template, ticker) {
  return template.replace(PLACEHOLDER, (_, p) =>
    p === 'TICKER' ? encodeURIComponent(ticker.toUpperCase())
    : p === 'ticker' ? encodeURIComponent(ticker.toLowerCase())
    : encodeURIComponent(ticker));
}

// Site keys for a preset or single site key. Unknown -> [].
export function expandTarget(target, cfg) {
  if (cfg.presets && cfg.presets[target]) return cfg.presets[target];
  if (cfg.sites && cfg.sites[target]) return [target];
  return [];
}

// Omnibox text -> { ticker, target }. Order-free: "gme rk", "rk gme", "gme".
// Words that name a preset/site are targets; the remaining word is the ticker.
export function parseQuery(text, cfg) {
  const words = String(text || '').trim().split(/\s+/).filter(Boolean);
  let target = null, ticker = null;
  for (const w of words) {
    const lw = w.toLowerCase();
    if (!target && expandTarget(lw, cfg).length && !(ticker === null && words.length === 1)) { target = lw; continue; }
    if (!ticker) ticker = normalizeTicker(w, cfg);
  }
  return { ticker, target: target || cfg.defaultPreset || Object.keys(cfg.presets || {})[0] || Object.keys(cfg.sites)[0] };
}

export function urlsFor(ticker, target, cfg) {
  return expandTarget(target, cfg).map(k => buildUrl(cfg.sites[k].url, ticker));
}

// Reverse a site template into a regex that captures the ticker, so any
// configured site doubles as a "which ticker is this page about" detector.
export function templateRegex(template) {
  const [base] = template.split('#');
  const esc = base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    .replace(/\\\{(TICKER|ticker|q)\\\}/g, '([A-Za-z0-9.\\-]+)');
  return new RegExp('^' + esc.replace(/^https?:/, 'https?:'), 'i');
}

export function tickerFromUrl(url, cfg) {
  for (const s of Object.values(cfg.sites || {})) {
    const m = String(url).match(templateRegex(s.url));
    if (m) {
      const t = normalizeTicker(decodeURIComponent(m[1]), cfg);
      if (t) return t;
    }
  }
  return null;
}

// Session <-> boring-env sessions/*.txt (one URL per line, # comments)
export function sessionToText(name, urls) {
  return `# ${name}\n${urls.join('\n')}\n`;
}

export function textToUrls(text) {
  return String(text).split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('#'));
}

// Layer one profile onto another. Sites and presets from `add` win on clashes;
// the base keeps its defaultPreset, pattern and colour.
export function mergeConfigs(base, add) {
  return {
    ...add, ...base,
    sites: { ...base.sites, ...add.sites },
    presets: { ...base.presets, ...add.presets },
  };
}
