---
description: Start a Dual-Agent Dialogue v2 session with Codex (symmetric turns)
argument-hint: "[task description]"
---

# /dialogue-start

Start a symmetric-turn Dialogue session between Codex and Claude Code.

## Arguments

- `$ARGUMENTS` = one-line task description. If empty, analyze project state and auto-propose.

## Procedure

1. Read `PROJECT-RULES.md` first, then `CLAUDE.md` and `DIALOGUE-PROTOCOL.md` to internalize the v2 protocol. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Analyze current project state:
   - `git log --oneline -10` (recent work history)
   - `git status` (current changes)
   - runtime / test console errors (if the project surfaces them)
   - project `*-research.md` files (test baseline), if the project uses them
3. Determine scope (small / medium / large).
4. **Perform Turn 1**:
   a. Draft Sprint Contract (for medium/large):
      - concrete checkpoint list (with verification methods)
      - link `reference_prompts`
   b. Plan + partial execution
   c. Self-iteration loop: verify against checkpoints, repeat until satisfied
   d. Save Turn Packet to `Document/dialogue/sessions/{session-id}/turn-01.yaml`
   e. Save the exact Codex handoff prompt to `Document/dialogue/sessions/{session-id}/turn-01-handoff.md` and record that path in `handoff.prompt_artifact`. Only set `handoff.ready_for_peer_verification: true` after `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are all finalized.
5. Initialize/update `Document/dialogue/state.json`.
6. Emit the Codex prompt to the user (prompt body only, no CLI wrapper). The prompt MUST include all 7 elements:
   - `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - `Session: Document/dialogue/state.json`
   - `Previous turn: Document/dialogue/sessions/{session-id}/turn-01.yaml`
   - concrete task instructions (`handoff.next_task + handoff.context`)
   - ~10-line relay-friendly summary
   - the mandatory footer block below
   - the same body that was saved to `Document/dialogue/sessions/{session-id}/turn-01-handoff.md`

   Mandatory footer (append verbatim at end of prompt):
```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```

## User mode selection

Session modes:
- **Autonomous**: escalate only. Everything else auto.
- **Supervised**: every convergence requires user confirmation.
- **Hybrid** (default): confirm only on large scope or low-confidence convergence.

## Invocation examples

```
/dialogue-start fix card reward screen bug
/dialogue-start audit map system code
/dialogue-start
```
