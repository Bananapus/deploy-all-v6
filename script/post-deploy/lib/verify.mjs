#!/usr/bin/env node
// verify.mjs — Etherscan v2 contract verifier with retry + backoff.
//
// For each (chain, contract):
//   1. Load compile settings + source repo from artifacts.manifest.json.
//   2. Resolve the contract's full solc version (with commit hash) from the
//      artifact's embedded metadata.
//   3. Derive constructor args from the on-chain creation transaction.
//   4. Shell out to `forge verify-contract` from the SOURCE REPO so that
//      Foundry uses the right foundry.toml + source tree.
//   5. Retry transient failures (network / 429 / 5xx / "pending") with
//      exponential backoff. Permanent failures (compiler mismatch, source
//      mismatch, missing constructor args) hard-fail that contract and move on.
//   6. Track status in .cache/status-<chainId>.json so reruns skip the
//      already-verified contracts.
//
// Usage:
//   node verify.mjs --chain <chainId> [--contract <Name>] [--all]
// Env:
//   ETHERSCAN_API_KEY  — required (single key for the v2 unified API).
//   RPC_<UPPERCASE>    — optional; if present, used for direct eth_getTransactionByHash.
//                        Otherwise the script uses Etherscan's proxy module.
//
// Exit code: 0 if every contract verified or already-verified, non-zero if
// any contract failed permanently.

import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
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

// ── CLI args ──────────────────────────────────────────────────────────────
const args = parseArgs(process.argv.slice(2));
if (!args.chain) die('Missing --chain <chainId>');
const CHAIN_ID = String(args.chain);

const ETHERSCAN_KEY = process.env.ETHERSCAN_API_KEY;
if (!ETHERSCAN_KEY) die('ETHERSCAN_API_KEY environment variable is required.');

// ── Load manifest + chains config + addresses ─────────────────────────────
const manifest = readJson(path.join(ARTIFACTS_DIR, 'artifacts.manifest.json'));
const chainsCfg = readJson(path.join(POST_DEPLOY_DIR, 'chains.json'));
const chain = chainsCfg.chains[CHAIN_ID];
if (!chain) die(`Unknown chainId ${CHAIN_ID} (not in chains.json)`);

// Dirty-source gate: refuse to verify on production chains when the manifest
// was built from a dirty source tree. --rehearsal acknowledges non-production use.
if (manifest.gitDirty && chain.production && !args.rehearsal) {
  die(
    `Refusing to verify on production chain ${CHAIN_ID} (${chain.alias}): ` +
    `artifact manifest was built from a dirty source tree. ` +
    `Rebuild with a clean tree (./script/build-artifacts.sh) or pass --rehearsal.`
  );
}

const addressesPath = path.join(CACHE_DIR, `addresses-${CHAIN_ID}.json`);
if (!fs.existsSync(addressesPath)) {
  die(`Missing addresses file: ${addressesPath}\nRun the address dump first (forge script Deploy.s.sol --rpc-url ...).`);
}
const addresses = readJson(addressesPath);

// ── Status cache (idempotent reruns) ──────────────────────────────────────
const statusPath = path.join(CACHE_DIR, `status-${CHAIN_ID}.json`);
const status = fs.existsSync(statusPath) ? readJson(statusPath) : { chainId: CHAIN_ID, contracts: {} };
const persistStatus = () => fs.writeFileSync(statusPath, JSON.stringify(status, null, 2));

// ── Pick contracts to process ─────────────────────────────────────────────
const allContractsOnChain = Object.entries(addresses)
  .filter(([k, v]) => k !== 'format' && k !== 'chainId' && typeof v === 'string' && v.startsWith('0x'))
  .map(([name, addr]) => ({ name, address: addr.toLowerCase() }));

const targets = args.contract
  ? allContractsOnChain.filter((c) => c.name === args.contract)
  : allContractsOnChain;

if (targets.length === 0) {
  console.log(`No contracts to verify on chain ${CHAIN_ID}.`);
  process.exit(0);
}

console.log(`Verifying ${targets.length} contract(s) on chain ${CHAIN_ID} (${chain.alias}).`);

