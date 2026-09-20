#!/usr/bin/env node

import { copyFile, lstat, mkdir, readdir, realpath } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const skillName = 'windows-save-token-jev-setup';
const sourceRoot = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const codexHome = path.resolve(
  process.env.CODEX_HOME?.trim() || path.join(os.homedir(), '.codex'),
);
const targetRoot = path.join(codexHome, 'skills', skillName);

const nodeMajor = Number.parseInt(process.versions.node.split('.')[0], 10);
if (nodeMajor < 20) {
  console.error(`Node.js 20 or newer is required; found ${process.version}.`);
  process.exit(1);
}

const managedPaths = [
  'README.md',
  'SKILL.md',
  'agents/openai.yaml',
  'references/trust-and-e2e.md',
  'scripts/Install-SaveTokenJev.ps1',
  'scripts/Set-OpenRouterKey.ps1',
  'scripts/Test-SaveTokenJev.ps1',
  'scripts/install-skill.mjs',
  'scripts/verify-stale-sidecar.mjs',
];

function isSameOrNested(first, second) {
  const relative = path.relative(second, first);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

async function existingRealPath(candidate) {
  try {
    return await realpath(candidate);
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

async function assertNotSymlink(candidate) {
  try {
    const stats = await lstat(candidate);
    if (stats.isSymbolicLink()) {
      throw new Error(`Refusing to write through symbolic link: ${candidate}`);
    }
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
}

async function copyManagedFile(relativePath) {
  const source = path.join(sourceRoot, relativePath);
  const destination = path.join(targetRoot, relativePath);
  const sourceStats = await lstat(source);

  if (!sourceStats.isFile() || sourceStats.isSymbolicLink()) {
    throw new Error(`Managed source is not a regular file: ${source}`);
  }

  await assertNotSymlink(destination);
  await assertNotSymlink(path.dirname(destination));
  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(source, destination);
}

async function main() {
  const sourceReal = await realpath(sourceRoot);
  const targetReal = await existingRealPath(targetRoot);
  const targetForComparison = targetReal ?? targetRoot;

  if (
    isSameOrNested(targetForComparison, sourceReal) ||
    isSameOrNested(sourceReal, targetForComparison)
  ) {
    throw new Error(
      `Source and target overlap; refusing recursive or in-place installation. Source: ${sourceReal}; target: ${targetForComparison}`,
    );
  }

  await assertNotSymlink(codexHome);
  await assertNotSymlink(path.join(codexHome, 'skills'));
  await assertNotSymlink(targetRoot);
  await mkdir(targetRoot, { recursive: true });

  for (const relativePath of managedPaths) {
    await copyManagedFile(relativePath);
  }

  const installedTopLevel = await readdir(targetRoot);
  if (!installedTopLevel.includes('SKILL.md')) {
    throw new Error(`Installation did not produce ${path.join(targetRoot, 'SKILL.md')}`);
  }

  console.log(`Installed or updated Codex Skill: ${targetRoot}`);
  console.log('Restart Codex completely, then invoke $windows-save-token-jev-setup.');
  console.log('No Hooks, environment variables, API keys, or /compact actions were changed.');
}

main().catch((error) => {
  console.error(`Skill installation failed: ${error.message}`);
  process.exitCode = 1;
});
