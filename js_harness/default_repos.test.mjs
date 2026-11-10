import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadProvider, callProvider } from './host.mjs';

// The app ships with NO built-in providers; onboarding installs the sources in
// these manifests (kDefaultRepoUrls in lib/core/app_config.dart). Keep this list
// in sync with that constant. This test is the harness-side guard that every
// source a new user receives actually loads and answers getInfo under the same
// wrapper the app uses — a broken upstream provider shows up here, not as a
// silent empty Home for the user.
const REPOS = [
  'https://raw.githubusercontent.com/claudeone7492/Zangetsu/main/provider-repo/index.json',
  'https://raw.githubusercontent.com/Spyou/zangetsu-providers/main/index.json',
  'https://raw.githubusercontent.com/Spyou/Zangetsu-spyou-provider/main/index.json',
  'https://raw.githubusercontent.com/Spyou/sozoread-providers/main/index.json',
];

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

live('every default repo source loads and reports getInfo', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'default-repos-'));
  let checked = 0;
  const skipped = [];
  try {
    for (const repoUrl of REPOS) {
      const manifestRes = await fetch(repoUrl);
      if (!manifestRes.ok) {
        // The first-party pack lives on the app repo's main branch, which only
        // gains it once this branch's PR merges. Until then onboarding skips it
        // (unreachable repos are non-fatal) — mirror that here.
        skipped.push(`${repoUrl} → HTTP ${manifestRes.status}`);
        continue;
      }
      const manifest = await manifestRes.json();
      assert.ok(Array.isArray(manifest.sources), `${repoUrl} has a sources[]`);
      const base = repoUrl.slice(0, repoUrl.lastIndexOf('/') + 1);

      for (const s of manifest.sources) {
        const fileUrl = new URL(s.file, base).toString();
        const res = await fetch(fileUrl);
        assert.ok(res.ok, `${s.id}: ${fileUrl} → HTTP ${res.status}`);
        const local = path.join(dir, `${s.id}.js`);
        fs.writeFileSync(local, await res.text());

        loadProvider(s.id, new URL(`file://${local}`));
        const info = JSON.parse(await callProvider(s.id, 'getInfo', []));
        assert.ok(info.name, `${s.id} getInfo has a name`);
        assert.ok(info.type, `${s.id} getInfo has a type`);
        checked++;
      }
    }
    if (skipped.length) console.log('[default_repos] skipped:', skipped.join('; '));
    assert.ok(checked >= 20, `expected the full default set, validated ${checked}`);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
