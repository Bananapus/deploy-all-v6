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
//   node verify.mjs --chain <chainId> [--addresses-file <path>] [--contract <Name>] [--all]
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
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const POST_DEPLOY_DIR = path.resolve(__dirname, '..');
const DEPLOY_ROOT = path.resolve(POST_DEPLOY_DIR, '..', '..');
const MONOREPO_ROOT = path.resolve(DEPLOY_ROOT, '..');
const ARTIFACTS_DIR = path.join(DEPLOY_ROOT, 'artifacts');
const CACHE_DIR = path.join(POST_DEPLOY_DIR, '.cache');
const EXPLORER_MIN_INTERVAL_MS = Number(process.env.ETHERSCAN_MIN_INTERVAL_MS || 500);
let lastExplorerFetchAt = 0;

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

const addressesPath = args['addresses-file']
  ? path.resolve(args['addresses-file'])
  : path.join(CACHE_DIR, `addresses-${CHAIN_ID}.json`);
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

const ARTIFACT_ALIASES = new Map([
  ['BannyLPSplitHook', 'JBUniswapV4LPSplitHook']
]);

// Explicit allowlist of address-dump entries that may legitimately be skipped without failing the
// chain. Empty by default — every entry in addresses-<chainId>.json must verify successfully.
// Add a name here only if there is a documented reason it has no published artifact yet.
const VERIFY_SKIP_ALLOWLIST = new Set();

