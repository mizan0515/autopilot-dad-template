---
description: Iterate Dual-Agent Dialogue v2 symmetric turns
argument-hint: "[turn count, default 5]"
---

# /repeat-workflow

Run a symmetric-turn Dialogue session under the DAD v2 protocol.

## Arguments

- `$ARGUMENTS` = number of turns (1–10). Defaults to 5.

## Procedure

1. Read `PROJECT-RULES.md` first, then `CLAUDE.md` and `DIALOGUE-PROTOCOL.md` to internalize the v2 protocol. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Check `Document/dialogue/state.json` for an existing session (if absent, use `/dialogue-start` to open one).
3. Analyze current project state.
4. For each turn:
   a. **Peer feedback**: PASS/FAIL against Contract checkpoints
   b. **Own plan + execution**: run self-iteration loop
   c. **Save Turn Packet**: `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
   d. **Save peer prompt artifact**: write the exact peer prompt body to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md` and record that path in `handoff.prompt_artifact`. Keep `handoff.ready_for_peer_verification` false until `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are finalized.
   e. **Emit peer prompt**: print prompt body to the user (no CLI wrapper).
      Must contain all 7 elements:
      - `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
      - `Session: Document/dialogue/state.json`
      - `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
      - concrete task instructions (`handoff.next_task + handoff.context`)
      - ~10-line relay-friendly summary
      - the mandatory footer block below
      - the same body saved to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`

      Mandatory footer:
```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```
   f. **User relays peer result**: feedback → next turn
   g. **Convergence check**: all checkpoints PASS + both sides done → commit on working branch + push + open PR
5. On finish, record the session summary under `Document/dialogue/sessions/`.

## Safety rails

1. Hard turn limit per scope; over-limit → user ESCALATE
2. 2 turns of quality stall → user ESCALATE
3. 3 consecutive FAILs on same checkpoint → auto ESCALATE
4. Compile errors → resolve first, then continue
5. No direct push to main

## User intervention points

- Before each turn: course-correct freely
- When relaying peer result: add feedback with `User note:` prefix
- On ESCALATE: user decides

## Invocation examples

```
/repeat-workflow 5
/repeat-workflow 3
/repeat-workflow
```
