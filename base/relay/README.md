# relay/ — Dual-Agent Dialogue execution broker (optional)

## What is the relay?

The relay is a separate repository that brokers turns between Codex and Claude Code
as equal peers. It handles:

- Agent identity management (Layer 1)
- Tool governance and policy enforcement (Layers 2–3)
- Anomaly detection and posture reporting (Layers 4–5)
- Carry-forward context truncation (CarryForwardMaxBytes)
- Session artifacts, governance status, ops dashboard

This template ships only the **integration stubs** needed for this project to talk
to a relay. The relay itself is a separate repo.

## Layer 1 ownership

Per the 5-layer agent security model, **the relay repo is the authoritative owner
of agent identities, tool-policy allowlists, and dialogue-checkpoint contracts.**

This project repo does NOT own:
- `.agents/identities/`
- `agent-identities.json`
- `tool-policy.json`
- `policy-registry.json`

Those live in the relay repo. If the relay is not installed on this machine,
the project still runs under its own Layer 3 policy (`PROJECT-RULES.md`,
`CLAUDE.md`, `AGENTS.md`) and Layer 4 anomaly signals (project test suite).

## Setup

See [SETUP.md](SETUP.md) for step-by-step install + profile generation.

## When to install the relay

- You want MCP pass-through between Codex and Claude Code (e.g., Codex sees Unity
  MCP reflections Claude Code emits).
- You want centralized token-ceiling / cost-budget enforcement.
- You want the ops dashboard that renders governance + anomaly status across
  multiple projects.

If none of those matter yet, you can skip relay and use the user-bridged relay
mode (user copy-pastes between Codex and Claude Code). The DAD protocol
supports both modes.

## Config pointer

`.autopilot/config.json` has a `relay_repo_path` field. Set it to the absolute
path of your installed relay clone. If empty, the project assumes no relay.
