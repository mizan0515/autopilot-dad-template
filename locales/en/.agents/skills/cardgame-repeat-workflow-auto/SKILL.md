---
name: cardgame-repeat-workflow-auto
description: "CardGame repository-only explicit skill for continuing an active DAD v2 session in autonomous mode. Invoke it directly as $cardgame-repeat-workflow-auto. It automates decisions and surfaces only ESCALATEs to the user. Triggers: \"auto repeat\", \"autonomous mode\". Note: user relay is still required."
---

# Repeat Workflow Auto (autonomous mode)

**Autonomous variant** of `$cardgame-repeat-workflow`. Decides autonomously in ambiguous situations instead of asking the user.

## Invocation

- **Explicit-call skill**, not auto-suggested.
- Example: `Use $cardgame-repeat-workflow-auto to continue the current DAD v2 session in auto mode.`
- If no session exists yet, call `$cardgame-dialogue-start` first.

Note: DAD v2 is a **user-bridged protocol**. What is automated is judgment and convergence rules, not the user relay step itself.

## Differences from $cardgame-repeat-workflow (4 overrides)

1. **Minimize user confirmation** — auto-decide except ESCALATE
2. **Autonomous task selection** — pick the highest-value work based on analysis
3. **Auto-commit on PASS** — all checkpoints green → commit on working branch + push + open PR (no direct push to main)
4. **ESCALATE on stall** — 2 turns of quality stall or 3 consecutive same-checkpoint FAILs → user ESCALATE

## Procedure

1. Read `PROJECT-RULES.md` first, then `AGENTS.md` and `DIALOGUE-PROTOCOL.md`. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Check `Document/dialogue/state.json` for an existing session (if absent, call `$cardgame-dialogue-start` first).
3. Auto-analyze project state (git log, tests, console).
4. Run autonomously:
   - Auto-draft Contract → execute work → self-iterate → emit peer prompt → user relay → judge convergence for next turn
   - Save the exact peer prompt body to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md` and record that path in `handoff.prompt_artifact`. Keep `handoff.ready_for_peer_verification` false until `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are finalized.
5. The peer prompt must include all 7 elements:
   - `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - `Session: Document/dialogue/state.json`
   - `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
   - concrete task instructions (`handoff.next_task + handoff.context`)
   - ~10-line relay-friendly summary
   - the mandatory footer below
   - the same body saved to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`
6. Append this footer verbatim at the end of the prompt:
```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```
7. On finish, record the session summary under `Document/dialogue/sessions/`.

## Safety rails

1. Hard turn limit per scope; over-limit → user ESCALATE
2. 3 consecutive FAILs on same checkpoint → auto ESCALATE
3. Compile errors that can't be resolved → user ESCALATE
4. No direct push to main
5. 2 turns of quality stall → user ESCALATE