// Explicit allowlist of address-dump entries that may legitimately be skipped without failing the
// chain. Empty by default — every entry in addresses-<chainId>.json must verify successfully.
// Add a name here only if there is a documented reason it has no published artifact yet.
const VERIFY_SKIP_ALLOWLIST = new Set();

// ── Drive verification, contract by contract (Etherscan rate limit: ~5 req/s on free tier) ──
let permanentFailures = 0;
let skipFailures = 0;
for (const target of targets) {
  // Strip route suffix (e.g., "__ETH_USD") for manifest lookup.
  const baseName = target.name.split('__')[0];
  const entry = manifest.contracts[baseName];
  if (!entry) {
    if (VERIFY_SKIP_ALLOWLIST.has(target.name)) {
      console.warn(`  SKIP    ${target.name}: not in manifest (allowlisted)`);
    } else {
      console.error(`  ✗       ${target.name}: not in manifest (no published artifact)`);
      skipFailures += 1;
    }
    continue;
  }
  const cur = status.contracts[target.name] || {};
  // Cached "verified" only counts when the cache matches the current address, chain, and source.
  // A bare `status === "verified"` would silently accept the cache from a previous run that
  // targeted a different deployment of the same contract name.
  if (
    cur.status === 'verified' &&
    String(cur.address || '').toLowerCase() === target.address &&
    String(cur.chainId || '') === CHAIN_ID &&
    cur.sourcePath === entry.sourcePath &&
    cur.gitCommit === entry.gitCommit
  ) {
    console.log(`  cached  ${target.name}: already verified`);
    continue;
  }
  if (cur.status === 'verified') {
    // Cache hit but identity-mismatched — bust it and re-verify.
    console.warn(`  cache-busted  ${target.name}: cached identity does not match current target`);
  }
  try {
    await verifyOne({ target, entry, baseName });
    status.contracts[target.name] = {
      status: 'verified',
      address: target.address,
      chainId: CHAIN_ID,
      sourcePath: entry.sourcePath,
      gitCommit: entry.gitCommit,
      verifiedAt: new Date().toISOString()
    };
    persistStatus();
    console.log(`  ✓       ${target.name} @ ${target.address}`);
  } catch (err) {
    const reason = err?.message || String(err);
    if (err?.transient) {
      status.contracts[target.name] = {
        status: 'transient_failed',
        address: target.address,
        reason,
        lastAttemptAt: new Date().toISOString()
      };
      persistStatus();
      console.warn(`  RETRY   ${target.name}: ${reason}`);
    } else {
      status.contracts[target.name] = {
        status: 'failed',
        address: target.address,
        reason,
        failedAt: new Date().toISOString()
      };
      persistStatus();
      permanentFailures += 1;
      console.error(`  ✗       ${target.name}: ${reason}`);
    }
  }
}

console.log('');
const verifiedCount = Object.values(status.contracts).filter((s) => s.status === 'verified').length;
console.log(
  `Chain ${CHAIN_ID} summary: ${verifiedCount} verified, ${permanentFailures} permanent failures, ${skipFailures} unverifiable-skips.`
);
// Exit nonzero on either failure category: silent skips of current address entries are treated
// as critical the same way actual permanent failures are.
process.exit(permanentFailures + skipFailures > 0 ? 1 : 0);

// ════════════════════════════════════════════════════════════════════════
//  Helpers
// ════════════════════════════════════════════════════════════════════════

