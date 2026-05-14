#!/usr/bin/env node
// artifacts.mjs — Emit sphinx-sol-ct-artifact-1 JSON per (chain, contract).
//
// Output schema mirrors the v5 layout (nana-core-v5/...) byte-for-byte EXCEPT
// the `merkleRoot` field is omitted (we are not produced via a Sphinx merkle
// batch, and downstream tooling treats the field as informational).
//
// Schema fields produced:
//   format, address, sourceName, contractName, chainId (hex),
//   abi, args, solcInputHash, receipt, bytecode, deployedBytecode,
//   metadata (stringified), gitCommit, history.
//
// Inputs:
//   --chain <chainId>                  required
//   --contract <Name>                  optional; default: all in addresses-<chain>.json
//   --out-dir <path>                   optional; default: post-deploy/.cache/artifacts-<chain>/
//
// Env:
//   ETHERSCAN_API_KEY                  required (for getcontractcreation + receipt fetch).

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const POST_DEPLOY_DIR = path.resolve(__dirname, '..');
const DEPLOY_ROOT = path.resolve(POST_DEPLOY_DIR, '..', '..');
const ARTIFACTS_DIR = path.join(DEPLOY_ROOT, 'artifacts');
const CACHE_DIR = path.join(POST_DEPLOY_DIR, '.cache');

const args = parseArgs(process.argv.slice(2));
if (!args.chain) die('Missing --chain <chainId>');
const CHAIN_ID = String(args.chain);

const ETHERSCAN_KEY = process.env.ETHERSCAN_API_KEY;
if (!ETHERSCAN_KEY) die('ETHERSCAN_API_KEY required for receipt fetch.');

const manifest = readJson({path: path.join(ARTIFACTS_DIR, 'artifacts.manifest.json')});
const chainsCfg = readJson({path: path.join(POST_DEPLOY_DIR, 'chains.json')});
const chain = chainsCfg.chains[CHAIN_ID];
if (!chain) die(`Unknown chainId ${CHAIN_ID}`);

// Dirty-source gate: refuse to emit artifacts for production chains when the
// manifest was built from a dirty source tree. --rehearsal acknowledges non-production use.
if (manifest.gitDirty && chain.production && !args.rehearsal) {
  die(
    `Refusing to emit artifacts for production chain ${CHAIN_ID} (${chain.alias}): ` +
    `artifact manifest was built from a dirty source tree. ` +
    `Rebuild with a clean tree (./script/build-artifacts.sh) or pass --rehearsal.`
  );
}

const addressesPath = path.join(CACHE_DIR, `addresses-${CHAIN_ID}.json`);
if (!fs.existsSync(addressesPath)) die(`Missing addresses file: ${addressesPath}`);
const addresses = readJson({path: addressesPath});

const outDir = args['out-dir'] ? path.resolve(args['out-dir']) : path.join(CACHE_DIR, `artifacts-${CHAIN_ID}`);
// Prune any artifact files from a previous run so distribution only sees JSONs
// produced in this invocation. Without this, a target that was emitted in a
// previous run but is missing from the current address dump (e.g. renamed,
// removed) would still be picked up by distribute.mjs's readdirSync and copied
// to deployments/ with stale content.
if (fs.existsSync(outDir)) {
  fs.rmSync(outDir, { recursive: true, force: true });
}
fs.mkdirSync(outDir, { recursive: true });

const targets = Object.entries(addresses)
  .filter(([k, v]) => k !== 'format' && k !== 'chainId' && typeof v === 'string' && v.startsWith('0x'))
  .filter(([k]) => !args.contract || k === args.contract)
  .map(([name, addr]) => ({ name, address: addr.toLowerCase() }));

console.log(`Generating ${targets.length} artifact(s) for chain ${CHAIN_ID} (${chain.alias}) → ${path.relative(DEPLOY_ROOT, outDir)}/`);

let okCount = 0;
let failCount = 0;
for (const target of targets) {
  try {
    const out = await buildArtifact({target});
    const outPath = path.join(outDir, `${target.name}.json`);
    // Match v5's tab-indented JSON formatting.
    fs.writeFileSync(outPath, jsonStringifyTabs({value: out}));
    okCount += 1;
    console.log(`  ✓ ${target.name}.json`);
  } catch (err) {
    failCount += 1;
    console.error(`  ✗ ${target.name}: ${err.message}`);
  }
}

