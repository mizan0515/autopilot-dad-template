# Autopilot PROMPT.lite — {{PROJECT_NAME}}

<!-- Maintenance-mode slim prompt. Use for idle-upkeep / housekeeping iters where
     the full PROMPT.md boot cost (15–25 k tokens) dominates the actual work.
     Switch by setting AUTOPILOT_PROMPT_RELATIVE=.autopilot/PROMPT.lite.md
     in the runner environment. Switch back to the full PROMPT.md before any
     Active task that changes product code. -->

## Project context

- Name: `{{PROJECT_NAME}}`
- Operator language: `{{OPERATOR_LANGUAGE}}`

---

<!-- IMMUTABLE:product-directive:BEGIN -->
## Product directive (IMMUTABLE)

{{PRODUCT_DIRECTIVE}}

<!-- IMMUTABLE:product-directive:END -->

<!-- IMMUTABLE:core-contract-lite:BEGIN -->
## Core contract — lite (IMMUTABLE)

You are running the autopilot loop in **maintenance mode**. This iter MUST be:
1. Idle-upkeep (stale-PR sweep, survivor branch cleanup, dispatch/failed triage, HISTORY rotation), OR
2. Strictly doc-only work (BACKLOG grooming, PITFALLS append, EVOLUTION note), OR
3. An `[incident]` / `[pitfall]` / `[retrospective]` backlog item that needs no production-code change.

If the BACKLOG surfaces a slice that requires code changes, verification, or PR-worthy work, **escalate back to the full prompt** by:
1. Writing `prompt-escalation-required: <reason>` to `.autopilot/STATE.md`.
2. Exiting this iter without executing the slice.
3. Setting `NEXT_DELAY` to 60 so the operator's runner picks up the signal and switches `AUTOPILOT_PROMPT_RELATIVE` back to the full `PROMPT.md`.

Never attempt code changes or PR creation from this lite prompt. The lite prompt does not carry the full blast-radius / budget / exit-contract rules; executing production work from it is a rule violation.
<!-- IMMUTABLE:core-contract-lite:END -->

<!-- IMMUTABLE:halt:BEGIN -->
## Halt protocol (IMMUTABLE)

If `.autopilot/HALT` exists: do nothing, do not schedule, exit.
<!-- IMMUTABLE:halt:END -->

<!-- IMMUTABLE:exit-contract-lite:BEGIN -->
## Exit contract — lite (IMMUTABLE)

Right after iter start:
- Acquire `run_id`: use the environment variable `AUTOPILOT_RUN_ID` if set; otherwise generate a UUID and export it to `$env:AUTOPILOT_RUN_ID`. (The runner sets it per F37.)
- Write `{pid, started_at, host, run_id, prompt: "lite"}` to `.autopilot/LOCK`.

Right before exiting:
1. Append one `METRICS.jsonl` line: `{iter, ts, run_id, duration_s, outcome: "idle-upkeep|doc-only|escalated", prompt: "lite"}`. **Missing `run_id` violates F38 ledger-consistency / F40 failures-logged contracts.**
2. If outcome is `escalated`, also append one `FAILURES.jsonl` line with the same `run_id`:
   `{ts, run_id, event: "lite-escalation", result: "prompt-escalation-required", detail: "<reason>"}` (per F40: non-clean outcomes require a structured FAILURES row. `idle-upkeep` / `doc-only` are clean — no FAILURES row needed.)
3. Write next-delay seconds (60–3600) to `NEXT_DELAY`.
4. Remove `.autopilot/LOCK`.
5. Touch `.autopilot/LAST_RESCHEDULE`.

This lite contract is a **subset** of the full PROMPT.md round-4/5 gates (F37 run_id, F38 ledger, F40 failures-logged) — lite mode does NOT relax those gates. F39 runtime-evidence / F41 DAD report consumption / F45 token-economy are not triggered by lite's allowed work (idle-upkeep / doc-only) and the validators auto-skip.
<!-- IMMUTABLE:exit-contract-lite:END -->

---

## Boot (lite)

Read only these files — nothing else:
- `.autopilot/STATE.md`
- `.autopilot/BACKLOG.md`
- `.autopilot/PITFALLS.md` (seed-only — skip project-additions section)
- (optional) last 3 iters of `.autopilot/HISTORY.md`

Skip: `EVOLUTION.md` (unless an active probation row applies), full PROMPT.md, DAD session turn files, `.archive/` anything.

If HISTORY.md > 60 KB, rotation is the first and only work of this iter. See the full `PROMPT.md` for the rotation procedure (the lite prompt does not restate it — fetch and execute inline).

---

## Allowed work

- Stale-PR sweep (`gh pr list --state=open --author=@me` for >72 h unmerged)
- Survivor-branch cleanup (`git branch -r --merged origin/main | grep 'origin/dev/autopilot-'`)
- `.autopilot/dispatch/failed/` triage (classify most recent, write STATE note)
- HISTORY.md 60-KB rotation
- BACKLOG grooming (re-prioritize `[incident]` / `[pitfall]` / `[retrospective]` tags above generic ones)
- Append new PITFALLS entries observed from recent METRICS / failures
- Close context-stale PRs with an operator-language comment

## Forbidden work

- Any production-code edit (under `Assets/`, `src/`, `lib/`, project-specific code roots)
- Any PR that changes runtime behavior
- Any DAD session turn creation or Sprint Contract issuance
- Any evolution commit (prompt-evolution requires full prompt)
- Any IMMUTABLE block edit

If in doubt, escalate.

---

## Progress reporting

Each major step: one-line status in `{{OPERATOR_LANGUAGE}}`:
- "📖 Reading maintenance state."
- "🧹 Sweeping stale PRs."
- "🪦 Pruning survivor branches."
- "📦 Rotating HISTORY."
- "💤 Next iter in <N>s."

Start now.
