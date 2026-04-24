---
name: cardgame-dialogue-start
description: "CardGame repository-only explicit skill for starting a DAD v2 dialogue session with Claude Code. Invoke it directly as $cardgame-dialogue-start. Use it when medium or large work benefits from external review. Do not use it for small work that a single agent can finish. Triggers: \"start dialogue session\", \"dialogue start\", \"collaborate with Claude Code\"."
---

# Dialogue Start (Codex takes Turn 1)

A DAD v2 session where Codex (this agent) performs Turn 1 and produces the Claude Code handoff prompt.

## Invocation

- This is an **explicit-call skill**, not auto-suggested.
- Example: `Use $cardgame-dialogue-start to open a DAD v2 session.`

## Premise

- The agent executing this skill is in the **Codex** role.
- Contract file is `AGENTS.md` (Claude Code uses `CLAUDE.md`).
- When producing the peer prompt for Claude Code, start with: `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`

## Procedure

1. Read `PROJECT-RULES.md` first, then `AGENTS.md` and `DIALOGUE-PROTOCOL.md` to internalize the v2 protocol. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Analyze current project state:
   - `git log --oneline -10` (recent work)
   - `git status` (current changes)
   - project `*-research.md` files, if the project uses them
3. Determine scope (small / medium / large).
4. **Perform Turn 1**:
   a. large scope → write `task_model` (goals / non-goals / risks / success shape)
   b. Draft Sprint Contract (for medium/large):
      - concrete checkpoint list (with verification methods)
      - link `reference_prompts`
   c. Plan + execution
   d. Self-iteration loop: verify against Contract checkpoints, repeat until satisfied
   e. Save Turn Packet to `Document/dialogue/sessions/{session-id}/turn-01.yaml`
   f. Save the exact Claude Code handoff prompt body to `Document/dialogue/sessions/{session-id}/turn-01-handoff.md` and record that path in `handoff.prompt_artifact`. Only set `handoff.ready_for_peer_verification: true` after `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are finalized.
5. Initialize/update `Document/dialogue/state.json`:
   - `protocol_version: "dad-v2"`
   - `relay_mode: "user-bridged"`
   - `last_agent: "codex"` (Turn 1 initiator)
6. Emit the Claude Code prompt to the user (prompt body only, no CLI wrapper). Must include all 7 elements:
   - `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - `Session: Document/dialogue/state.json`
   - `Previous turn: Document/dialogue/sessions/{session-id}/turn-01.yaml`
   - concrete task instructions (`handoff.next_task + handoff.context`)
   - ~10-line relay-friendly summary
   - the mandatory footer below
   - the same body saved to `Document/dialogue/sessions/{session-id}/turn-01-handoff.md`

   Mandatory footer (append verbatim):

```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```

## Branch discipline

- No direct push to main. If the current branch is main at session start, create a working branch.
- Convergence commits also go on the working branch → push → PR → merge to main.

## Session modes

- **Autonomous**: escalate only. Everything else auto.
- **Supervised**: every convergence requires user confirmation.
- **Hybrid** (default): confirm only on large scope or low-confidence convergence.
