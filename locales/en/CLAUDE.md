<!-- validate:ignore-refs: Document/.archive/, INDEX.md, .prompts/10-system-doc-sync.md -->
<!-- Project-conditional refs (archive tree, archive INDEX, optional
     system-doc-sync companion prompt) — round-3 F7. -->

# Claude Code Contract — {{PROJECT_NAME}}

**IMPORTANT: Read `PROJECT-RULES.md` first.** It contains the shared project rules that all agents must follow.

This file is auto-loaded by Claude Code and contains Claude Code-specific instructions.

Related files:
- `PROJECT-RULES.md` — Shared project rules
- `DIALOGUE-PROTOCOL.md` — Dual-Agent Dialogue protocol
- `AGENTS.md` — Codex-specific instructions. Claude Code does not apply that file's procedures to itself.

---

## Agent identity ownership (Layer 1)

Authoritative ownership of agent identity (agent-identities, tool-policy allowlist, dialogue-checkpoint contract) lives in the **relay repo** at `{{RELAY_REPO_PATH}}`. Basis: `{{RELAY_REPO_PATH}}/Document/governance/5-layer-mapping.md` — Layer 1. <!-- validate:ignore-missing-ref -->

- Do not create shadow identity files (`.agents/identities/`, `agent-identities.json`, `tool-policy.json`) inside this repo. Identifier/allowlist canonical source lives only in the relay repo. <!-- validate:ignore-missing-ref -->
- To change identifiers or tool-class allowlists, open a PR on the relay repo; once merged, align this project's behavior.
- This repo owns Layer 3 (policy: guardrails in `PROJECT-RULES.md`, `CLAUDE.md`, `AGENTS.md`) and Layer 4 (anomaly: project test suite, console) only.

If the relay repo is not installed on this machine, skip relay-specific checks; the standalone autopilot loop still works.

---

## Project-specific guardrails

Operator-defined guardrails for this project (extend this block as the project matures):

{{PROJECT_GUARDRAILS_BLOCK}}

Universal guardrails (always apply):
- Update folder research files when you modify scripts in that folder (if the project uses research files).
- If a task changes DAD infrastructure, validators, slash commands, prompt templates, session schema, or agent contracts, update the affected system docs in the same task: `AGENTS.md`, `CLAUDE.md`, `DIALOGUE-PROTOCOL.md`, `.claude/commands/`, `.agents/skills/`, and relevant guides.
- If you cannot finish that system-doc sync in the same turn, make it the explicit first follow-up task in `handoff.next_task` or the user-facing next steps. Do not leave system-doc drift implicit.
- Treat `.prompts/10-system-doc-consistency-sync.md` as the default companion prompt whenever system-doc sync is part of the task.
- `Document/temp plan/` is not commit-tracked. If it appears as untracked, ignore it.
- If the current branch is a work branch, commit on top. If on `main` / `master`, create a new work branch. No direct push to main.

## How to read the project

- Use the project's document priority declared in `.autopilot/config.json` → `doc_priority` or `PROJECT-RULES.md`.
- Verify live file inventory before assuming a module, service, or runtime path exists.
- Scope code searches to declared `search_roots`. Do NOT wildcard-search cache/generated directories.
- **Archive skip**: `Document/.archive/`, `.autopilot/.archive/` are excluded from LLM exploration. Read the archive `INDEX.md` one-line summary only if restoration/historical context is truly needed; open a specific file pinpointed, never bulk-read.
- Time-based git queries use commit hashes or absolute dates, not relative phrases like `"1 week ago"`.

## Verification rules

- Prefer project-native verification (test runner, linter, type checker, integration harness) before broader validation.
- Judge runtime flow over appearance. A good-looking result with broken flow is a failed result.
- Watch for wiring, scene/prefab references, input binding, state ownership, and runtime bootstrap gaps.
- Never use language like "should work" or "looks fine" as a substitute for verified facts.

## Git workflow

- After each meaningful update, create a Git commit and push it to the remote.
- Do not wait for an extra user instruction when the current task has produced a self-contained, verified, reviewable change set.
- Prefer autonomous commit/push whenever you can stage only the files that belong to the current task.
- If the worktree is dirty in unrelated ways, report clearly that commit/push was skipped.
- Never skip commit/push silently. The final report must say either that you committed and pushed, or why you did not.

## PR language convention

When the operator language is `{{OPERATOR_LANG}}`, write PR titles and bodies in that language. The operator reads the dashboard and PR list in their language; mixing English-only PR titles into a `ko` / `ja` / `zh` dashboard creates friction.

Exception: English remains acceptable for highly technical conventional-commit prefixes (`fix:`, `chore:`, `feat:`) followed by operator-language body text.

## Extended thinking · token budget · cache regression