console.log(`Done. ${okCount} ok, ${failCount} failed.`);
process.exit(failCount > 0 ? 1 : 0);

// ════════════════════════════════════════════════════════════════════════
//  Build a single artifact
// ════════════════════════════════════════════════════════════════════════

async function buildArtifact({target}) {
  // Strip multi-instance route suffix for manifest + artifact lookups.
  const baseName = target.name.split('__')[0];
  const manifestEntry = manifest.contracts[baseName];
  if (!manifestEntry) throw new Error(`not in manifest`);

  const forgeArtifact = readJson({path: path.join(ARTIFACTS_DIR, `${baseName}.json`)});
  const metadataString =
    typeof forgeArtifact.metadata === 'string' ? forgeArtifact.metadata : JSON.stringify(forgeArtifact.metadata);
  const metadataObj = typeof forgeArtifact.metadata === 'string' ? JSON.parse(forgeArtifact.metadata) : forgeArtifact.metadata;

  // Fetch creation tx + receipt from the explorer.
  const creation = await getContractCreation({address: target.address});
  if (!creation?.txHash) throw new Error(`no creation tx (explorer)`);
  const receipt = await getTxReceipt({txHash: creation.txHash});
  if (!receipt) throw new Error(`no receipt for ${creation.txHash}`);

  // Constructor args = tx input minus salt(32 bytes) minus creation bytecode.
  const txInput = await getTxInput({txHash: creation.txHash});
  const ctorArgsHex = sliceConstructorArgs({txInput, creationCodeHex: forgeArtifact.bytecode.object});
  const argsDecoded = decodeConstructorArgs({abi: forgeArtifact.abi, ctorArgsHex});

  // solcInputHash — v5 uses md5 of the full metadata string. Mirror that.
  const solcInputHash = crypto.createHash('md5').update(metadataString).digest('hex');

  return {
    format: 'sphinx-sol-ct-artifact-1',
    address: target.address,
    sourceName: manifestEntry.sourcePath,
    contractName: baseName,
    chainId: `0x${Number(CHAIN_ID).toString(16)}`,
    abi: forgeArtifact.abi,
    args: argsDecoded,
    solcInputHash,
    receipt,
    bytecode: forgeArtifact.bytecode.object,
    deployedBytecode: forgeArtifact.deployedBytecode.object,
    metadata: metadataString,
    gitCommit: manifestEntry.gitCommit || 'unknown',
    gitDirty: Boolean(manifestEntry.gitDirty),
    history: []
  };
}

// ════════════════════════════════════════════════════════════════════════
//  Explorer / decode helpers
// ════════════════════════════════════════════════════════════════════════

async function getContractCreation({address}) {
  return await withRetry({fn: async () => {
    const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=contract&action=getcontractcreation&contractaddresses=${address}&apikey=${ETHERSCAN_KEY}`;
    const res = await fetchWithTimeout({url});
    const body = await parseJsonOrThrow({res});
    if (body.status === '1' && Array.isArray(body.result) && body.result[0]?.txHash) {
      return { txHash: body.result[0].txHash, creator: body.result[0].contractCreator };
    }
    const msg = String(body.message || body.result || 'unknown');
    if (/rate limit|throttle|max calls/i.test(msg)) throw transientError({message: `rate limited: ${msg}`});
    throw nonTransientError({message: `getcontractcreation: ${msg}`});
  }});
}

async function getTxReceipt({txHash}) {
  return await withRetry({fn: async () => {
    const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=proxy&action=eth_getTransactionReceipt&txhash=${txHash}&apikey=${ETHERSCAN_KEY}`;
    const res = await fetchWithTimeout({url});
    const body = await parseJsonOrThrow({res});
    if (body.result && typeof body.result === 'object') return body.result;
    throw transientError({message: `eth_getTransactionReceipt: ${JSON.stringify(body).slice(0, 200)}`});
  }});
}

