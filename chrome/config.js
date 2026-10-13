// Config lives in chrome.storage.sync (follows your Chrome profile). Profiles in
// profiles/*.json are starting points you load in the options page.
import { validateConfig } from './lib.js';

export async function bundledProfile(file) {
  return (await fetch(chrome.runtime.getURL(`profiles/${file}`))).json();
}

export async function bundledProfiles() {
  const files = await (await fetch(chrome.runtime.getURL('profiles/index.json'))).json();
  return Promise.all(files.map(async file => ({ file, ...(await bundledProfile(file)) })));
}

export const defaults = () => bundledProfile('starter.json');

export async function loadConfig() {
  const { config } = await chrome.storage.sync.get('config');
  if (config && !validateConfig(config).length) return config;
  return defaults();
}

export async function saveConfig(cfg) {
  const errors = validateConfig(cfg);
  if (errors.length) return errors;
  try { await chrome.storage.sync.set({ config: cfg }); }
  catch (e) { return [`Chrome refused to save (sync items max out at 8 KB): ${e.message}`]; }
  return [];
}
