# AUDIT — 48-row incident-prevention matrix

Phase 7 first-pass audit (rows 1–17) covered the silent-stall chain from `card-climber/.autopilot/INCIDENTS.md` §1–§3. Phases 8–10 (round-2 audit) extended the matrix with 26 more rows drawn from `D:\Unity\card game\.autopilot\PITFALLS.md` and `D:\cardgame-dad-relay\.autopilot\PITFALLS.md` + governance docs. Round-3 (rows 44–48) came from a real first-time-installer dogfood test on a brand-new project — every bug a fresh operator would actually hit.

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

## Round-2 extension — runtime discipline + relay robustness (rows 18–43)

Sourced from the audit of `D:\Unity\card game` + `D:\cardgame-dad-relay` after phases 1–7 closed. Split across three PRs.

| # | Incident pattern | Template safeguard | Source PR | Status |
|---|---|---|---|---|
| 18 | Broad regex/replace_all on localized strings corrupts neighbors | `locales/{en,ko}/.autopilot/PITFALLS.md` seed entry; `PROMPT.md` shell-discipline section | Phase 8 (#13) | ✅ covered (doc) |
| 19 | `doctor green` ≠ live-runtime-green | `preflight.{ps1,sh}` adds separate `preflight-runtime-bridge` hook slot (soft-fail, distinct from hard-fail verify-hook); `PROMPT.md` runtime-evidence trust gate | Phase 8 (#13) | ✅ covered |
| 20 | Worktree-bridge drift (long-lived MCP pinned to old worktree) | `PROMPT.md` runtime-evidence gate mandates bridge-reported-path == iter worktree check | Phase 8 (#13) | ✅ covered (doc) |
| 21 | PowerShell `Start-Process` spaced-arg truncation | `base/tools/Start-Process-Safe.ps1` wrapper + PITFALLS seed | Phase 8 (#13) | ✅ covered |
| 22 | Subprocess launched-at-shell ≠ process materialized | same `Start-Process-Safe.ps1` polls PID for N seconds + PITFALLS seed | Phase 8 (#13) | ✅ covered |
| 23 | PowerShell UTF-16-BOM corruption of runtime JSON / QA evidence | `base/tools/Write-Utf8NoBom.ps1` + `write-utf8-nobom.sh` + PITFALLS seed + `PROMPT.md` shell-discipline | Phase 8 (#13) | ✅ covered |
| 24 | Stale bg-job collision across iters | PITFALLS seed; `preflight-runtime-bridge` hook slot is the drain-point | Phase 8 (#13) | ✅ covered (doc + slot) |
| 25 | `gh pr merge --delete-branch` unreliable with worktree pinning | PITFALLS seed instructs `git worktree remove` → merge → `fetch --prune` order; stale-PR sweep (row 10) covers the cleanup | Phase 8 (#13) | ✅ covered (doc) |
| 26 | Post-merge branch-delete scope ambiguity | PITFALLS seed: only auto-delete branches created in the current iter; pre-existing `[gone]` reported to METRICS as cleanup debt | Phase 8 (#13) | ✅ covered (doc) |
| 27 | Focused test-filter silently returns 0 matches | `PROMPT.md` test-filter zero-match guard — fail iter + METRICS `test-filter-zero` | Phase 8 (#13) | ✅ covered |
| 28 | `budget_exceeded` signal saturation | `PROMPT.md` budget self-calibration protocol (p75 recalibration after iter 20; IMMUTABLE caps untouched) | Phase 8 (#13) | ✅ covered |
| 29 | Incident→backlog admission not practiced | `PROMPT.md` `[incident]`/`[pitfall]`/`[retrospective]` admission tags, prioritized in idle-upkeep/brainstorm | Phase 8 (#13) | ✅ covered (doc) |
| 30 | Rotation infinite loop on lifetime cumulative counter | `broker.myproject.json` `_notes` mandates segment-scoped `OutputTokensAtLastRotation`; `relay/SETUP.md` Troubleshooting #1 | Phase 9 (#14) | ✅ covered (contract) |
| 31 | Rotation leaves non-active peer's native session handle (C2 violation) | `broker.myproject.json` `_notes` + `relay/SETUP.md` Troubleshooting #2 (C1/C2/C3 contract checklist) | Phase 9 (#14) | ✅ covered (contract) |
| 32 | Silent artifact-write failure swallowed | `relay/SETUP.md` Troubleshooting #3 mandates exit=5 + `artifact_write_failures` population; `--working-dir` hygiene | Phase 9 (#14) | ✅ covered (contract) |
| 33 | Convergence rejected when no Sprint Contract issued (small-scope) | `relay/SETUP.md` Troubleshooting #4; `DIALOGUE-PROTOCOL.md` already encodes small-scope Contract-optional | Phase 9 (#14) | ✅ covered |
| 34 | Live-path not verified by `dotnet build` alone | `relay/SETUP.md` required `ccrelay-run --probe-only` smoke before task dispatch | Phase 9 (#14) | ✅ covered |
| 35 | Peer asymmetry via `if agent == "codex"` role-conditional branches | `DIALOGUE-PROTOCOL.md` Protocol Invariants #1 (IMMUTABLE:mission violation); `relay/SETUP.md` Troubleshooting #6 lint guidance | Phase 9 (#14) | ✅ covered |
| 36 | `final_no_handoff` with populated `next_task` (migration hazard) | `DIALOGUE-PROTOCOL.md` Protocol Invariants #2 | Phase 9 (#14) | ✅ covered |
| 37 | `recovery_resume` misuse to skip handoffs | `DIALOGUE-PROTOCOL.md` Protocol Invariants #3 (requires `confidence:low` + ≥1 `open_risks`) | Phase 9 (#14) | ✅ covered |
| 38 | MCP correlation in audit log falsely assumed present | `DIALOGUE-PROTOCOL.md` Protocol Invariants #4 documents this as explicit non-feature | Phase 9 (#14) | ✅ covered (doc) |
| 39 | METRICS.jsonl schema drift (missing `ts`, collision with Tier-3) | `DIALOGUE-PROTOCOL.md` Protocol Invariants #5; `base/tools/Validate-Metrics.ps1` enforces Tier-1 + `<project>_` prefix | Phase 9 (#14) | ✅ covered |
| 40 | `handoff.context` unbounded → token bloat cross-turn | `broker.myproject.json` `carryForwardMaxBytes: 2048` (was missing); mirrored from DIALOGUE-PROTOCOL cap | Phase 9 (#14) | ✅ covered |
| 41 | Broker cap values unsafe as shipped defaults | `broker.myproject.json` tuned: `maxCumulativeOutputTokens=30000`, `maxTurnsPerSession=12`, `maxSessionDuration=00:30:00`, `perTurnTimeout=00:10:00`, `cacheReadRatioFloor=0.25`, `consecutiveLowCacheTurnsThreshold=2` | Phase 9 (#14) | ✅ covered |
| 42 | PROMPT boot cost dominates maintenance iters | `locales/{en,ko}/.autopilot/PROMPT.lite.md` + `AUTOPILOT_PROMPT_RELATIVE` switch protocol in `PROMPT.md` prompt-economy section | Phase 10 (#15) | ✅ covered |
| 43 | Relay-autopilot vs project-autopilot confusion | `relay/SETUP.md` "Relay autopilot vs project autopilot" isolation note | Phase 9 (#14) | ✅ covered (doc) |

## Round-3 extension — first-time-installer dogfood (rows 44–48)

Rows 44–48 came from running the template end-to-end against a brand-new project (`D:\dogfood-sample`, ko locale, no PRD-detection priors) with the same one-prompt path a real operator would take. PR #17 fixes all five.

| # | Incident pattern | Template safeguard | Source PR | Status |
|---|---|---|---|---|
| 44 | F1 — Pwsh OEM-codepage mojibake on Korean filenames in install log (e.g. `12-�ƶ�-���-��å.md`) makes Korean operators think the install corrupted their tree | `apply.ps1` head now forces `[Console]::OutputEncoding = UTF-8` + `$OutputEncoding = UTF-8` | Round-3 (#17) | ✅ covered |
| 45 | F2 — `strings.json` bleeds to target repo root because Copy-Tree walks the full `locales/<lang>/` tree (locale-root file gets dumped at `<target>/strings.json`) | `Copy-Tree`/`copy_tree` gain an `ExcludeRelative` parameter; locale walk skips `strings.json` (still copied explicitly to `.autopilot/locales/<lang>/`) | Round-3 (#17) | ✅ covered |
| 46 | F3 — `preflight.{ps1,sh}` aborted manual runs with cryptic "missing mandatory parameters: AutopilotRoot" because the runner-only invocation contract was undocumented | Both preflight scripts default `-AutopilotRoot` / `$1` to `<pwd>/.autopilot` when omitted; runner still passes explicit path | Round-3 (#17) | ✅ covered |
| 47 | F4 — `git-no-origin` failure surfaced as opaque token; fresh-project operators stalled with no remediation path | Per-problem hint switch in both preflights (covers `git-no-origin`, `gh-not-installed`, `gh-not-authed`, `ai-cli-missing*`, `no-prompt-md`) + new "Make sure a GitHub remote exists" step in `apply.{ps1,sh}` Next-steps with copy-paste `gh repo create` | Round-3 (#17) | ✅ covered |
| 48 | F5 — `PROMPT.lite.md` placeholders never substituted (Phase 10 regression — apply.{ps1,sh} only rendered `PROMPT.md`); the moment `AUTOPILOT_PROMPT_RELATIVE` flipped to maintenance mode the agent saw literal `{{PROJECT_NAME}}` | Render block in both installers loops over `@('PROMPT.md', 'PROMPT.lite.md')` so any future prompt variant inherits placeholder substitution by default | Round-3 (#17) | ✅ covered |

## Interpretation

**46 of 48 rows have concrete safeguards** inside the template. The two remaining exceptions:

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