// ── Drive verification, contract by contract (Etherscan rate limit: ~5 req/s on free tier) ──
let permanentFailures = 0;
let skipFailures = 0;
let transientFailures = 0;
for (const target of targets) {
  // Strip route suffix (e.g., "__ETH_USD") for manifest lookup.
  const baseName = artifactNameFor(target.name);
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
  const cloneImplementation = cloneImplementationFor(target.name);
  if (cloneImplementation) {
    status.contracts[target.name] = {
      status: 'skipped_clone',
      address: target.address,
      chainId: CHAIN_ID,
      implementation: cloneImplementation.address,
      implementationName: cloneImplementation.name,
      reason: 'Explorer source/proxy verification does not support this clone runtime; implementation is verified separately.',
      skippedAt: new Date().toISOString()
    };
    persistStatus();
    console.warn(`  CLONE   ${target.name}: skipped source verification; implementation ${cloneImplementation.name} is verified separately`);
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
      transientFailures += 1;
      status.contracts[target.name] = {
        status: 'transient_failed',
        address: target.address,
        chainId: CHAIN_ID,
        sourcePath: entry.sourcePath,
        gitCommit: entry.gitCommit,
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
  `Chain ${CHAIN_ID} summary: ${verifiedCount} verified, ${permanentFailures} permanent failures, ${skipFailures} unverifiable-skips, ${transientFailures} transient failures.`
);
// Exit nonzero on either failure category: silent skips of current address entries are treated
// as critical the same way actual permanent failures are.
process.exit(permanentFailures + skipFailures + transientFailures > 0 ? 1 : 0);

// ════════════════════════════════════════════════════════════════════════
//  Helpers
// ════════════════════════════════════════════════════════════════════════

async function verifyOne({ target, entry, baseName }) {
  // Reruns should notice verifications that completed after a previous polling window
  // instead of submitting duplicate `verifysourcecode` requests.
  if (await contractHasAbi(target.address)) return;

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
  // Under Sphinx/Safe deployment the OUTER tx input is the Safe.execTransaction wrapper, and
  // slicing through it picks up wrapper ABI bytes as fake constructor args. Recover from the
  // internal call to the deterministic CREATE2 factory instead — its input is exactly
  // `0x + salt(32 bytes) + creationCode + constructorArgs`. Fall back to the outer input if no
  // factory call is present (non-Sphinx deploys).
  const ctorArgsHex = constructorArgsOverride(baseName) || await constructorArgsFromCreation({
    creation,
    artifact
  });

  const repoDir = resolveSourceRoot(entry);
  if (!fs.existsSync(repoDir)) throw nonTransient(`Source root not found: ${repoDir}`);
  const foundryProfile = verificationFoundryProfile(entry, repoDir);

  // Build the forge verify-contract argv.
  const forgeArgs = [
    'verify-contract',
    target.address,
    `${entry.sourcePath}:${baseName}`,
    '--chain-id', CHAIN_ID,
    '--watch',
    '--verifier', chain.verifier,
    '--verifier-url', chain.forgeApiUrl || chain.apiUrl,
    '--etherscan-api-key', ETHERSCAN_KEY,
    '--num-of-optimizations', String(entry.optimizerRuns),
    '--compiler-version', solcVersionFull,
    '--use', entry.solcVersion,
    '--no-auto-detect',
    '--evm-version', entry.evmVersion,
    '--skip-is-verified-check',
    '--retries', String(process.env.POST_DEPLOY_FORGE_VERIFY_RETRIES || 24),
    '--delay', String(process.env.POST_DEPLOY_FORGE_VERIFY_DELAY_SECONDS || 20)
  ];
  if (entry.viaIr) forgeArgs.push('--via-ir');
  if (ctorArgsHex.length > 0) {
    forgeArgs.push('--constructor-args', `0x${ctorArgsHex}`);
  }
  // Pass only the libraries this artifact actually links. Extra library specs can alter
  // metadata.settings.libraries for otherwise-unlinked contracts, causing explorer bytecode
  // mismatches even when the runtime bytecode is correct.
  for (const libSpec of librarySpecsForArtifact(artifact)) {
    forgeArgs.push('--libraries', libSpec);
  }

  const forgeScratch = makeForgeScratchDir();
  let result;
  try {
    result = await runProcess('forge', forgeArgs, repoDir, {
      FOUNDRY_PROFILE: foundryProfile || process.env.FOUNDRY_PROFILE || 'default',
      FOUNDRY_VIA_IR: entry.viaIr ? 'true' : 'false',
      FOUNDRY_CACHE_PATH: path.join(forgeScratch, 'cache'),
      FOUNDRY_OUT: path.join(forgeScratch, 'out')
    });
  } finally {
    fs.rmSync(forgeScratch, { recursive: true, force: true });
  }
  classifyForgeResult(result);
}

async function constructorArgsFromCreation({creation, artifact}) {
  const fromCreationBytecode = sliceConstructorArgsFromCreationBytecode(
    creation.creationBytecode,
    artifact.bytecode.object
  );
  if (fromCreationBytecode !== null) return fromCreationBytecode;

  const factoryInput = await getFactoryCallInput(creation.txHash);
  const txInput = factoryInput || await getTxInput(creation.txHash);
  return sliceConstructorArgs(txInput, artifact.bytecode.object);
}

function constructorArgsOverride(baseName) {
  if (baseName === 'JBUniswapV4LPSplitHook') {
    return encodeAddressArgs([
      addressOf('JBDirectory'),
      addressOf('JBPermissions'),
      addressOf('JBTokens'),
      '0x000000000022D473030F116dDEE9F6B43aC78BA3',
      addressOf('JBSuckerRegistry')
    ]);
  }
  return null;
}

function addressOf(name) {
  if (addresses[name]) return addresses[name];

  const file = path.join(DEPLOY_ROOT, 'deployments', chain.alias, `${name}.json`);
  if (!fs.existsSync(file)) throw nonTransient(`Missing ${name} in address dump and ${path.relative(DEPLOY_ROOT, file)}`);
  return readJson(file).address;
}

function encodeAddressArgs(values) {
  return values.map((value) => {
    const addr = String(value || '').toLowerCase();
    if (!/^0x[0-9a-f]{40}$/.test(addr)) throw nonTransient(`Invalid constructor address: ${value}`);
    return addr.slice(2).padStart(64, '0');
  }).join('');
}

function sliceConstructorArgsFromCreationBytecode(creationBytecodeHex, artifactCreationCodeHex) {
  if (!creationBytecodeHex) return null;
  const input = creationBytecodeHex.startsWith('0x') ? creationBytecodeHex.slice(2) : creationBytecodeHex;
  const creation = artifactCreationCodeHex.startsWith('0x') ? artifactCreationCodeHex.slice(2) : artifactCreationCodeHex;
  if (input.toLowerCase().startsWith(creation.toLowerCase())) return input.slice(creation.length);
  return null;
}

function artifactNameFor(name) {
  const baseName = name.split('__')[0];
  return ARTIFACT_ALIASES.get(baseName) || baseName;
}

function cloneImplementationFor(name) {
  let implementationName = null;
  const baseName = name.split('__')[0];
  const suffix = name.includes('__') ? name.slice(name.indexOf('__')) : '';
  if (baseName === 'BannyLPSplitHook') implementationName = 'JBUniswapV4LPSplitHook';
  else if (name.startsWith('JBERC20__')) implementationName = 'JBERC20';
  else if (name.startsWith('JB721TiersHook__')) implementationName = 'JB721TiersHook';
  else if (name.startsWith('JBProjectPayer__')) implementationName = 'JBProjectPayer';
  if (!implementationName) return null;

  const implementationAddress = addresses[implementationName] || addresses[`${implementationName}${suffix}`];
  if (!implementationAddress) return null;
  return { name: implementationName, address: String(implementationAddress).toLowerCase() };
}

function librarySpecsForArtifact(artifact) {
  if (!manifest.libraries || typeof manifest.libraries !== 'object') return [];

  const specs = [];
  const seen = new Set();
  for (const libName of linkedLibraryNames(artifact)) {
    const libEntry = manifest.libraries[libName];
    if (!libEntry?.sourcePath || !libEntry?.address) {
      throw nonTransient(`Missing manifest library entry for ${libName}`);
    }

    const spec = `${libEntry.sourcePath}:${libName}:${libEntry.address}`;
    if (seen.has(spec)) continue;
    seen.add(spec);
    specs.push(spec);
  }
  return specs;
}

function linkedLibraryNames(artifact) {
  const names = new Set();
  collectLinkedLibraryNames(names, artifact?.bytecode?.linkReferences);
  collectLinkedLibraryNames(names, artifact?.deployedBytecode?.linkReferences);
  return [...names].sort();
}

function collectLinkedLibraryNames(names, linkReferences) {
  if (!linkReferences || typeof linkReferences !== 'object') return;
  for (const libsBySource of Object.values(linkReferences)) {
    if (!libsBySource || typeof libsBySource !== 'object') continue;
    for (const libName of Object.keys(libsBySource)) {
      names.add(libName);
    }
  }
}

function resolveSourceRoot(entry) {
  if (entry.sourceRoot) return path.resolve(DEPLOY_ROOT, entry.sourceRoot);
  return entry.repo === 'deploy-all-v6' ? DEPLOY_ROOT : path.join(MONOREPO_ROOT, entry.repo);
}

function verificationFoundryProfile(entry, repoDir) {
  // npm package artifacts are compiled from deploy-all-v6 so source paths stay
  // as node_modules/... in metadata. forge verify-contract does not honor
  // FOUNDRY_VIA_IR=false from env, so use an explicit profile for the packages
  // whose deployment artifacts were built without viaIR.
  if (path.resolve(repoDir) !== DEPLOY_ROOT) return null;
  return entry.viaIr ? 'default' : 'verify_non_via_ir';
}

function makeForgeScratchDir() {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'deploy-all-v6-verify-'));
  fs.mkdirSync(path.join(scratch, 'cache'), { recursive: true });
  fs.mkdirSync(path.join(scratch, 'out'), { recursive: true });
  return scratch;
}

