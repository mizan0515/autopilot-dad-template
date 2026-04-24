# profile-stub/

Minimal per-project profile scaffold for the DAD relay.

Copy this folder into your relay clone as `<relay-root>/profiles/<your-slug>/`,
then replace `myproject` with your project's slug across the files. The relay's
profile generators and status scripts will pick up the new profile on next run.

## Files

- `profile.json` — project slug, display name, directive, MCP pass-through toggle, bucket list
- `agent-identities.json` — Layer 1 identities (orchestrator + workers). **Relay repo owns this file** (see `relay/README.md` Layer 1 note).
- `broker.myproject.json` — per-project broker budget (token ceiling, turn limit, timeouts). Rename to `broker.<your-slug>.json`.
- `policy-registry.json` — project-scoped Layer 3 policies (no main push, UTF-8 BOM contract, etc.).
- `tool-registry.json` — Layer 2 tool classes. `mcp-call` has `passthrough: true` by default.
- `anomaly-rules.json` — Layer 4 detection rules (checkpoint stall, token ceiling, cache ratio).
- `skill-contracts.json` — skill → tool-class / bucket / execution-mode requirements.

## What goes where after copying

1. `profiles/<your-slug>/` = this folder with renamed files + replaced slug.
2. Your project's `.autopilot/config.json` gets `relay_repo_path` pointing at the relay clone.
3. Skill files in your project (`.agents/skills/<your-slug>-*`) are registered with the relay via `relay skill register` (run from the relay repo root).

## Slug convention

The slug must:
- Be lowercase `[a-z0-9-]` only (no spaces, no underscores).
- Match the `SKILL_PREFIX` that `apply.ps1`/`apply.sh` derived during template install.
- Match the prefix on your project's `.agents/skills/<slug>-*` folders.

Mismatched slugs cause governance-status scripts to fail-closed.
