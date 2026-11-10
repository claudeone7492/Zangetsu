import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadProvider, callProvider } from './host.mjs';

// Offline guard for the first-party manifest: every source it advertises must
// have a file on disk that loads and answers getInfo under the app's wrapper.
// (js_harness/default_repos.test.mjs covers the same ground over the network,
// including the community packs.)
const repoDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'provider-repo');

test('every official source file exists and answers getInfo', async () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(repoDir, 'index.json'), 'utf8'));
  assert.ok(Array.isArray(manifest.sources) && manifest.sources.length > 0, 'has sources[]');

  const seen = new Set();
  for (const s of manifest.sources) {
    assert.ok(s.id && s.name && s.type, `${s.id || '?'}: id/name/type present`);
    assert.ok(!seen.has(s.id), `${s.id}: id is unique`);
    seen.add(s.id);

    const file = path.resolve(repoDir, s.file);
    assert.ok(fs.existsSync(file), `${s.id}: ${s.file} exists on disk`);

    loadProvider(s.id, new URL(`file://${file}`));
    const info = JSON.parse(await callProvider(s.id, 'getInfo', []));
    assert.ok(info.name, `${s.id}: getInfo has a name`);
    assert.ok(info.type, `${s.id}: getInfo has a type`);
  }

  // The five first-party providers this change adds.
  for (const id of ['framextv', 'netweb', 'vidsrc', 'vidlink', 'iptv']) {
    assert.ok(seen.has(id), `manifest advertises ${id}`);
  }
});