function classifyForgeResult({ code, stdout, stderr }) {
  const out = `${stdout}\n${stderr}`.toLowerCase();
  if (code === 0 && /verified|already verified|pass - verified/.test(out)) return; // success
  if (code === 0) return; // forge --watch returns 0 on success; assume success if no failure markers.

  // Permanent classifications. Check these before transient words because Foundry can print
  // "pending" logs before the final explorer status resolves to a hard failure.
  if (/already verified/.test(out)) return; // edge case: forge exits non-zero but it's already verified.
  if (/source code does not match|bytecode does not match|unable to verify|fail - unable to verify|invalid constructor arguments/.test(out)) {
    throw nonTransient(`forge verify rejected: source/bytecode mismatch`);
  }
  if (/compiler version mismatch|wrong compiler/.test(out)) {
    throw nonTransient(`forge verify rejected: compiler version mismatch`);
  }

  // Transient classifications.
  if (/rate limit|429|too many requests|timeout|econnreset|service unavailable|gateway|temporarily/.test(out)) {
    throw transient(`forge verify transient: code=${code}: ${truncate(stderr || stdout, 800)}`);
  }
  if (/pending in queue|in progress/.test(out)) {
    throw transient(`forge verify pending: code=${code}: ${truncate(stderr || stdout, 800)}`);
  }
  throw nonTransient(`forge verify failed (code=${code}): ${truncate(stderr || stdout, 400)}`);
}

