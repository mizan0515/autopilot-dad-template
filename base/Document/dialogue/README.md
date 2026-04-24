# Document/dialogue/ — DAD v2 runtime directory

This folder holds Dual-Agent Dialogue v2 **runtime artifacts** — not contract/schema definitions, but the state/packets/summaries/archives produced by actual sessions.

Contract docs:
- `DIALOGUE-PROTOCOL.md` (repo root) — thin contract
- `Document/DAD/PACKET-SCHEMA.md` / `Document/DAD/STATE-AND-LIFECYCLE.md` / `Document/DAD/VALIDATION-AND-PROMPTS.md` — detailed rules

---

## Directory layout

```
Document/dialogue/
├── README.md                           # this file
├── DECISIONS.md                        # operator decision input (one-way)
├── DASHBOARD-TEMPLATE.{lang}.html      # tracked dashboard shell (lang = operator_language)
├── DASHBOARD-LIVE.{lang}.json          # runtime-generated dashboard data
├── DASHBOARD-LIVE.{lang}.html          # runtime-generated dashboard view
├── state.json                          # root state pointer for the currently-active session
├── sessions/
│   ├── {session-id}/
│   │   ├── state.json                  # session-local snapshot
│   │   ├── turn-01.yaml                # canonical Turn Packet
│   │   ├── turn-01-handoff.md          # the actual peer prompt that was emitted
│   │   ├── turn-02.yaml
│   │   ├── ...
│   │   └── summary.md                  # closed-session summary (optional)
│   └── YYYY-MM-DD-{session-id}-summary.md  # named summary for a closed session (optional)
└── packets/                            # legacy v1 input (migration only — do not write new packets here)
```

### File roles

| path | role | authoritative? |
|------|------|----------------|
| `state.json` | pointer/state for the currently-active session | ✅ current session |
| `DECISIONS.md` | operator decisions, one-way input surface | ✅ operator input |
| `DASHBOARD-TEMPLATE.{lang}.html` | tracked dashboard shell | ✅ template |
| `DASHBOARD-LIVE.{lang}.json` | compressed read-only dashboard data | ❌ derived |
| `DASHBOARD-LIVE.{lang}.html` | rendered dashboard operators read | ❌ derived |
| `sessions/{id}/state.json` | session-independent snapshot | ✅ that session |
| `sessions/{id}/turn-{N}.yaml` | Turn Packet original | ✅ that turn |
| `sessions/{id}/turn-{N}-handoff.md` | peer prompt originally relayed | ✅ that turn |
| `sessions/{id}/summary.md` | session closure summary | ✅ closed session |
| `packets/*.yaml` | v1 legacy input | ❌ do not write new files here |

The `{lang}` placeholder is replaced with the operator language at apply time (e.g. `DASHBOARD-LIVE.ko.html` for `ko`).

---

## Operational rules

1. **New Turn Packet path**: `sessions/{session-id}/turn-{N}.yaml` only. The `{N}` in the filename must match the inner `turn:` value. Non-standard filenames (e.g. `turn-01-suffix.yaml`) are rejected by `tools/Validate-DadPacket.ps1` and normalized by `tools/Migrate-DadSession.ps1`.
2. **Root `state.json` and session `state.json` sync**: when the active session changes, overwrite the root state; keep the prior session's state at `sessions/{id}/state.json`. Transition the prior session's `session_status` to `superseded` if appropriate.
3. **Handoff prompt artifact**: when creating or modifying a turn, save the actual peer prompt alongside `turn-{N}.yaml` as `turn-{N}-handoff.md` and record the path in `handoff.prompt_artifact`. Legacy sessions that lack this file are kept as-is.
4. **3 closure artifacts**: when closing a session, write `session_status`/`closed_reason`/optional `superseded_by`, a final Turn Packet, and a scope `summary.md`.
5. **Short session-scoped slices**: prefer chaining short sessions over one long umbrella session. Switch sessions when goals, verification surface, or work ownership change.
6. **Legacy path**: do not write new artifacts to `packets/`. The validator rejects residue there unless `-AllowLegacyPackets` is supplied; that flag is for migration-input inspection only.

---

## Session creation / turn creation / validation

- New session: `tools/New-DadSession.ps1` — creates session directory and initial `state.json`.
- New turn: `tools/New-DadTurn.ps1` — generates the next `turn-{N}.yaml` skeleton.
- Dashboard refresh: `tools/Write-DadDashboard.ps1` — reads the active session and writes `DASHBOARD-LIVE.{lang}.{json,html}`.
- Open dashboard: `tools/Show-DadDashboard.ps1` — regenerates then opens.
- Validator set (the `.githooks/pre-commit` hook runs the same chain):
  - `tools/Validate-Documents.ps1 -Root . -IncludeRootGuides -IncludeAgentDocs -Fix`
  - `tools/Validate-CodexSkillMetadata.ps1 -RepoRoot .`
  - `tools/Register-CodexSkills.ps1 -RepoRoot . -SkillHome .git/.codex-hook-validate -ValidateOnly`
  - `tools/Lint-StaleTerms.ps1`
  - `tools/Validate-DadDecisions.ps1 -Root .`
  - `tools/Validate-DadDecisionWorkflow.ps1 -Root .`
  - `tools/Validate-DadPacket.ps1 -Root . -AllSessions`
- Large-doc guard: `tools/Validate-Documents.ps1 -ReportLargeRootGuides -FailOnLargeDocs` — blocks the three root contract files (`AGENTS.md`, `CLAUDE.md`, `DIALOGUE-PROTOCOL.md`) from regrowing into a monolith (default threshold 12000 chars). Add `-ReportLargeDocs` for a non-enforcing report on other `Document/` files.

---

## Operator notes

- The DAD dashboard **reads** `Document/dialogue/` without modifying it.
- The operator-facing screen is `DASHBOARD-LIVE.{lang}.html`. Open the ledger (`state.json`, latest `turn-{N}.yaml`) only when needed.
- For a one-click open, run the root-level launcher if provided by `.autopilot/` (filename depends on operator language).
- When the operator leaves a direction or approval, prefer `DECISIONS.md` over editing `state.json` or turn packets directly.
- `DECISIONS.md` does not replace the session ledger. Session state and turn packets remain authoritative; this file holds only operator intent.
- `DECISIONS.md` may only be modified on a work branch and merged via PR. Direct modification on `main`/`master` is blocked by `tools/Validate-DadDecisionWorkflow.ps1`.
- The dashboard computes turn pressure (`current_turn / max_turns`) and the elapsed days since the latest turn, then warns on long dormancy or near-cap pressure first.
- The dashboard scans all sessions under `Document/dialogue/sessions/` and groups recent ones by state: `active / converged / superseded / abandoned`.
- `abandoned`, `superseded`, and long-idle `active` sessions are promoted to a dedicated "at-risk" block.
- The Primary Queue at the top of the dashboard combines the active session's next task, flagged items from `DECISIONS.md`, and at-risk sessions — a short list of "what to handle now" with `urgency reason` tags.
- Dashboard labels are rendered in the operator language declared in `.autopilot/config.json`.
