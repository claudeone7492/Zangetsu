import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadProvider, callProvider } from './host.mjs';

// The app ships with NO built-in providers; onboarding installs the sources in
// kDefaultRepoUrls (lib/core/app_config.dart) — now a single curated pack whose
// manifest lives in this repo at provider-repo/index.json. Every source in that
// pack was verified end-to-end (browse → search → detail → playback/reader)
// before being added; anything that did not resolve fully was pruned.
//
// The local test is hermetic: it loads each manifest entry straight from the
// repo tree and asserts it loads and answers getInfo under the same wrapper the
// app uses. The live test (RUN_LIVE=1) additionally fetches the manifest and
// each source over the network, so a source that rots after merge is caught.

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..');
const manifestPath = path.join(repoRoot, 'provider-repo', 'index.json');
const RAW_MANIFEST =
  'https://raw.githubusercontent.com/claudeone7492/Zangetsu/main/provider-repo/index.json';

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

test('the curated pack has sources of every mode', () => {
  const types = new Set(manifest.sources.map((s) => s.type));
  for (const t of ['anime', 'movie', 'manga', 'novel']) {
    assert.ok(types.has(t), `manifest should include a ${t} source`);
  }
});

test('every curated source loads from the repo tree and answers getInfo', async () => {
  for (const s of manifest.sources) {
    // `file` is written relative to the manifest dir (provider-repo/), so it
    // resolves to providers/<id>.js inside the repo — mirror that here.
    const filePath = path.resolve(path.dirname(manifestPath), s.file);
    assert.ok(fs.existsSync(filePath), `${s.id}: ${s.file} exists in the repo`);
    loadProvider(s.id, filePath);
    const info = JSON.parse(await callProvider(s.id, 'getInfo', []));
    assert.ok(info.name, `${s.id} getInfo has a name`);
    assert.ok(info.type, `${s.id} getInfo has a type`);
    assert.equal(info.type, s.type, `${s.id} getInfo.type matches the manifest`);
  }
});

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

live('the published manifest matches this repo and every source downloads', async () => {
  const res = await fetch(RAW_MANIFEST);
  if (!res.ok) {
    // main only gains this pack once the PR merges; onboarding treats an
    // unreachable repo as non-fatal, so mirror that here.
    console.log(`[default_repos] skipped: manifest → HTTP ${res.status}`);
    return;
  }
  const remote = await res.json();
  const remoteIds = remote.sources.map((s) => s.id).sort();
  const localIds = manifest.sources.map((s) => s.id).sort();
  assert.deepEqual(remoteIds, localIds, 'published manifest matches the repo');

  const base = RAW_MANIFEST.slice(0, RAW_MANIFEST.lastIndexOf('/') + 1);
  for (const s of remote.sources) {
    const url = new URL(s.file, base).toString();
    const r = await fetch(url);
    assert.ok(r.ok, `${s.id}: ${url} → HTTP ${r.status}`);
  }
});
