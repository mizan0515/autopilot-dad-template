---
description: Start a Dual-Agent Dialogue v2 session with Claude Code (Codex takes Turn 1)
argument-hint: "[task description]"
---

# /dialogue-start-as-codex

Start a DAD v2 session where Codex (this chat) takes Turn 1 and produces the Claude Code handoff prompt.

## Arguments

- `$ARGUMENTS` = one-line task description. If empty, analyze project state and auto-propose.

## Premise

- The agent running this command is the **Codex** role.
- Contract file is `AGENTS.md` (Claude Code uses `CLAUDE.md`).
- When producing the peer prompt for Claude Code, start with: `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`

## Procedure

1. Read `PROJECT-RULES.md` first, then `AGENTS.md` and `DIALOGUE-PROTOCOL.md` to internalize the v2 protocol. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Analyze current project state:
   - `git log --oneline -10` (recent work)
   - `git status` (current changes)
   - runtime / test console errors (if the project surfaces them)
   - project `*-research.md` files, if the project uses them
3. Determine scope (small / medium / large).
4. **Perform Turn 1**:
   a. large scope → write `task_model` (goals / non-goals / risks / success shape)
   b. Draft Sprint Contract (for medium/large):
      - concrete checkpoint list (with verification methods)
      - link `reference_prompts`
   c. Plan + execution
   d. Self-iteration loop: verify against checkpoints, repeat until satisfied
   e. Save Turn Packet to `Document/dialogue/sessions/{session-id}/turn-01.yaml`
   f. Save the exact Claude Code handoff prompt to `Document/dialogue/sessions/{session-id}/turn-01-handoff.md` and record that path in `handoff.prompt_artifact`. Only set `handoff.ready_for_peer_verification: true` after `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are finalized.
5. Initialize/update `Document/dialogue/state.json`:
   - `protocol_version: "dad-v2"`
   - `relay_mode: "user-bridged"`
   - `last_agent: "codex"` (Turn 1 initiator)
6. Emit the Claude Code prompt to the user (prompt body only, no CLI wrapper). Must contain all 7 elements:
   - `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - `Session: Document/dialogue/state.json`
   - `Previous turn: Document/dialogue/sessions/{session-id}/turn-01.yaml`
   - concrete task instructions (`handoff.next_task + handoff.context`)
   - ~10-line relay-friendly summary
   - the mandatory footer block below
   - the same body saved to `Document/dialogue/sessions/{session-id}/turn-01-handoff.md`

   Mandatory footer (append verbatim at end of prompt):
```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```

## User mode selection

- **Autonomous**: escalate only. Everything else auto.
- **Supervised**: every convergence requires user confirmation.
- **Hybrid** (default): confirm only on large scope or low-confidence convergence.

## Invocation examples

```
/dialogue-start-as-codex fix card reward screen bug
/dialogue-start-as-codex audit map system code
/dialogue-start-as-codex
```