async function getTxInput({txHash}) {
  return await withRetry({fn: async () => {
    const url = `${chain.apiUrl}?chainid=${CHAIN_ID}&module=proxy&action=eth_getTransactionByHash&txhash=${txHash}&apikey=${ETHERSCAN_KEY}`;
    const res = await fetchWithTimeout({url});
    const body = await parseJsonOrThrow({res});
    if (body.result?.input) return body.result.input;
    throw transientError({message: `eth_getTransactionByHash: no input`});
  }});
}

function sliceConstructorArgs({txInput, creationCodeHex}) {
  const input = txInput.startsWith('0x') ? txInput.slice(2) : txInput;
  const creation = creationCodeHex.startsWith('0x') ? creationCodeHex.slice(2) : creationCodeHex;
  if (input.length >= 64 + creation.length && input.slice(64, 64 + creation.length).toLowerCase() === creation.toLowerCase()) {
    return input.slice(64 + creation.length);
  }
  if (input.toLowerCase().startsWith(creation.toLowerCase())) return input.slice(creation.length);
  const idx = input.toLowerCase().indexOf(creation.toLowerCase());
  if (idx >= 0) return input.slice(idx + creation.length);
  return '';
}

/**
 * Decode constructor args into v5-compatible array form. v5 stores them as a
 * JSON array of primitives (addresses, strings, uint stringified). We do a
 * best-effort decode using the ABI; for non-trivial types we emit raw hex.
 */
function decodeConstructorArgs({abi, ctorArgsHex}) {
  if (!ctorArgsHex || ctorArgsHex.length === 0) return [];
  const ctor = (abi || []).find((f) => f?.type === 'constructor');
  if (!ctor?.inputs?.length) return [];

  try {
    // Lightweight ABI decoder for primitives. Defer complex types to raw hex.
    const types = ctor.inputs.map((i) => i.type);
    return decodePrimitivesAbi({types, dataHex: ctorArgsHex});
  } catch {
    return [`0x${ctorArgsHex}`];
  }
}

/**
 * Minimal head-only ABI decoder. Handles address / uintN / intN / bool / bytesN /
 * static-length tuples. Returns raw hex for dynamic types since we don't ship
 * a full ABI decoder here. Good enough for verify-readable output.
 */
function decodePrimitivesAbi({types, dataHex}) {
  const out = [];
  let offset = 0;
  for (const t of types) {
    if (offset + 64 > dataHex.length) {
      out.push(`0x${dataHex.slice(offset)}`);
      break;
    }
    const word = dataHex.slice(offset, offset + 64);
    offset += 64;
    if (t === 'address') {
      out.push(`0x${word.slice(24)}`);
    } else if (t === 'bool') {
      out.push(word.endsWith('1'));
    } else if (/^uint\d*$/.test(t) || /^int\d*$/.test(t)) {
      out.push(BigInt(`0x${word}`).toString());
    } else if (/^bytes\d+$/.test(t)) {
      const bytes = Number(t.slice(5));
      out.push(`0x${word.slice(0, bytes * 2)}`);
    } else {
      out.push(`0x${word}`); // tuple head / dynamic pointer / unsupported
    }
  }
  return out;
}

// ════════════════════════════════════════════════════════════════════════
//  Retry, fetch, json shims
// ════════════════════════════════════════════════════════════════════════

async function withRetry({fn, maxAttempts = 10, baseMs = 1000, capMs = 60_000}) {
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
      await sleep(wait);
    }
  }
  throw lastErr;
}

function transientError({message}) {
  const e = new Error(message);
  e.transient = true;
  return e;
}

function nonTransientError({message}) {
  const e = new Error(message);
  e.transient = false;
  return e;
}

async function fetchWithTimeout({url, timeoutMs = 30_000}) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(t);
  }
}

async function parseJsonOrThrow({res}) {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    throw transientError({message: `non-JSON response: ${text.slice(0, 200)}`});
  }
}

function readJson({path: p}) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

/**
 * Stringify with TAB indent to match Sphinx's v5 artifact layout exactly.
 * Trailing newline included.
 */
function jsonStringifyTabs({value}) {
  return JSON.stringify(value, null, '\t') + '\n';
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

function die(msg) {
  console.error(`ERROR: ${msg}`);
  process.exit(2);
}
