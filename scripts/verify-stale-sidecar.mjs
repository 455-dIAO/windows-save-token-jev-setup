import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const pluginRoot = process.argv[2];
if (!pluginRoot) throw new Error('Usage: node verify-stale-sidecar.mjs <plugin-root>');

const modulePath = resolve(pluginRoot, 'dist', 'integrations', 'codex.js');
const { codexDataPath, handleCodexHook } = await import(pathToFileURL(modulePath).href);
const dataDir = await mkdtemp(join(tmpdir(), 'save-token-jev-regression-'));
const sessionId = 'stale-sidecar-regression';
const env = {
  ...process.env,
  SAVE_TOKEN_JEV_DATA_DIR: dataDir,
  SAVE_TOKEN_JEV_DASHBOARD: 'off',
};

try {
  const sidecarPath = codexDataPath(sessionId, env);
  await mkdir(dirname(sidecarPath), { recursive: true });
  await writeFile(sidecarPath, JSON.stringify({
    version: 1,
    createdAt: new Date(0).toISOString(),
    context: 'STALE-CONTENT-MUST-NOT-RETURN',
    stats: {},
    decisions: [],
  }));

  const pre = await handleCodexHook({
    session_id: sessionId,
    hook_event_name: 'PreCompact',
    transcript_path: null,
    trigger: 'manual',
  }, env);

  let sidecarStillExists = true;
  try {
    await readFile(sidecarPath, 'utf8');
  } catch (error) {
    if (error && error.code === 'ENOENT') sidecarStillExists = false;
    else throw error;
  }

  const start = await handleCodexHook({
    session_id: sessionId,
    hook_event_name: 'SessionStart',
    source: 'compact',
  }, env);
  const restored = Boolean(start?.hookSpecificOutput?.additionalContext);

  if (sidecarStillExists || restored) {
    throw new Error('Regression failed: stale sidecar content could be restored.');
  }

  process.stdout.write(JSON.stringify({
    passed: true,
    staleSidecarRemoved: true,
    staleContextRestored: false,
    preCompactContinued: pre?.continue === true,
  }));
} finally {
  await rm(dataDir, { recursive: true, force: true });
}
