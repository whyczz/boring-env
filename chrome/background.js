import { parseQuery, urlsFor, expandTarget, tickerFromUrl, normalizeTicker } from './lib.js';
import { loadConfig } from './config.js';

// Open a ticker's sites as one named tab group in the current window.
async function openDossier(ticker, target) {
  const cfg = await loadConfig();
  const urls = urlsFor(ticker, target, cfg);
  if (!urls.length) return;
  const win = await chrome.windows.getLastFocused();
  const tabs = [];
  for (const [i, url] of urls.entries())
    tabs.push(await chrome.tabs.create({ url, windowId: win.id, active: i === 0 }));
  const groupId = await chrome.tabs.group({ tabIds: tabs.map(t => t.id), createProperties: { windowId: win.id } });
  await chrome.tabGroups.update(groupId, { title: ticker, color: cfg.groupColor || 'blue' });
}

// --- omnibox: k GME, k GME rk, k fv GME ---------------------------------
chrome.omnibox.onInputChanged.addListener(async (text, suggest) => {
  const cfg = await loadConfig();
  const { ticker } = parseQuery(text, cfg);
  if (!ticker) return suggest([]);
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const rows = [
    ...Object.keys(cfg.presets || {}).map(p => ({ key: p, label: `${p}: ${cfg.presets[p].join(', ')}` })),
    ...Object.entries(cfg.sites).map(([k, s]) => ({ key: k, label: `${k}: ${s.name || k}` })),
  ];
  suggest(rows.map(r => ({ content: `${ticker} ${r.key}`, description: esc(`${ticker} → ${r.label}`) })));
});

chrome.omnibox.onInputEntered.addListener(async text => {
  const cfg = await loadConfig();
  const { ticker, target } = parseQuery(text, cfg);
  if (ticker) openDossier(ticker, target);
});

// --- right-click a highlighted ticker -------------------------------------
async function buildMenus() {
  const cfg = await loadConfig();
  await chrome.contextMenus.removeAll();
  chrome.contextMenus.create({ id: 'kk', title: 'Kitty Keys: "%s"', contexts: ['selection'] });
  for (const p of Object.keys(cfg.presets || {}))
    chrome.contextMenus.create({ id: `t:${p}`, parentId: 'kk', title: `${p} (${cfg.presets[p].length} sites)`, contexts: ['selection'] });
  chrome.contextMenus.create({ id: 'sep', parentId: 'kk', type: 'separator', contexts: ['selection'] });
  for (const [k, s] of Object.entries(cfg.sites))
    chrome.contextMenus.create({ id: `t:${k}`, parentId: 'kk', title: s.name || k, contexts: ['selection'] });
}
chrome.runtime.onInstalled.addListener(buildMenus);
chrome.runtime.onStartup.addListener(buildMenus);
chrome.storage.onChanged.addListener((changes, area) => { if (area === 'sync' && changes.config) buildMenus(); });

chrome.contextMenus.onClicked.addListener(async info => {
  if (!info.menuItemId.startsWith('t:')) return;
  const cfg = await loadConfig();
  const ticker = normalizeTicker(info.selectionText, cfg);
  const target = info.menuItemId.slice(2);
  if (ticker && expandTarget(target, cfg).length) openDossier(ticker, target);
});

// --- hotkeys ---------------------------------------------------------------
chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command !== 'dossier-from-page' || !tab) return;
  const cfg = await loadConfig();
  const ticker = tickerFromUrl(tab.url || '', cfg);
  if (ticker) openDossier(ticker, cfg.defaultPreset);
});

// --- popup's ticker box -----------------------------------------------------
chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg?.type !== 'open') return;
  loadConfig().then(cfg => {
    const { ticker, target } = parseQuery(msg.text, cfg);
    if (!ticker) return reply({ error: `"${msg.text}" doesn't look like a ticker` });
    openDossier(ticker, target).then(() => reply({ ticker, target }));
  });
  return true;
});
