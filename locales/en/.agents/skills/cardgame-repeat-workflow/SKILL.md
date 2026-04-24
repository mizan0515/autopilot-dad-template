---
name: cardgame-repeat-workflow
description: "CardGame repository-only explicit skill for continuing an active DAD v2 dialogue session. Invoke it directly as $cardgame-repeat-workflow. It executes the next turn of the current session. Triggers: \"next turn\", \"repeat workflow\", \"continue the session\". Do not use it when no session exists."
---

# Repeat Workflow (symmetric-turn iteration)

Perform the next turn of an active DAD v2 session.

## Invocation

- **Explicit-call skill**, not auto-suggested.
- Example: `Use $cardgame-repeat-workflow to run the next turn of the current DAD v2 session.`
- If no session exists yet, call `$cardgame-dialogue-start` first.

## Procedure

1. Read `PROJECT-RULES.md` first, then `AGENTS.md` and `DIALOGUE-PROTOCOL.md`. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Check `Document/dialogue/state.json` for an existing session (if absent, direct the user to `$cardgame-dialogue-start`).
3. Read the previous Turn Packet at `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`.
4. Perform the current turn:
   a. **Peer feedback**: PASS/FAIL against Contract checkpoints, with evidence
   b. **Own plan + execution**: run self-iteration loop
   c. **Save Turn Packet**: `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
   d. **Save peer prompt artifact**: write the exact peer prompt body to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md` and record that path in `handoff.prompt_artifact`. Keep `handoff.ready_for_peer_verification` false until `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are finalized.
   e. **Emit peer prompt**: print prompt body to the user (no CLI wrapper):
      - `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
      - `Session: Document/dialogue/state.json`
      - `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
      - concrete task instructions (`handoff.next_task + handoff.context`)
      - ~10-line relay-friendly summary
      - the mandatory footer block below
      - the same body saved to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`
   f. **Convergence check**: all checkpoints PASS + both sides done → commit on working branch + push + open PR (no direct push to main)

   Mandatory footer (append verbatim at end of prompt):
```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```

5. On convergence, record a session summary under `Document/dialogue/sessions/`.

## Safety rails

1. Hard turn limit per scope; over-limit → user ESCALATE
2. 2 turns of quality stall → user ESCALATE
3. 3 consecutive FAILs on the same checkpoint → auto ESCALATE
4. Compile errors → resolve first, then continue
5. No direct push to main
