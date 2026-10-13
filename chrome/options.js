import { loadConfig, saveConfig, defaults, bundledProfiles } from './config.js';
import { mergeConfigs, validateConfig } from './lib.js';

const $ = id => document.getElementById(id);

function showKeywords(cfg) {
  const rows = Object.entries(cfg.sites).map(([k, s]) => [s.name || k, k, s.url.replace(/\{(TICKER|ticker|q)\}/g, '%s')]);
  const w0 = Math.max(...rows.map(r => r[0].length)), w1 = Math.max(...rows.map(r => r[1].length));
  $('keywords').textContent = rows.map(([n, k, u]) => `${n.padEnd(w0)}  ${k.padEnd(w1)}  ${u}`).join('\n');
}

async function show(cfg) { $('cfg').value = JSON.stringify(cfg, null, 2); showKeywords(cfg); }

$('save').onclick = async () => {
  let cfg;
  try { cfg = JSON.parse($('cfg').value); }
  catch (e) { $('errors').textContent = `Not valid JSON: ${e.message}`; return; }
  const errors = await saveConfig(cfg);
  $('errors').textContent = errors.join('\n');
  $('status').textContent = errors.length ? '' : 'Saved.';
  if (!errors.length) showKeywords(cfg);
};

$('reset').onclick = async () => { await chrome.storage.sync.remove('config'); show(await defaults()); $('status').textContent = 'Reset.'; $('errors').textContent = ''; };

// Replace or merge a profile, then save straight away so the menus rebuild.
async function apply(profile, mode) {
  const errors = validateConfig(profile);
  if (errors.length) { $('errors').textContent = `${profile.name || 'Profile'} is invalid:\n${errors.join('\n')}`; return; }
  const { name, about, source, file, ...rest } = profile;
  const next = mode === 'merge' ? mergeConfigs(await loadConfig(), rest) : rest;
  const saveErrors = await saveConfig(next);
  $('errors').textContent = saveErrors.join('\n');
  if (saveErrors.length) return;
  show(next);
  $('status').textContent = `${mode === 'merge' ? 'Merged' : 'Loaded'} ${name || 'profile'}.`;
}

function profileRow(p) {
  const li = document.createElement('li');
  li.className = 'row';
  li.style.alignItems = 'flex-start';
  const text = document.createElement('div');
  text.className = 'grow';
  text.style.whiteSpace = 'normal';
  const title = Object.assign(document.createElement('strong'), { textContent: p.name });
  const about = Object.assign(document.createElement('div'), { className: 'muted', textContent: p.about || '' });
  text.append(title, about);
  if (p.source) text.append(Object.assign(document.createElement('a'), { href: p.source, target: '_blank', textContent: 'source' }));
  const btn = (label, mode) => { const b = Object.assign(document.createElement('button'), { textContent: label }); b.onclick = () => apply(p, mode); return b; };
  li.append(text, btn('Replace', 'replace'), btn('Merge', 'merge'));
  return li;
}

$('file').onchange = async e => {
  const f = e.target.files[0];
  if (!f) return;
  try { apply(JSON.parse(await f.text()), 'merge'); }
  catch (err) { $('errors').textContent = `${f.name} is not valid JSON: ${err.message}`; }
  e.target.value = '';
};

bundledProfiles().then(ps => $('profiles').replaceChildren(...ps.map(profileRow)));
loadConfig().then(show);