async function verifyOne({ target, entry, baseName }) {
  // Load artifact (we need its metadata for the exact solc commit hash, and
  // its creation bytecode length to slice the constructor args).
  const artifact = readJson(path.join(ARTIFACTS_DIR, `${baseName}.json`));
  const metadata = typeof artifact.metadata === 'string' ? JSON.parse(artifact.metadata) : artifact.metadata;
  const solcVersionFull = metadata?.compiler?.version
    ? `v${metadata.compiler.version}` // already has "+commit.<hash>"
    : `v${entry.solcVersion}`;

  // Look up creation tx via Etherscan + slice constructor args off its input.
  const creation = await getContractCreation(target.address);
  if (!creation?.txHash) {
    throw nonTransient(`No creation transaction found on explorer for ${target.address}`);
  }
  const txInput = await getTxInput(creation.txHash);
  const ctorArgsHex = sliceConstructorArgs(txInput, artifact.bytecode.object);

  // Resolve repo path. deploy-all-v6 has a special case (it IS DEPLOY_ROOT).
  const repoDir = entry.repo === 'deploy-all-v6' ? DEPLOY_ROOT : path.join(MONOREPO_ROOT, entry.repo);
  if (!fs.existsSync(repoDir)) throw nonTransient(`Source repo not found: ${repoDir}`);

  // Build the forge verify-contract argv.
  const forgeArgs = [
    'verify-contract',
    target.address,
    `${entry.sourcePath}:${baseName}`,
    '--chain-id', CHAIN_ID,
    '--watch',
    '--verifier', chain.verifier,
    '--verifier-url', chain.apiUrl,
    '--etherscan-api-key', ETHERSCAN_KEY,
    '--num-of-optimizations', String(entry.optimizerRuns),
    '--compiler-version', solcVersionFull,
    '--evm-version', entry.evmVersion
  ];
  if (entry.viaIr) forgeArgs.push('--via-ir');
  if (ctorArgsHex.length > 0) {
    forgeArgs.push('--constructor-args', `0x${ctorArgsHex}`);
  }
  // Pass every published library `--libraries <path>:<LibName>:<address>`. forge tolerates extra
  // library specs that the target source doesn't actually link against; this avoids needing to
  // parse the artifact's linkReferences for every contract. Without these, Etherscan re-compiles
  // the source with unresolved placeholders and rejects the verification.
  if (manifest.libraries && typeof manifest.libraries === 'object') {
    for (const [libName, libEntry] of Object.entries(manifest.libraries)) {
      if (libEntry?.sourcePath && libEntry?.address) {
        forgeArgs.push('--libraries', `${libEntry.sourcePath}:${libName}:${libEntry.address}`);
      }
    }
  }

  // Run forge with retry on transient failures.
  await withRetry(async () => {
    const result = await runProcess('forge', forgeArgs, repoDir);
    classifyForgeResult(result);
  });
}

function classifyForgeResult({ code, stdout, stderr }) {
  const out = `${stdout}\n${stderr}`.toLowerCase();
  if (code === 0 && /verified|already verified|pass - verified/.test(out)) return; // success
  if (code === 0) return; // forge --watch returns 0 on success; assume success if no failure markers.

  // Transient classifications.
  if (/rate limit|429|too many requests|timeout|econnreset|service unavailable|gateway|temporarily/.test(out)) {
    throw transient(`forge verify transient: code=${code}`);
  }
  if (/pending in queue|in progress/.test(out)) {
    throw transient(`forge verify pending: code=${code}`);
  }
  // Permanent classifications.
  if (/already verified/.test(out)) return; // edge case: forge exits non-zero but it's already verified.
  if (/source code does not match|bytecode does not match|unable to verify/.test(out)) {
    throw nonTransient(`forge verify rejected: source/bytecode mismatch`);
  }
  if (/compiler version mismatch|wrong compiler/.test(out)) {
    throw nonTransient(`forge verify rejected: compiler version mismatch`);
  }
  throw nonTransient(`forge verify failed (code=${code}): ${truncate(stderr || stdout, 400)}`);
}

// ── Retry harness ─────────────────────────────────────────────────────────
async function withRetry(fn, { maxAttempts = 10, baseMs = 1000, capMs = 60_000 } = {}) {
  let attempt = 0;
  let lastErr;
  while (attempt < maxAttempts) {
    attempt += 1;
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (!err?.transient) throw err;
      const wait = Math.min(capMs, baseMs * 2 ** (attempt - 1));
      console.warn(`    retry ${attempt}/${maxAttempts} in ${Math.round(wait / 1000)}s — ${err.message}`);
      await sleep(wait);
    }
  }
  throw lastErr;
}

function transient(message) {
  const e = new Error(message);
  e.transient = true;
  return e;
}

function nonTransient(message) {
  const e = new Error(message);
  e.transient = false;
  return e;
}

