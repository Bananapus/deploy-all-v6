#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const NETWORKS = {
  mainnets: [
    { name: 'ethereum', chainId: 1, folder: 'ethereum', uniswap: true },
    { name: 'optimism', chainId: 10, folder: 'optimism', uniswap: true },
    { name: 'base', chainId: 8453, folder: 'base', uniswap: true },
    { name: 'arbitrum', chainId: 42161, folder: 'arbitrum', uniswap: true },
  ],
  testnets: [
    { name: 'ethereum_sepolia', chainId: 11155111, folder: 'sepolia', uniswap: true },
    { name: 'optimism_sepolia', chainId: 11155420, folder: 'optimism_sepolia', uniswap: false },
    { name: 'base_sepolia', chainId: 84532, folder: 'base_sepolia', uniswap: true },
    { name: 'arbitrum_sepolia', chainId: 421614, folder: 'arbitrum_sepolia', uniswap: true },
  ],
};

const REQUIRED_DEPLOYMENTS = [
  'ERC2771Forwarder',
  'JBAddressRegistry',
  'JBBuybackHookRegistry',
  'JBDirectory',
  'JBFeelessAddresses',
  'JBMultiTerminal',
  'JBPermissions',
  'JBPrices',
  'JBProjects',
  'JBRouterTerminalRegistry',
  'JBSplits',
  'JBSuckerRegistry',
  'JBTokens',
];

const REQUIRED_UNISWAP_DEPLOYMENTS = ['JBBuybackHook', 'JBRouterTerminal'];

const REQUIRED_UNISWAP_ARTIFACTS = [
  'JBBuybackHook',
  'JBRouterTerminal',
  'JBUniswapV4Hook',
  'JBUniswapV4LPSplitHook',
  'JBUniswapV4LPSplitHookDeployer',
];

const REQUIRED_ARTIFACT_PACKAGES = {
  JBBuybackHook: '@bananapus/buyback-hook-v6',
  JBRouterTerminal: '@bananapus/router-terminal-v6',
  JBUniswapV4Hook: '@bananapus/univ4-router-v6',
  JBUniswapV4LPSplitHook: '@bananapus/univ4-lp-split-hook-v6',
  JBUniswapV4LPSplitHookDeployer: '@bananapus/univ4-lp-split-hook-v6',
};

const root = process.cwd();
const scope = process.argv[2] ?? 'testnets';
const networks = NETWORKS[scope];
const errors = [];
const artifactManifest = readJson(path.join(root, 'artifacts', 'artifacts.manifest.json'));

if (!networks) {
  console.error(`Usage: node script/preflight-twap-oracle-upgrade.mjs <${Object.keys(NETWORKS).join('|')}>`);
  process.exit(2);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    errors.push(`${file}: ${err.message}`);
    return undefined;
  }
}

function expectDeployment(chain, name) {
  const file = path.join(root, 'deployments', chain.folder, `${name}.json`);
  if (!fs.existsSync(file)) {
    errors.push(`${chain.name}: missing deployments/${chain.folder}/${name}.json`);
    return;
  }

  const json = readJson(file);
  if (!json) return;

  if (!/^0x[0-9a-fA-F]{40}$/.test(json.address ?? '')) {
    errors.push(`${chain.name}: deployments/${chain.folder}/${name}.json has invalid address`);
  }

  const expectedChainId = `0x${chain.chainId.toString(16)}`;
  if ((json.chainId ?? '').toLowerCase() !== expectedChainId) {
    errors.push(
      `${chain.name}: deployments/${chain.folder}/${name}.json chainId ${json.chainId} != ${expectedChainId}`,
    );
  }
}

function expectArtifact(name) {
  const file = path.join(root, 'artifacts', `${name}.json`);
  if (!fs.existsSync(file)) {
    errors.push(`missing artifacts/${name}.json; run npm run artifacts`);
    return;
  }

  const json = readJson(file);
  const bytecode = json?.bytecode?.object;
  if (typeof bytecode !== 'string' || !bytecode.startsWith('0x') || bytecode.length <= 2) {
    errors.push(`artifacts/${name}.json has no bytecode.object`);
  }

  const expectedPackage = REQUIRED_ARTIFACT_PACKAGES[name];
  const entry = artifactManifest?.contracts?.[name];
  if (!expectedPackage || !entry) {
    errors.push(`artifacts manifest missing ${name}; run npm run artifacts`);
    return;
  }

  const packageJson = readJson(path.join(root, 'node_modules', expectedPackage, 'package.json'));
  if (!packageJson?.version) return;

  if (entry.sourcePackage !== expectedPackage) {
    errors.push(`artifacts manifest ${name}.sourcePackage ${entry.sourcePackage} != ${expectedPackage}`);
  }

  if (entry.sourceVersion !== packageJson.version) {
    errors.push(
      `artifacts manifest ${name}.sourceVersion ${entry.sourceVersion} != installed ${expectedPackage}@${packageJson.version}; run npm run artifacts`,
    );
  }
}

console.log(`TWAP oracle upgrade preflight: ${scope}`);

if (artifactManifest?.gitDirty || artifactManifest?.rehearsal) {
  errors.push('artifacts manifest is dirty/rehearsal; run npm run artifacts from a clean tree');
}

for (const chain of networks) {
  for (const name of REQUIRED_DEPLOYMENTS) expectDeployment(chain, name);
  if (chain.uniswap) {
    for (const name of REQUIRED_UNISWAP_DEPLOYMENTS) expectDeployment(chain, name);
  }

  console.log(`  checked deployments/${chain.folder} for ${chain.name}`);
}

if (networks.some((chain) => chain.uniswap)) {
  for (const name of REQUIRED_UNISWAP_ARTIFACTS) expectArtifact(name);
  console.log('  checked TWAP upgrade artifacts');
}

if (errors.length !== 0) {
  console.error('\nPreflight failed:');
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log('Preflight passed.');
