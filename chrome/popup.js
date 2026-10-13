import { sessionToText, textToUrls } from './lib.js';

const $ = id => document.getElementById(id);
const getSessions = async () => (await chrome.storage.local.get('sessions')).sessions || {};
const setSessions = s => chrome.storage.local.set({ sessions: s });

// The tabs to save: the active tab's group if it has one, else the whole window.
async function currentScope() {
  const [active] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (active && active.groupId !== -1) {
    const group = await chrome.tabGroups.get(active.groupId);
    const tabs = await chrome.tabs.query({ groupId: active.groupId });
    return { label: `group "${group.title || 'untitled'}"`, name: group.title, tabs };
  }
  return { label: 'this window', name: '', tabs: await chrome.tabs.query({ currentWindow: true }) };
}

async function render() {
  const sessions = await getSessions();
  const names = Object.keys(sessions).sort();
  $('empty').hidden = names.length > 0;
  $('list').replaceChildren(...names.map(name => {
    const li = document.createElement('li');
    li.className = 'row';
    const label = Object.assign(document.createElement('span'), { className: 'grow', textContent: `${name} (${sessions[name].length})` });
    const btn = (text, fn) => { const b = Object.assign(document.createElement('button'), { textContent: text }); b.onclick = fn; return b; };
    li.append(label,
      btn('Open', () => chrome.windows.create({ url: sessions[name] })),
      btn('Copy', async () => {
        try { await navigator.clipboard.writeText(sessionToText(name, sessions[name])); $('msg').textContent = `Copied ${name} as sessions/${name}.txt text.`; }
        catch { $('msg').textContent = 'Clipboard blocked; open the session and copy URLs instead.'; }
      }),
      btn('Delete', async () => { delete sessions[name]; await setSessions(sessions); render(); }));
    return li;
  }));
}

$('save').onclick = async () => {
  const scope = await currentScope();
  const name = ($('name').value || scope.name || '').trim();
  if (!name) { $('msg').textContent = 'Give the session a name.'; return; }
  const urls = scope.tabs.map(t => t.url).filter(u => /^https?:/.test(u));
  const sessions = await getSessions();
  sessions[name] = urls;
  await setSessions(sessions);
  $('msg').textContent = `Saved ${urls.length} tabs as ${name}.`;
  render();
};

$('import').onclick = async () => {
  const urls = textToUrls($('paste').value);
  const name = $('pasteName').value.trim();
  if (!name || !urls.length) { $('msg').textContent = 'Need a name and at least one URL.'; return; }
  const sessions = await getSessions();
  sessions[name] = urls;
  await setSessions(sessions);
  $('paste').value = $('pasteName').value = '';
  render();
};

$('go').onsubmit = async e => {
  e.preventDefault();
  const res = await chrome.runtime.sendMessage({ type: 'open', text: $('q').value });
  if (res?.error) $('msg').textContent = res.error; else window.close();
};

currentScope().then(s => { $('scope').textContent = `Save grabs ${s.label} (${s.tabs.length} tabs).`; $('name').placeholder = s.name || 'session name'; });
render();
