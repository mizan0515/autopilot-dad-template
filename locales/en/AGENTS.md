# Codex Agent Contract — {{PROJECT_NAME}}

**IMPORTANT: Read `PROJECT-RULES.md` first.** It contains the shared project rules that all agents must follow.

This file is auto-loaded by Codex and is the **root map**. When your task is scoped to a subfolder, prefer that subfolder's `AGENTS.md` first so Codex does not drag unrelated project rules into context.

Related files:
- `PROJECT-RULES.md` — shared rules and document/update constraints
- `RTK.md` — shell-output compression policy (optional, user-machine install)
- `DIALOGUE-PROTOCOL.md` — Dual-Agent Dialogue protocol
- `CLAUDE.md` — Claude-specific contract

## Role

Codex is a peer engineer, not a unilateral orchestrator.

Codex may:
- implement code, fixes, refactors, tests, and docs
- evaluate Claude Code output and propose work
- escalate to the user when a real blocker or decision is needed

Codex must not:
- push directly to `main` / `master`
- rewrite shared system rules without approval
- assume docs are accurate without checking live files

## RTK

For shell commands, follow `RTK.md` if RTK is installed on the operator's machine.

Default:
- use `rtk <command>` for noisy read-only external CLI commands
- use raw output or `rtk proxy <command>` when exact output matters

Never treat RTK as applying to:
- MCP tools
- file edit tools
- web tools

If RTK is not available on this machine, ignore this section and run commands directly.

## Standalone Mode

Default mode when the user works with Codex directly.

Rules:
- follow `PROJECT-RULES.md`
- verify current file state before acting
- prefer vertical slices: code + data + validation together
- if the project uses per-folder research files, update the relevant `*-research.md` in the same task when scripts change
- if a task exposes system-doc drift, sync the affected system docs in the same task or name that sync as the first follow-up

Git:
- commit and push meaningful changes
- if on `main`, create a work branch first
- do not push directly to `main`

## Dialogue Mode

When collaborating through the Dual-Agent Dialogue flow, follow `DIALOGUE-PROTOCOL.md`.

Do not copy the full protocol into prompts from memory; read the file and use the live session state.

## Cost control

Use the smallest context that can finish the task:
- open the nearest scoped `AGENTS.md` when present
- prefer `rg --files` / narrow `rg -n` before opening large files
- read `*-research.md` (if the project uses them) before bulk-reading script folders
- run the narrowest test or verification path that can verify the change

If a task is clearly local to one folder, do not re-open unrelated large docs unless the change actually crosses those boundaries.

## Search roots

Keep searches scoped to source directories declared in `.autopilot/config.json` → `search_roots`. Default roots for most projects:
- source tree root (e.g. `src/`, `Assets/Scripts/`, `lib/`)
- test tree root (e.g. `tests/`, `Assets/Tests/`)
- `Document/` or `docs/`
- `.autopilot/`, `.agents/`, `.prompts/`, `tools/`

Do NOT wildcard-search: `Library/`, `Temp/`, `Logs/`, `UserSettings/`, `node_modules/`, `target/`, `build/`, `dist/`, or unbounded `Packages/`. These produce token storms without value.
