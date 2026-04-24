# Relay setup

The relay is a separate .NET-based broker. It lives in its own repo (typically a
fork of a reference implementation like `cardgame-dad-relay`).

## Prerequisites

- .NET 8 SDK or later
- Git
- PowerShell 7.2+ (for status scripts)

## 1. Clone or fork the reference relay

```sh
# Example: fork cardgame-dad-relay to your own org, then clone
git clone https://github.com/<your-org>/<your-relay>.git D:\<your-relay>
```

Pick a path that this project can point at. Typical layouts:

- Windows: `D:\<your-relay>`
- macOS / Linux: `~/code/<your-relay>`

## 2. Build the relay CLI

```sh
cd D:\<your-relay>
dotnet build -c Release
```

The CLI binary typically lands at:
- `CodexClaudeRelay.Adapters.Cli/bin/Release/net8.0/codex-claude-relay.exe` (Windows)
- `CodexClaudeRelay.Adapters.Cli/bin/Release/net8.0/codex-claude-relay` (macOS/Linux)

Add that directory to your `PATH`, or symlink the binary into `~/.local/bin/`.

## 3. Create a profile for this project

The relay uses per-project profiles under `profiles/<project-slug>/`. Copy the
profile stub shipped with this template:

```sh
cp -r <this-project>/relay/profile-stub <your-relay>/profiles/<your-slug>
```

Then edit:
- `profile.json` → set the project slug, directive, bucket list
- `agent-identities.json` → rename `<slug>-autopilot-manager`, `<slug>-route-direct-codex`, etc.
- `broker.<slug>.json` → adjust token budgets and turn limits to this project's size
- `tool-registry.json`, `policy-registry.json` → add/remove tool classes as needed

## 4. Point this project at the relay

Edit `.autopilot/config.json` in this project:

```json
{
  "relay_repo_path": "D:\\<your-relay>"
}
```

The autopilot loop reads this path to resolve relay-side artifacts and status.

## 5. Verify

```sh
codex-claude-relay --version
codex-claude-relay profile list
```

If both succeed, relay is installed and this project should discover the profile.

## MCP pass-through (default enabled)

Relay profiles ship with MCP pass-through enabled by default. This means:

- When Codex invokes an MCP tool (e.g., Unity MCP, Claude Preview), the relay
  forwards the call through a shared broker so Claude Code sees the same reply.
- Turn packets record the MCP calls in `turn-{N}.yaml` under `evidence.mcp_calls`.
- If a call fails or times out, the relay raises an anomaly signal rather than
  silently dropping the data.

To disable pass-through for a specific profile, set `profile.json`:
```json
{
  "mcp_passthrough": false
}
```

## Worktree reuse (disk-saturation prevention)

The autopilot runner in this template creates a **single reusable worktree** at
`<repo-parent>/<leaf>-autopilot-runner/live` (override via `AUTOPILOT_WORKTREE_DIR`)
rather than a per-iter worktree. This prevents the Row 17 incident where disk
fills up after hundreds of iters.

If you ever see `<leaf>-autopilot-runner/iter-*` directories accumulating:

```sh
git worktree prune --expire now
```

run from the main repo root will detach and clean dead worktrees. Do NOT `rm -rf`
stale worktrees — always use `git worktree remove` / `git worktree prune` so the
main repo's `.git/worktrees/` bookkeeping stays consistent.

## Live smoke after install (required)

`dotnet build` success is a preflight, not a live check — a green build still leaves room for a broker that exits before writing artifacts or a relay that silently swallows exit codes. Before dispatching any real task, run a probe:

```sh
codex-claude-relay ccrelay-run --probe-only --profile <your-slug>
```

The probe exits 0 only if the full turn path (broker startup → adapter invocation → handoff artifact write → exit signaling) completes end-to-end. Treat a non-zero probe as "do not dispatch" regardless of `dotnet build` status.

## Troubleshooting — recurring relay incidents