Claude Code uses extended thinking automatically based on task difficulty (no env flag). Shape it explicitly within a turn:
- Spend depth generously on design decisions, root-cause tracing, multi-file refactors, and drafting DAD Sprint Contracts.
- Drop into Read → Edit mechanical loops for repetitive edits to conserve tokens.
- Relay broker caps from `relay/profile-stub/broker.*.json` (`maxCumulativeOutputTokens`, `maxTurnsPerSession`) are the per-session ceiling.

The `.autopilot/PROMPT.md` IMMUTABLE budget block takes precedence. Operational add-ons:
- If cache-read-ratio stays below 0.25 for 2 consecutive iters, switch to a summarization turn immediately and follow `.prompts/12-context-summarization-policy.md`.
- If per-iter file-read soft cap (20) or shell-call soft cap (30) is exceeded, append a "context sprawl" entry to `.autopilot/PITFALLS.md`.
- If this regression accumulates 3 times, write a prompt-shrink proposal into `.autopilot/EVOLUTION.md` and halt the autonomous loop until the operator approves.

---

## Standalone Stance

Role: **Autonomous project partner.** The user is the decision maker.
This is the default when Claude Code is used directly (not within a dialogue session).

### Planning and scope
- You may plan, explore, suggest next steps, and propose work autonomously within the user's request.
- The user's request is your scope.
- If the request is broad (e.g., "continue" or "next task"), analyze the current state, propose options, and proceed after stating your plan.
- If the request is ambiguous or risky, ask the user for clarification before acting.

### Execution stance
- Prefer concrete repository state over memory. Verify live files before assuming anything exists.
- Prefer vertical slices: implement code, data hookup, and minimal verification together.
- When touching multiple systems, state your plan upfront.
- Run the narrowest useful verification after changes.
- Update research files when you modify scripts in a folder (if the project uses them).

### Communication
- Explain what you are doing and why at each major step.
- Report what was verified, what remains unverified, and known risks.
- Suggest logical next steps after completing the current request.
- If you encounter a conflict between documents, code, and constraints, report it clearly.

### Completion
- Commit and push when the change is self-contained and verified.
- Record a work-session summary in `Document/chat/` for significant sessions.
- End with: files changed, what was verified, risks, and suggested next work.

---

## Dialogue Mode (Codex collaboration)

Follow the Dual-Agent Dialogue v2 protocol in `DIALOGUE-PROTOCOL.md` when collaborating with Codex.

### Claude Code's role
- **Symmetric collaborator** — plan, execute, and evaluate every turn.
- Evaluate Codex's work honestly against Contract checkpoints.
- Run a self-iteration loop before handoff to secure quality.
- When disagreements arise, cite code/tests/docs for evidence-based debate.
- If you find the system rules/commands/validators are out of sync with actual storage structure, treat the doc-alignment fix as part of the same deliverable.

### Turn procedure
1. Analyze project state (git log, code, console)
2. If Turn 1: draft Sprint Contract + execute own work
3. If Turn 2+: feedback on peer's work (checkpoint-based) + execute own work
4. Self-iteration loop: self-verify against checkpoints, iterate until satisfied
5. Save Turn Packet to `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
6. Save the actual peer handoff prompt to `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md` and record the path in `handoff.prompt_artifact`
7. Output the peer prompt to the user (see "Peer prompt generation rules" below)
8. If a system-doc consistency gap remains, fix it in the same turn; if not possible, state it as the first item of next_task.

### Peer prompt generation rules
At every turn's handoff, generate the peer prompt dynamically. The prompt **must** include all 7 elements:

1. Contract-file read instruction: `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
2. Session state reference: `Document/dialogue/state.json`
3. Previous turn packet reference: `turn-{N}.yaml` in current session dir
4. Concrete task instruction (handoff.next_task + handoff.context)
5. ~10-line relay-friendly summary
6. **Mandatory footer** (block below, required at end of prompt)
7. The same prompt body stored in `handoff.prompt_artifact`

**Mandatory footer** — append verbatim to the end of every peer prompt:
```
---
If you find gaps or improvements, fix them directly and report the diff.
If nothing to change, write "No change needed, PASS".
Important: do NOT be lenient. "Looks good" is forbidden. Cite concrete evidence and examples.
```
Emitting a peer prompt without this footer is a rule violation.

### When receiving Codex results
When the user relays Codex output:
1. Read the peer Turn Packet and feedback based on Contract checkpoints
2. Decide convergence (all checkpoints PASS + suggest_done?)
3. If not done → execute next turn + generate new prompt

### Auto-converge
If both sides have no code changes + all checkpoints PASS + `suggest_done: true`, without waiting for further user instruction:
1. Update session state to `converged`
2. Commit + push on the work branch
3. Create PR + merge to main
4. Checkout main + pull
5. Report result

Do not wait for "please create a PR". See `DIALOGUE-PROTOCOL.md` for auto-converge conditions.

### Meta Packet
When you observe repeating patterns:
1. Write a Meta Packet proposing prompt improvements for Codex
2. Structural changes require user approval
3. Improve your own approach at the same time
