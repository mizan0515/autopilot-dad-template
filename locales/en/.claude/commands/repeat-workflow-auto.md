---
description: Dual-Agent Dialogue v2 autonomous iteration (minimal user confirmation)
argument-hint: "[turn count, default 5]"
---

# /repeat-workflow-auto

**Autonomous variant** of `/repeat-workflow`. Decides autonomously in ambiguous situations
instead of asking the user. Only ESCALATEs surface to the user.

Note: DAD v2 is a **user-bridged protocol**. This command does not hide the act of
invoking the peer agent. What is automated is judgment and convergence rules, not the
user relay step itself.

If you want supervision, use `/repeat-workflow N`.

## Arguments
- `$ARGUMENTS` = number of turns (1–10). Defaults to 5.

## Differences from /repeat-workflow (4 overrides)

1. **Minimize user confirmation** — auto-decide except ESCALATE
2. **Autonomous task selection** — pick the highest-value work based on analysis
3. **Auto-converge on PASS** — all checkpoints green → commit on working branch + push + open PR
4. **ESCALATE on stall** — 2 turns of quality stall or 3 consecutive same-checkpoint FAILs → user ESCALATE

## Procedure

1. Read `PROJECT-RULES.md` first, then `CLAUDE.md` and `DIALOGUE-PROTOCOL.md`. If the root protocol points to `Document/DAD/` references, read the needed files there too.
2. Check `Document/dialogue/state.json` for an existing session (if absent, use `/dialogue-start` to open one).
3. Analyze current project state automatically (git log, tests, console).
4. Run `$ARGUMENTS` turns (or 5) autonomously:
   - Auto-draft Contract → execute work → self-iterate → emit peer prompt (with mandatory footer) → user relay → judge convergence
   - Save Turn Packet to `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
   - Save the exact peer prompt body to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md` and record that path in `handoff.prompt_artifact`. Keep `handoff.ready_for_peer_verification` false until `handoff.next_task`, `handoff.context`, and `handoff.prompt_artifact` are finalized.
   - The peer prompt must include all 7 elements:
     - `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
     - `Session: Document/dialogue/state.json`
     - `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
     - concrete task instructions (`handoff.next_task + handoff.context`)
     - ~10-line relay-friendly summary
     - the mandatory footer block below
     - the same body saved to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`
   - Append this footer verbatim at the end of the peer prompt:
```
---
If you find gaps or improvements, fix them directly and report a diff.
If nothing needs changing, state "No change required, PASS".
IMPORTANT: Do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```
5. On finish, record the session summary under `Document/dialogue/sessions/`.

## Safety rails

1. Hard turn limit per scope; over-limit → user ESCALATE
2. 3 consecutive FAILs on same checkpoint → auto ESCALATE
3. Compile errors that can't be resolved → user ESCALATE
4. No direct push to main
5. 2 turns of quality stall → user ESCALATE