The following classes have bitten other projects using this same relay. Check these before opening a new bug report.

### 1. Rotation infinite loop after a segment rotate

**Symptom:** a session rotates on `maxCumulativeOutputTokens`, immediately re-trips the ceiling on the very next turn, and loops.

**Cause:** the rotation trigger is comparing against a **lifetime** output-token counter instead of a **segment-scoped** counter reset at rotation time.

**Fix:** the broker must track `OutputTokensAtLastRotation` and compare `(total - OutputTokensAtLastRotation) >= maxCumulativeOutputTokens`. Never use raw lifetime totals in the rotation trigger. The shipped `broker.<slug>.json` encodes this expectation in `_notes`.

### 2. Rotation that did not clear the non-active peer's native session handle (C2 contract)

**Symptom:** after a rotation, one peer gets a "fresh" session while the other silently continues against the pre-rotation session handle, producing contract divergence and cache thrash.

**Fix:** rotation must clear native session handles for **all** roles, not just the active one. Contracts C1/C2/C3:
- **C1** — rotate on trigger (ceiling, cache-floor-breach, turn cap, duration cap).
- **C2** — clearing native handles on rotation is *mandatory for every role*, including inactive.
- **C3** — post-rotation turn starts with empty native-session state but preserved packet history.

Downstream relays MUST NOT ship C1 alone.

### 3. Silent artifact-write failures swallowed

**Symptom:** a session reports `converged: true` but no `turn-{N}-handoff.md` / `report-<id>.json` / learning record appears on disk.

**Fix:** the broker must exit 5 and populate `artifact_write_failures` in the report on write failure — never exit 0 on a silent failure. Also verify the broker writes under `--working-dir`, not the adapter's CWD. Surface failures on the operator dashboard.

### 4. Convergence rejected when no Contract was issued (small-scope session)

**Symptom:** both peers emit `suggest_done: true` but the session stays `active`.

**Fix:** the convergence gate must accept mutual `suggest_done` even when no Sprint Contract was issued (small-scope sessions omit Contracts by design — see `DIALOGUE-PROTOCOL.md` scope table). Reject only when *one* side claims done without the other.

### 5. PROMPT boot cost dominates maintenance iters

**Symptom:** idle-upkeep / housekeeping iters burn 15–25 k tokens on prompt boot alone before doing trivial work.

**Fix:** see Phase 10 (`AUTOPILOT_PROMPT_RELATIVE=.autopilot/PROMPT.lite.md` for maintenance profiles, full PROMPT.md for Active mode).

### 6. Peer asymmetry via role-conditional branches

Relay code / prompts must NEVER contain `if agent == "codex"` / `if agent == "claude"` branches. The DAD v2 protocol is symmetric; any such branch violates the `IMMUTABLE:mission` invariant in `DIALOGUE-PROTOCOL.md` and drifts peer capability contracts apart. Use a strategy / cost-advisor pattern instead. Lint review PRs for this.

## Relay autopilot vs project autopilot

The relay repo may have its own `.autopilot/` folder (the relay's self-improvement loop, separate daemon). That is **not** the same as your project's `.autopilot/` scaffolded by this template. Do not cross-reference their states. Symptoms of confusion:
- Adding a relay-repo BACKLOG item and expecting the project loop to pick it up.
- Running `AUTOPILOT_WORKTREE_DIR` from the relay repo by accident.
- Mixing `reports/` paths between the two — relay writes reports under `<relay>/Document/operator/`, projects consume them from `<project>/.autopilot/reports/`.

Keep the two loops isolated. The only shared artifact is the `dispatch/queue` → `reports/` handoff flow.

## Fallback: user-bridged mode

If you skip relay install, DAD still works:
- Each agent produces a peer prompt body.
- User copy-pastes between Codex and Claude Code.
- No MCP pass-through (each agent's MCP state is local).
- No centralized token ceiling (each agent's budget is local).

This is the default when `relay_repo_path` is empty in `.autopilot/config.json`.