// ── Retry harness ─────────────────────────────────────────────────────────
async function withRetry(
  fn,
  {
    maxAttempts = Number(process.env.POST_DEPLOY_VERIFY_RETRY_ATTEMPTS || 18),
    baseMs = Number(process.env.POST_DEPLOY_VERIFY_RETRY_BASE_MS || 2000),
    capMs = Number(process.env.POST_DEPLOY_VERIFY_RETRY_CAP_MS || 120_000)
  } = {}
) {
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
      return {
        txHash: body.result[0].txHash,
        creator: body.result[0].contractCreator,
        creationBytecode: body.result[0].creationBytecode
      };
    }
    // Etherscan returns status=0 with NOTOK message for various reasons.
    const msg = String(body.message || body.result || 'unknown');
    if (/rate limit|max calls|throttle/i.test(msg)) throw transient(`Explorer rate limited: ${msg}`);
    if (/not.*found|no.*record/i.test(msg)) throw nonTransient(`No creation tx for ${address} (yet?)`);
    throw transient(`Explorer error: ${msg}`);
  });
}

async function contractHasAbi(address) {
  return await withRetry(async () => {
    const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=contract&action=getabi&address=${address}&apikey=${ETHERSCAN_KEY}`;
    const res = await fetchWithTimeout(url);
    const text = await res.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      throw transient(`Explorer non-JSON ABI response: ${truncate(text, 200)}`);
    }

    if (body.status === '1' && typeof body.result === 'string' && body.result.startsWith('[')) return true;

    const msg = String(body.message || body.result || 'unknown');
    if (/rate limit|max calls|throttle/i.test(msg)) throw transient(`Explorer rate limited: ${msg}`);
    if (/not verified|contract source code not verified|invalid address format/i.test(msg)) return false;
    return false;
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

// The canonical deterministic CREATE2 factory used by every artifact deploy path.
const CREATE2_FACTORY = '0x4e59b44847b379578588920ca78fbf26c0b4956c';

/// Returns the internal call's `input` for the CREATE2 factory invocation inside `txHash`, or
/// null if no such internal call exists (non-Sphinx deployments). The factory's input is
/// `0x + salt(32 bytes) + creationCode + constructorArgs`, which `sliceConstructorArgs` slices
/// cleanly without picking up wrapper ABI bytes from the outer Safe.execTransaction. Mirrors the
/// helper in artifacts.mjs so the verifier and emitter share the same factory-call recovery.
async function getFactoryCallInput(txHash) {
  try {
    return await withRetry(async () => {
      const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=account&action=txlistinternal&txhash=${txHash}&apikey=${ETHERSCAN_KEY}`;
      const res = await fetchWithTimeout(url);
      const text = await res.text();
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        throw transient(`Explorer non-JSON response: ${truncate(text, 200)}`);
      }
      if (body.status !== '1' || !Array.isArray(body.result)) {
        const msg = String(body.message || body.result || 'unknown');
        if (/rate limit|throttle|max calls/i.test(msg)) throw transient(`Explorer rate limited: ${msg}`);
        return null;
      }
      const factoryCall = body.result.find(
        (entry) =>
          String(entry?.to || '').toLowerCase() === CREATE2_FACTORY
          && typeof entry?.input === 'string'
          && entry.input.length > 2
      );
      return factoryCall?.input || null;
    });
  } catch (err) {
    if (err?.transient) throw err;
    return null;
  }
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
async function runProcess(cmd, argv, cwd, envOverrides = {}) {
  return await new Promise((resolve, reject) => {
    const proc = spawn(cmd, argv, { cwd, env: { ...process.env, ...envOverrides } });
    let stdout = '';
    let stderr = '';
    proc.stdout.on('data', (b) => (stdout += b.toString()));
    proc.stderr.on('data', (b) => (stderr += b.toString()));
    proc.on('error', reject);
    proc.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

async function fetchWithTimeout(url, { timeoutMs = 30_000 } = {}) {
  const elapsed = Date.now() - lastExplorerFetchAt;
  if (elapsed < EXPLORER_MIN_INTERVAL_MS) await sleep(EXPLORER_MIN_INTERVAL_MS - elapsed);
  lastExplorerFetchAt = Date.now();

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
