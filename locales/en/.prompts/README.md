# .prompts/ — Dual-Agent Dialogue v2 prompts

## Overview

This folder holds the prompt pack for the **symmetric-turn collaboration (DAD v2)** system
between Codex and Claude Code. All prompts are **agent-neutral** — the same file can be
read and executed by either side.

The template ships a minimal **infrastructure** prompt set. Operators add project-specific
domain prompts (audit checklists, bug-fix playbooks, QA procedures, etc.) as needed.

### System files (repo root)
- `DIALOGUE-PROTOCOL.md` — v2 symmetric-turn protocol thin-root contract. Detailed schema /
  convergence / validator rules live under `Document/DAD/` (see `PACKET-SCHEMA.md`,
  `STATE-AND-LIFECYCLE.md`, `VALIDATION-AND-PROMPTS.md`).
- `AGENTS.md` — Codex contract
- `CLAUDE.md` — Claude Code contract
- `PROJECT-RULES.md` — shared project rules

---

## Shipped prompts

| No. | File | Purpose | Category |
|-----|------|---------|----------|
| 12  | `12-context-summarization-policy.md` | Keep `handoff.context` under CarryForwardMaxBytes without losing load-bearing facts | System |

Operators are expected to add domain-specific prompts (audits, bug-fix playbooks, data
validation, QA procedures) numbered 00–11 as the project grows.

## Naming convention

- Two-digit prefix: `NN-topic.md`
- Topic: kebab-case, descriptive.
- Front-matter required fields: `id`, `audience`, `intent`, `invoke`.

## Referencing from system docs

`DIALOGUE-PROTOCOL.md`, `CLAUDE.md`, and `AGENTS.md` may point at specific `.prompts/` files
when a well-defined procedure exists. If a reference is added, the file must exist in the
shipped set — broken pointers are a system-doc drift bug.
