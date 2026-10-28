import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { deprecatedPathFor } from './deprecated.mjs';

const write = (dir, file, address) => fs.writeFileSync(path.join(dir, file), JSON.stringify({ address }));

test('retires an outgoing artifact after the highest suffix, never into a gap', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'deprecated-'));
  const dest = path.join(dir, 'Hook.json');
  write(dir, 'Hook.json', '0xccc');
  assert.equal(deprecatedPathFor({ dest, name: 'Hook', address: '0xddd' }), path.join(dir, 'Hook_deprecated.json'));
  write(dir, 'Hook_deprecated.json', '0xaaa');
  write(dir, 'Hook_deprecated2.json', '0xbbb');
  assert.equal(deprecatedPathFor({ dest, name: 'Hook', address: '0xddd' }), path.join(dir, 'Hook_deprecated3.json'));
  // Same address rewritten, or the outgoing one already retired (even past a gap): nothing to keep.
  assert.equal(deprecatedPathFor({ dest, name: 'Hook', address: '0xCCC' }), null);
  write(dir, 'Hook_deprecated5.json', '0xccc');
  assert.equal(deprecatedPathFor({ dest, name: 'Hook', address: '0xddd' }), null);
  // Other contracts' records sharing a prefix do not count.
  write(dir, 'HookLib_deprecated7.json', '0xeee');
  fs.rmSync(path.join(dir, 'Hook_deprecated5.json'));
  assert.equal(deprecatedPathFor({ dest, name: 'Hook', address: '0xddd' }), path.join(dir, 'Hook_deprecated3.json'));
  assert.equal(deprecatedPathFor({ dest: path.join(dir, 'Missing.json'), name: 'Missing', address: '0x1' }), null);
});
