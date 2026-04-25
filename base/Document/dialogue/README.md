<!-- Dashboard pipeline (round-5 F49): Show-DadDashboard.ps1 delegates to
     .autopilot/project.ps1 status, which writes OPERATOR-LIVE.{json,html}.
     OPERATOR-LIVE.html includes both the DAD sessions panel and (round-5
     F47) the validator-signals panel — superset of the legacy
     DASHBOARD-LIVE artifacts. There is no separate Write-DadDashboard.ps1. -->

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

The operator-facing dashboard lives at `.autopilot/OPERATOR-LIVE.{json,html}`
(produced by `.autopilot/project.ps1 status`, see round-5 F47/F49). It includes
a DAD-sessions panel that reads from this directory without writing to it.

### File roles

| path | role | authoritative? |
|------|------|----------------|
| `state.json` | pointer/state for the currently-active session | ✅ current session |
| `DECISIONS.md` | operator decisions, one-way input surface | ✅ operator input |
| `sessions/{id}/state.json` | session-independent snapshot | ✅ that session |
| `sessions/{id}/turn-{N}.yaml` | Turn Packet original | ✅ that turn |
| `sessions/{id}/turn-{N}-handoff.md` | peer prompt originally relayed | ✅ that turn |
| `sessions/{id}/summary.md` | session closure summary | ✅ closed session |
| `packets/*.yaml` | v1 legacy input | ❌ do not write new files here |

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
- Dashboard refresh + open: `tools/Show-DadDashboard.ps1 -Root .` — delegates to `.autopilot/project.ps1 status`, which writes `OPERATOR-LIVE.{json,html}` (includes DAD-sessions panel + validator-signals panel). Pass `-NoOpen` to skip launching the browser.
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

- The operator dashboard at `.autopilot/OPERATOR-LIVE.html` **reads** `Document/dialogue/` without modifying it (see `Get-DadSessions` in `.autopilot/project.ps1`).
- The operator-facing screen is `.autopilot/OPERATOR-LIVE.html` — generated by `.autopilot/project.ps1 status` (or `tools/Show-DadDashboard.ps1` which delegates to it). Open the ledger (`state.json`, latest `turn-{N}.yaml`) only when needed.
- When the operator leaves a direction or approval, prefer `DECISIONS.md` over editing `state.json` or turn packets directly.
- `DECISIONS.md` does not replace the session ledger. Session state and turn packets remain authoritative; this file holds only operator intent.
- `DECISIONS.md` may only be modified on a work branch and merged via PR. Direct modification on `main`/`master` is blocked by `tools/Validate-DadDecisionWorkflow.ps1`.
- The dashboard surfaces up to the 5 most-recent sessions (state + current turn + checkpoint pass-count + truncated task summary), open auto-PRs, the recent HISTORY.md flow, and (round-5 F47) a `🛡 Validator signals` rollup of recent FAILURES.jsonl event types.
- Dashboard labels are rendered in the operator language declared in `.autopilot/config.json` (locale strings live in `.autopilot/locales/<lang>/strings.json`).
