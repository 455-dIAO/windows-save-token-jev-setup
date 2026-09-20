---
name: windows-save-token-jev-setup
description: Install, merge, configure, and verify user-level save-token-jev Hooks for Codex on Windows. Use when a user wants Jev-guided PreCompact filtering and SessionStart restoration across projects sharing one Codex user configuration.
---

# Windows save-token-jev setup

Configure [`IAmUnbounded/save-token-jev-clean`](https://github.com/IAmUnbounded/save-token-jev-clean) without exposing credentials or replacing unrelated Codex settings.

## Safety boundaries

- Explain that `PreCompact` sends selected transcript/tool-call material to the configured Jev/OpenRouter endpoint. Obtain explicit consent before installation or a live test.
- Never ask the user to paste an API key into chat, a command argument, a project file, `hooks.json`, `AGENTS.md`, source code, or a backup.
- Never create Hook trust records or use a trust-bypass flag. The user must review and trust each Hook interactively in `/hooks`.
- Do not trigger `/compact` automatically. The user must enter it manually.
- Preserve all unrelated Hooks, `AGENTS.md`, JevRouter files, and Codex settings.
- Keep “configuration completed”, “Hooks trusted”, “synthetic validation passed”, and “real Codex compaction verified” as separate claims.

## Workflow

1. Confirm the host is Windows and obtain consent for the transcript data transfer described above.
2. Resolve the effective Codex home from process-level `CODEX_HOME`, then user-level, then machine-level `CODEX_HOME`, otherwise `%USERPROFILE%\.codex`. Report a process/persisted-value mismatch and stop until the launching environment is clear.
3. Check the Windows user environment variable `OPENROUTER_API_KEY` by presence and length only. If absent, pause and ask the user to run `scripts/Set-OpenRouterKey.ps1` in their own interactive PowerShell. Do not receive the value yourself.
4. Request the filesystem/network permissions needed to download, build, back up, and update the user configuration.
5. Run `scripts/Install-SaveTokenJev.ps1`. It:
   - discovers the actual Desktop folder and existing installation;
   - backs up allowlisted configuration and plugin files without exporting environment-variable values;
   - clones, patches, tests, and builds the upstream repository in a temporary staging directory;
   - applies the stale-sidecar guard before deployment;
   - deploys without deleting unrelated target files;
   - idempotently merges `PreCompact(manual|auto)` and `SessionStart(compact)` into user `hooks.json`;
   - writes only Windows user environment variables;
   - runs `doctor` and a no-network stale-sidecar regression test.
6. Run `scripts/Test-SaveTokenJev.ps1` as an independent read-only configuration check.
7. Read [references/trust-and-e2e.md](references/trust-and-e2e.md) and guide the user through Hook review, full restart, and a clean manual `/compact` test.

## Required configuration

The scripts set these Windows user variables without printing their values:

- `TYPESAFE_API_KEY` equal to the existing `OPENROUTER_API_KEY`
- `JEV_BASE_URL=https://openrouter.ai/api/alpha/decisions`
- `JEV_MODEL=~typesafe/jev-latest`
- `SAVE_TOKEN_JEV_KEEP_THRESHOLD=0.5`
- `SAVE_TOKEN_JEV_PRESERVE_RECENT=6`
- `SAVE_TOKEN_JEV_MIN_REDUCTION=0.15`
- `SAVE_TOKEN_JEV_DASHBOARD_PORT=43127`

The merged Hook definitions must retain the repository template values: PreCompact timeout 120 seconds; SessionStart timeout 10 seconds and `additionalContextLimit` 200000. Commands must contain the quoted absolute `dist/cli.js` path and no `${PLUGIN_ROOT}` placeholder.

## Completion standard

Do not say “fully verified” until all of the following are evidenced:

- `/hooks` shows both events as Installed 1 / Active 1 and each detail page shows Trusted.
- A fresh Codex CLI task creates a new Jev history/sidecar record during user-entered `/compact`.
- Codex performs its built-in compaction.
- the subsequent model request contains `save-token-jev-context` with the current test marker and tool result.
- a different fresh task does not receive the previous task's marker.

If Jev preparation fails or reduction is below threshold, explicitly report that only Codex built-in compaction ran. If evidence is incomplete, say what remains unconfirmed.
