# Dual-Agent Dialogue Protocol (DAD v2) — Root Contract

Codex and Claude Code collaborate in **symmetric turns**: each agent plans, executes, and evaluates every turn, converging on a Sprint Contract.

This file is a **thin root contract**. Detailed rules for schema, lifecycle, validator timing, and peer-prompt construction live in [`Document/DAD/`](Document/DAD/README.md) and those topic files are authoritative. If root and detail files disagree, trust the detail file and fix the root in the same task.

---

## Core principles

1. **Symmetric turns** — both sides plan, execute, and evaluate every turn. No fixed role.
2. **Sprint Contract** — both sides agree on "done criteria" before execution. Concrete checkpoints, not subjective scores.
3. **Self-iteration** — before handoff, self-verify against checkpoints and iterate until satisfied. In batch mode this is a bounded compile/test/fix loop; UX, feel, or broad-audit checkpoints that require outside eyes must be closed by peer review. Self-iteration is a **preparation phase**, not an exit verdict.
4. **Dynamic prompt generation** — a peer prompt is built at the end of every turn.
5. **User sovereignty** — the user can intervene, redirect, or stop at any time.
6. **Finite turns** — every session has a hard cap (2–10 turns based on scope).
7. **Live files first** — trust the current `Document/dialogue/` filesystem state over documentation. If v1 artifacts remain, migrate explicitly instead of appending.
8. **Strict schema** — Turn Packets and `state.json` must pass the validator. Freeform packets that "look similar" are rejected.
9. **System-doc sync** — when DAD infra, validator, slash commands, prompt templates, session schema, or agent contracts change (or drift is exposed), update affected system docs in the same task. If it can't close in the same turn, make it the first follow-up item.
10. **Separate operational input** — human approvals and direction decisions belong in `Document/dialogue/DECISIONS.md`, not mixed into `state.json` or turn packets.

v1 terms (`proposal`, `result`, `evaluation`, `review`) are forbidden in active rules.

---

## Flow summary

Turns are sequential. The user relays between agents; there is no concurrent execution.

- **Turn 1 (Agent A)** — state analysis → (large) task_model → draft Contract → execute → self-iterate → Packet + prompt → user
- **Turn 2 (Agent B)** — feedback (checkpoint-based) → review task_model → accept/modify Contract → execute → self-iterate → Packet + prompt → user
- **Turn 3+** — feedback → execute/new direction → self-iterate → converge (both PASS + `suggest_done: true`) or next prompt

| scope | checkpoints | max turns | Contract | task_model |
|-------|-------------|-----------|----------|------------|
| small | 0 (omit) | 2 | none — direct execute + review only | none |
| medium | 3–5 | 5 | in Turn 1 | optional |
| large | 6+ | 10 | in Turn 1 + user confirmation | required |

Full schema for the 3 packet types (Contract / Turn / Meta), `task_model`, field rules → [`Document/DAD/PACKET-SCHEMA.md`](Document/DAD/PACKET-SCHEMA.md).

`state.json` schema, session directory layout, convergence / auto-converge / Done Gate, session closure, v1 migration, pause/recover procedures → [`Document/DAD/STATE-AND-LIFECYCLE.md`](Document/DAD/STATE-AND-LIFECYCLE.md).

---

## Mandatory rules (every turn)

1. **Branch discipline** — no direct push to main. At session start, if on main create a work branch first. Convergence commits also happen on the work branch.
2. **Packet path** — new Turn Packets only to `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`. The `{N}` in the filename must match the inner `turn:` value. Legacy `Document/dialogue/packets/` is migration-input only.
3. **`my_work` required** — the own-work section uses key `my_work`. Aliases like `self_work` are forbidden.
4. **`suggest_done` location** — `suggest_done` and `done_reason` go inside `handoff` only. Root-level fields forbidden. `suggest_done: true` requires `done_reason`.
5. **Done Gate** — `suggest_done: true` requires: the peer has PASS'd every checkpoint on fresh evidence after your latest modification turn, plus `disconfirmation`, `evidence`, `open_risks`, validator pass. Details in STATE-AND-LIFECYCLE.md §3.
6. **Autonomous mode semantics** — autonomy means automated judgment, not "no user relay". Today the user is the turn relayer.
7. **Evidence-based verdicts** — PASS/FAIL uses commands, tests, console, screenshots, diffs, not impressions.

---

## Peer prompt rules (summary)

Every turn's peer prompt must contain the 7 elements below. Full rules and examples in [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md) §2.

1. Peer contract read instruction — **PROJECT-RULES.md first**, then the peer's contract file, then the root protocol. If the root protocol points to `Document/DAD/` references, tell the peer to read those too.
   - To Codex: `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - To Claude Code: `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
