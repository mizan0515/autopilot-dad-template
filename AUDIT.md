# AUDIT — 17-row incident-prevention matrix

Phase 7 final audit. Cross-references each incident pattern from `card-climber/.autopilot/INCIDENTS.md` (§1–§3) against the template's current safeguards.

| # | Incident pattern | Template safeguard | Source PR | Status |
|---|---|---|---|---|
| 1 | Validator dead-ref on runtime files | `Test-IsEphemeralReference` allowlist in `base/tools/Validate-Documents.ps1:179` — `*-LIVE.*`, `NEXT_DELAY\|LOCK\|HALT\|FAILURES.jsonl`, `.audit-cache.*` patterns | Phase 2 (#6) | ✅ covered |
| 2 | Retained-dirty silent-stall | `base/.autopilot/runners/stalled-fallback.{ps1,sh}` — snapshots, WIP-commits through pre-commit, opens rescue draft PR | Phase 0 (#2) | ✅ covered |
| 3 | Preflight / LLM timeout / consecutive-stall HALT missing | `base/.autopilot/runners/preflight.{ps1,sh}` + `AUTOPILOT_LLM_TIMEOUT_MIN` in runner + `AUTOPILOT_STALL_HALT_THRESHOLD` counter | Phase 0 (#2) | ✅ covered |
| 4 | Budget over-runs normalized | `locales/{ko,en}/.autopilot/PROMPT.md` IMMUTABLE budget block now ships `files_read: 20` / `bash_calls: 30` / `cache-read-ratio 0.25 × 2 iters` caps | Phase 5 (#9) | ✅ covered |
| 5 | Survivor autopilot remote branches | `PROMPT.md` idle-upkeep section documents the `gh api --method=DELETE` cleanup sweep against `origin/dev/autopilot-*` merged branches | Phase 7 | ✅ covered (doc) |
| 6 | QA JSON UTF-8 repair | `policy-registry.json` ships `utf8-bom-contract` policy; project-specific QA writers must hook into it | Phase 4 (#8) | ⚠ policy only — each project enforces in its own QA layer |
| 7 | MCP EditMode focused filter oddness | Documented as known issue in ROADMAP.md §Phase 7 row 7; template is engine-agnostic so no filter code ships | — | ⚠ known issue, project-specific |
| 8 | Unity MCP availability gaps | `preflight.{ps1,sh}` now honors an optional `.autopilot/hooks/preflight-verify.{ps1,sh}` that projects can drop in for engine-specific checks (Unity MCP, custom runtimes) | Phase 7 | ✅ covered (hook slot) |
| 9 | Dispatch queue `failed/` path missing | `base/.autopilot/dispatch/{queue,consumed,failed}/` scaffolded with `.gitkeep` + `README.md` describing job schema and failure-surfacing contract | Phase 7 | ✅ covered |
| 10 | Auto-merge-refused PR tracking | `PROMPT.md` idle-upkeep section documents the stale-PR sweep (`gh pr list --state=open --author=@me`) with explicit CI-red / review-blocked / stale-close branches | Phase 7 | ✅ covered |
| 11 | Concurrent runner LOCK race | `PROMPT.md` exit-contract now specifies PID-tracked LOCK: `{pid, started_at, host}` JSON, liveness-check before overwrite | Phase 7 | ✅ covered (spec) |
| 12 | PROMPT.md deletion → empty-prompt infinite loop | `preflight.{ps1,sh}` adds `Test-Path PROMPT.md` check → `preflight-failed:prompt-missing` | Phase 7 | ✅ covered |
| 13 | Korean BOM mojibake (relay PITFALL) | `policy-registry.json` ships `utf8-bom-contract` policy + `Validate-Documents.ps1` checks; `apply.ps1` writes all MDs via `UTF8NoBomEncoding` | Phase 2 (#6) + Phase 4 (#8) | ✅ covered |
| 14 | Wildcard `Grep` token storm | `locales/{ko,en}/AGENTS.md` + `CLAUDE.md` ship `search_roots` + blacklist (`Library/`, `Temp/`, `Logs/`, `UserSettings/`, `node_modules/`, `target/`, `build/`, `dist/`, unbounded `Packages/`) | Phase 1 (#5) | ✅ covered |
| 15 | HISTORY.md growth to 60 KB | `PROMPT.md` boot block now instructs iter-1-first rotation: move older half to `.autopilot/.archive/HISTORY-<iter>.md`, leave pointer line | Phase 7 | ✅ covered |
| 16 | Relay rotation token-counter reset | Relay-side fix (not template scope) | — | N/A (relay) |
| 17 | Per-iter worktree disk saturation | `relay/SETUP.md` documents reusable worktree convention (`<leaf>-autopilot-runner/live` via `AUTOPILOT_WORKTREE_DIR`) + `git worktree prune` cleanup; `base/.autopilot/runners/runner.ps1` already implements the reuse | Phase 7 | ✅ covered |

## Interpretation

**15 of 17 rows have concrete safeguards** inside the template. The two exceptions:

- **Row 7 (MCP EditMode filter):** genuinely project-specific — Unity MCP quirks have no place in an engine-agnostic template. Left as a documented known-issue.
- **Row 16 (relay token counter):** lives in the relay repo, not here. The template's `relay/SETUP.md` points at the relay as Layer 1 owner; that's where the fix belongs.

**Rows 5, 10, 11, 15 are doc-level safeguards** — the PROMPT.md contract asks the agent to perform the sweep, but there is no static check that the agent actually did it. This is intentional: these are policy choices that differ per project (some operators auto-close stale PRs aggressively, others want manual triage). Hardcoding the behavior would fight operator preference.

## Follow-ups (not part of this audit PR)

- Observe 3+ operators through the full 7-step bootstrap flow and confirm rows 4/5/10/11 sweeps actually fire in practice. If agents skip the idle-upkeep section, promote it into a validator instead of a doc note.
- If Row 11 (PID LOCK) proves fragile across Windows/WSL/Linux PID boundaries, replace with a file-lock daemon rather than JSON-in-file.

## Verification

- `pwsh apply.ps1 -Language ko -Name smoke-audit-test` in a clean dir, then diff against `locales/ko/` → expect every file from this matrix to be present at its documented location.
- `cat .autopilot/PROMPT.md | grep -E "files_read|bash_calls|idle upkeep|HISTORY.md.*60"` → all four hits present.
- `cat .autopilot/runners/preflight.ps1 | grep -E "prompt-missing|verify-hook"` → both hits present.
- `ls .autopilot/dispatch/` → `queue/ consumed/ failed/ README.md` present.