// ── Explorer / RPC calls ──────────────────────────────────────────────────
async function getContractCreation(address) {
  return await withRetry(async () => {
    const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=contract&action=getcontractcreation&contractaddresses=${address}&apikey=${ETHERSCAN_KEY}`;
    const res = await fetchWithTimeout(url);
    const text = await res.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      throw transient(`Explorer non-JSON response: ${truncate(text, 200)}`);
    }
    if (body.status === '1' && Array.isArray(body.result) && body.result[0]?.txHash) {
      return { txHash: body.result[0].txHash, creator: body.result[0].contractCreator };
    }
    // Etherscan returns status=0 with NOTOK message for various reasons.
    const msg = String(body.message || body.result || 'unknown');
    if (/rate limit|max calls|throttle/i.test(msg)) throw transient(`Explorer rate limited: ${msg}`);
    if (/not.*found|no.*record/i.test(msg)) throw nonTransient(`No creation tx for ${address} (yet?)`);
    throw transient(`Explorer error: ${msg}`);
  });
}

async function getTxInput(txHash) {
  return await withRetry(async () => {
    const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=proxy&action=eth_getTransactionByHash&txhash=${txHash}&apikey=${ETHERSCAN_KEY}`;
    const res = await fetchWithTimeout(url);
    const text = await res.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      throw transient(`Explorer non-JSON response: ${truncate(text, 200)}`);
    }
    if (body.result && typeof body.result.input === 'string') return body.result.input;
    throw transient(`Explorer eth_getTransactionByHash returned no input: ${JSON.stringify(body).slice(0, 200)}`);
  });
}

/**
 * Slice constructor args from the deployment tx input.
 *
 * Two cases:
 *  - CREATE2 factory call: input = 0x + salt(32 bytes) + initcode. initcode = creationCode + ctorArgs.
 *  - Direct CREATE/CREATE2 from a contract: tx.to is the contract; input is empty.
 *    Actual deployment goes through trace, not directly observable here.
 *
 * For factory-routed deploys (the all-precompile path), strip the salt prefix
 * then the creation bytecode, leaving ctorArgs.
 */
function sliceConstructorArgs(txInput, creationCodeHex) {
  const input = txInput.startsWith('0x') ? txInput.slice(2) : txInput;
  const creation = creationCodeHex.startsWith('0x') ? creationCodeHex.slice(2) : creationCodeHex;

  // Try factory pattern first: 32-byte salt then initcode.
  if (input.length >= 64 + creation.length && input.slice(64, 64 + creation.length).toLowerCase() === creation.toLowerCase()) {
    return input.slice(64 + creation.length);
  }
  // Try direct CREATE2 pattern: input is just initcode.
  if (input.toLowerCase().startsWith(creation.toLowerCase())) {
    return input.slice(creation.length);
  }
  // Fallback: locate creation bytecode within input (handles small prefix wrappers).
  const idx = input.toLowerCase().indexOf(creation.toLowerCase());
  if (idx >= 0) return input.slice(idx + creation.length);

  // Last-ditch: assume the deployment used a different bytecode (linked libraries, immutables in
  // creation code, etc.). Return empty and let Etherscan complain if constructor args were
  // actually required.
  return '';
}

// ── Subprocess + fetch helpers ────────────────────────────────────────────
async function runProcess(cmd, argv, cwd) {
  return await new Promise((resolve, reject) => {
    const proc = spawn(cmd, argv, { cwd, env: process.env });
    let stdout = '';
    let stderr = '';
    proc.stdout.on('data', (b) => (stdout += b.toString()));
    proc.stderr.on('data', (b) => (stderr += b.toString()));
    proc.on('error', reject);
    proc.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

async function fetchWithTimeout(url, { timeoutMs = 30_000 } = {}) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(t);
  }
}

// ── Misc utility ──────────────────────────────────────────────────────────
function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok.startsWith('--')) {
      const key = tok.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith('--')) {
        out[key] = true;
      } else {
        out[key] = next;
        i += 1;
      }
    }
  }
  return out;
}

function truncate(s, n) {
  if (!s) return '';
  return s.length <= n ? s : `${s.slice(0, n)}…`;
}

function die(msg) {
  console.error(`ERROR: ${msg}`);
  process.exit(2);
}