2. Session state reference: `Session: Document/dialogue/state.json`
3. Previous turn packet reference: `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
4. Concrete task instruction (`handoff.next_task + handoff.context`)
5. ~10-line relay-friendly summary
6. The mandatory footer (3 lines, see below)
7. The same prompt body stored at `handoff.prompt_artifact`. Default path: `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`

### Mandatory footer

Append this verbatim to the end of every peer prompt. Missing it is a rule violation.

```
---
If you find gaps or improvements, fix them directly and report the diff.
If nothing to change, write "No change needed, PASS".
Important: do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```

---

## Validator minimum execution points

Run the validator at these times (commands, flags, pre-commit setup in [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md) §1):

1. Right after saving a Turn Packet
2. Right after saving the prompt artifact referenced by `handoff.prompt_artifact`
3. Right before writing `suggest_done: true`
4. Right before resuming a paused session
5. End of any turn that modified system docs / prompts / validator / skill / command / hook

`.githooks/pre-commit` runs: document validation, Codex skill metadata check, Codex skill registration dry-run, stale-term lint, DAD decisions check, DAD decision workflow check, DAD packet validation. It also enforces the large-doc guard (`-FailOnLargeDocs`) so root contract docs don't regrow into a monolith. Enable with `git config core.hooksPath .githooks`.

---

## Safety rails

1. **Hard turn limit** — exceeding the scope cap forces ESCALATE
2. **Quality stall** — 2 consecutive turns with the same checkpoint FAIL → ESCALATE to user
3. **Debate cap** — max 3 rounds, then forced ESCALATE
4. **Consecutive failure cap** — 3 consecutive turns with the same checkpoint FAIL → auto ESCALATE
5. **Scope proportion** — warn when small work drifts past 3 turns

Debate procedure, user-intervention points, autonomous / supervised / hybrid modes, Meta Packet evolution, `.prompts/` integration, user-bridge procedure → [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md).

---

## Context carry-forward (summarization)

Turn-to-turn handoff data is byte-capped. Relay brokers truncate `handoff.context` at `CarryForwardMaxBytes` (default 2048) and append `…truncated`. If history beyond the cap is needed, the peer must read `state.json` + prior `turn-{N}.yaml` directly, not re-request it from the relay. Peer prompts SHOULD stay under ~1.5KB of carried context.

See `.prompts/12-context-summarization-policy.md` for the detailed summarization rules the peer applies when the task requires more than one turn's context.

---

## Protocol invariants (forbidden patterns)

These patterns have caused incidents in downstream relays; the validator treats each as a hard fail.

1. **No role-conditional branches.** Code paths, peer prompts, `.prompts/` files, or skills MUST NOT branch on `if agent == "codex"` / `if agent == "claude"`. The protocol is symmetric. Capability differences (tool-use depth, extended-thinking budget, streaming) are injected via a cost-advisor / strategy pattern, not by role-tested conditionals. Any such branch is an `IMMUTABLE:mission` violation.
2. **`final_no_handoff` + populated `next_task` is forbidden.** When a turn sets the session-final flag, `handoff.next_task` MUST be empty or omitted. Populated `next_task` on a final turn is a migration hazard — the next session starts on stale state.
3. **`recovery_resume` requires explicit evidence.** A turn that resumes after an interrupted prior turn (operator re-entry, broker crash) MUST set `confidence: low` and include at least one `open_risks` entry describing what was interrupted. Using `recovery_resume` to skip handoffs or convergence gates is a validator reject.
4. **MCP call correlation is not recorded in the session audit log.** The per-peer JSONL audit log CANNOT attribute which MCP tool was invoked mid-turn (bridge design limit). Turn packets record MCP calls under `evidence.mcp_calls`, but cross-referencing them to audit-log entries is explicitly unsupported. Do not build validator rules that assume correlation.
5. **METRICS.jsonl schema.** Tier-1 fields (including `ts`, `iter`, `outcome`) are required on every line. Project-scoped extensions MUST use a `<project>_` prefix to avoid collisions with relay Tier-3 fields. Validate via `tools/Validate-Metrics.ps1` where shipped.

---

## Agent definitions

Claude Code (conversational, `CLAUDE.md`) and Codex (batch, `AGENTS.md`) are distinct agent endpoints. The protocol does not assume model equality. Each turn packet should surface the agent's actual strengths and limits.

Session creation and turn initialization use `tools/New-DadSession.ps1` and `tools/New-DadTurn.ps1`.

---

## Reference map

- [`Document/DAD/README.md`](Document/DAD/README.md) — rationale for splitting, maintenance rules, reference index
- [`Document/DAD/PACKET-SCHEMA.md`](Document/DAD/PACKET-SCHEMA.md) — Contract / Turn / Meta packet schema, `task_model`, field rules
- [`Document/DAD/STATE-AND-LIFECYCLE.md`](Document/DAD/STATE-AND-LIFECYCLE.md) — `state.json`, session dir, convergence / closure / recovery
- [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md) — validator timing, Debate, full peer-prompt rules, `.prompts/` integration
- [`Document/dialogue/README.md`](Document/dialogue/README.md) — live file layout and session archive
- [`.prompts/README.md`](.prompts/README.md) — task-type prompt index
