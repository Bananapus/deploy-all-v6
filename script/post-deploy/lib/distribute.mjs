#!/usr/bin/env node
// distribute.mjs — Fan out generated artifacts to:
//
//   1. deploy-all-v6/deployments/juicebox-v6/<chain_alias>/<Contract>.json
//      (aggregator copy — every contract on this chain in one place)
//
//   2. <monorepo>/<repo>/deployments/<sphinxProject>/<chain_alias>/<Contract>.json
//      (per-repo copy — mirrors v5 layout so downstream tooling consumes
//      addresses from each source repo's deployments/ directly)
//
// Input: artifacts produced by artifacts.mjs, under
//   post-deploy/.cache/artifacts-<chainId>/<Contract>.json
//
// Usage:
//   node distribute.mjs --chain <chainId> [--in-dir <path>]
//   node distribute.mjs --chain <chainId> --dry-run   # print, no writes

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const POST_DEPLOY_DIR = path.resolve(__dirname, '..');
const DEPLOY_ROOT = path.resolve(POST_DEPLOY_DIR, '..', '..');
const MONOREPO_ROOT = path.resolve(DEPLOY_ROOT, '..');
const ARTIFACTS_DIR = path.join(DEPLOY_ROOT, 'artifacts');
const CACHE_DIR = path.join(POST_DEPLOY_DIR, '.cache');

const args = parseArgs(process.argv.slice(2));
if (!args.chain) die('Missing --chain <chainId>');
const CHAIN_ID = String(args.chain);
const DRY_RUN = Boolean(args['dry-run']);

const manifest = readJson({path: path.join(ARTIFACTS_DIR, 'artifacts.manifest.json')});
const chainsCfg = readJson({path: path.join(POST_DEPLOY_DIR, 'chains.json')});
const chain = chainsCfg.chains[CHAIN_ID];
if (!chain) die(`Unknown chainId ${CHAIN_ID}`);
const sphinxProjectByRepo = chainsCfg.sphinxProjectByRepo;

const inDir = args['in-dir'] ? path.resolve(args['in-dir']) : path.join(CACHE_DIR, `artifacts-${CHAIN_ID}`);
if (!fs.existsSync(inDir)) die(`No input artifacts dir: ${inDir} (run artifacts.mjs first)`);

const files = fs.readdirSync(inDir).filter((f) => f.endsWith('.json'));
console.log(`Distributing ${files.length} artifact(s) for chain ${CHAIN_ID} (${chain.alias})${DRY_RUN ? ' [DRY RUN]' : ''}`);

let writeCount = 0;
let skipCount = 0;

for (const file of files) {
  const contractName = file.replace(/\.json$/, '');
  const baseName = contractName.split('__')[0];
  const manifestEntry = manifest.contracts[baseName];
  if (!manifestEntry) {
    console.warn(`  SKIP    ${contractName}: not in manifest`);
    skipCount += 1;
    continue;
  }
  const sphinxProject = sphinxProjectByRepo[manifestEntry.repo];
  if (!sphinxProject) {
    console.warn(`  SKIP    ${contractName}: no sphinxProject mapping for repo ${manifestEntry.repo}`);
    skipCount += 1;
    continue;
  }
  const sourcePath = path.join(inDir, file);

  // Aggregator destination — always written.
  const aggregatorPath = path.join(DEPLOY_ROOT, 'deployments', 'juicebox-v6', chain.alias, file);

  // Per-repo destination. Special case: deploy-all-v6 = juicebox-v6 → same as aggregator (skip duplicate).
  const repoDir = manifestEntry.repo === 'deploy-all-v6' ? DEPLOY_ROOT : path.join(MONOREPO_ROOT, manifestEntry.repo);
  const perRepoPath = path.join(repoDir, 'deployments', sphinxProject, chain.alias, file);

  for (const dest of [aggregatorPath, perRepoPath]) {
    // Don't write to the same path twice (deploy-all-v6 owns both).
    if (dest === aggregatorPath && perRepoPath === aggregatorPath) continue;
    if (DRY_RUN) {
      console.log(`  would write  ${path.relative(MONOREPO_ROOT, dest)}`);
    } else {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.copyFileSync(sourcePath, dest);
    }
    writeCount += 1;
  }
  if (!DRY_RUN) console.log(`  ✓ ${contractName}.json → 2 destinations`);
}

console.log(`Done. ${writeCount} write(s), ${skipCount} skip(s).`);
process.exit(skipCount > 0 ? 1 : 0);

// ── helpers ──
function readJson({path: p}) { return JSON.parse(fs.readFileSync(p, 'utf8')); }

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok.startsWith('--')) {
      const key = tok.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith('--')) { out[key] = true; } else { out[key] = next; i += 1; }
    }
  }
  return out;
}

function die(msg) { console.error(`ERROR: ${msg}`); process.exit(2); }
