import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as lib from '../lib.js';

const cfg = JSON.parse(readFileSync(new URL('../profiles/starter.json', import.meta.url)));

test('starter profile is a valid config', () => assert.deepEqual(lib.validateConfig(cfg), []));

test('validateConfig catches typos', () => {
  const bad = { sites: { a: { url: 'https://x.com/a' } }, presets: { p: ['a', 'nope'] }, defaultPreset: 'zz' };
  const errs = lib.validateConfig(bad).join('\n');
  assert.match(errs, /no \{TICKER\}/);
  assert.match(errs, /unknown site "nope"/);
  assert.match(errs, /defaultPreset "zz"/);
});

test('normalizeTicker', () => {
  assert.equal(lib.normalizeTicker(' $gme ', cfg), 'GME');
  assert.equal(lib.normalizeTicker('BRK.B', cfg), 'BRK.B');
  assert.equal(lib.normalizeTicker('not a ticker', cfg), null);
});

test('buildUrl fills upper/lower case', () => {
  assert.equal(lib.buildUrl('https://a.com/{ticker}?t={TICKER}#x', 'Gme'), 'https://a.com/gme?t=GME#x');
});

test('parseQuery is order-free and defaults to defaultPreset', () => {
  assert.deepEqual(lib.parseQuery('gme', cfg), { ticker: 'GME', target: 'quick' });
  assert.deepEqual(lib.parseQuery('gme quick', cfg), { ticker: 'GME', target: 'quick' });
  assert.deepEqual(lib.parseQuery('fv gme', cfg), { ticker: 'GME', target: 'fv' });
  // a lone word that happens to be a site key is still a ticker
  assert.deepEqual(lib.parseQuery('sa', cfg), { ticker: 'SA', target: 'quick' });
});

test('urlsFor expands presets and single sites', () => {
  assert.equal(lib.urlsFor('GME', 'quick', cfg).length, cfg.presets.quick.length);
  assert.deepEqual(lib.urlsFor('GME', 'fv', cfg), ['https://finviz.com/quote.ashx?t=GME']);
  assert.deepEqual(lib.urlsFor('GME', 'nope', cfg), []);
});

test('tickerFromUrl reverses any configured site', () => {
  assert.equal(lib.tickerFromUrl('https://finviz.com/quote.ashx?t=AAPL&p=d', cfg), 'AAPL');
  assert.equal(lib.tickerFromUrl('https://stockanalysis.com/stocks/nvda/financials/', cfg), 'NVDA');
  assert.equal(lib.tickerFromUrl('http://openinsider.com/GME', cfg), 'GME');
  assert.equal(lib.tickerFromUrl('https://example.com/', cfg), null);
});

test('sessions round-trip with boring-env sessions/*.txt', () => {
  const urls = ['https://a.com', 'https://b.com'];
  const text = lib.sessionToText('gme', urls);
  assert.equal(text, '# gme\nhttps://a.com\nhttps://b.com\n');
  assert.deepEqual(lib.textToUrls(text), urls);
});

test('every bundled profile is valid and listed', () => {
  const files = JSON.parse(readFileSync(new URL('../profiles/index.json', import.meta.url)));
  for (const f of files) {
    const p = JSON.parse(readFileSync(new URL(`../profiles/${f}`, import.meta.url)));
    assert.deepEqual(lib.validateConfig(p), [], f);
    assert.ok(p.name && p.about, `${f} needs name and about`);
  }
});

test('mergeConfigs layers a profile onto yours', () => {
  const rk = JSON.parse(readFileSync(new URL('../profiles/roaring-kitty.json', import.meta.url)));
  const merged = lib.mergeConfigs(cfg, rk);
  assert.deepEqual(lib.validateConfig(merged), []);
  assert.equal(merged.defaultPreset, cfg.defaultPreset);
  assert.ok(merged.presets.quick && merged.presets.all);
  assert.equal(merged.sites.oi.url, rk.sites.oi.url);
});
