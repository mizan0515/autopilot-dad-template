# PITFALLS

Recurring traps. Read at iter start; append when you spot a new one. Every new pitfall that recurred ≥2× should earn a one-line entry; the template seeds only landmines we have already observed bite other projects.

## Seed — template authors (always-on)

- Do not edit IMMUTABLE blocks in `PROMPT.md` under the guise of "cleanup". The pre-commit hook rejects such changes.
- Never edit `Document/dialogue/sessions/**/turn-*.yaml` originals — always create a new turn file.
- Avoid relative date queries like `git log --since "1 week ago"` — use commit hashes or absolute dates.
- Avoid recursive searches of `.archive/` — read `.archive/INDEX.md` first and pinpoint-read at most one file.

## Seed — runtime / shell landmines observed in autopilot loops elsewhere

- **Broad regex on localized strings corrupts neighbors.** Edits to `.md` / `.json` / `.yaml` files containing CJK or accented copy must be line-targeted (surrounding context in `old_string`). `sed -i s/X/Y/g` or multi-file `Edit replace_all=true` on localized text has already silently corrupted sibling bullets in another project.
- **`doctor green` ≠ live-runtime-green.** A preflight that returns 0 proves the binary is reachable, not that it responds to work. For any external bridge (Unity MCP, Claude Preview, database, etc.), ship a separate `preflight-runtime-bridge` hook that actually sends a 1-call health ping and asserts a reply, and gate runtime-evidence claims on its exit code.
- **Worktree-bridge drift.** Long-lived external tools (MCP servers, IDEs) may be pinned to a worktree path from a previous iter. When the runner reuses `<leaf>-autopilot-runner/live`, the bridge can still be reporting against a path that no longer matches. Always assert the bridge's reported project path equals the current iter worktree before trusting its output.
- **PowerShell `Start-Process` with spaced-path args silently truncates.** `Start-Process foo.exe -ArgumentList "-projectPath","C:\My Path"` drops after the space. Always pass a single joined string with explicitly quoted spaced tokens, e.g. `-ArgumentList '"C:\My Path"'`. Use `base/tools/Start-Process-Safe.ps1` as the wrapper.
- **Subprocess launched-at-shell ≠ process materialized.** A successful `Start-Process` exit code does not mean the target process is alive. Poll the process list for N seconds and fail the iter if the PID does not appear. The safe wrapper above handles this.
- **Runtime JSON corruption from default PowerShell UTF-16 / BOM.** `Out-File` and `>` redirection default to UTF-16-LE with BOM on Windows PowerShell. Any non-ASCII content (Korean, Japanese, emoji) written to `.autopilot/*.json`, `.autopilot/qa-evidence/*.json`, METRICS lines will mojibake on downstream read. Use `base/tools/Write-Utf8NoBom.ps1` / its `.sh` peer, or explicitly `[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))`.
- **Stale background job collision across iters.** Persistent editors / daemons may carry pending jobs from the previous iter into the new one. Preflight should cancel or drain those before the new iter runs — otherwise the first "success" of the new iter is actually the previous iter's output.
- **`gh pr merge --delete-branch` is unreliable when a local worktree still pins the branch.** Force `git worktree remove` for the iter path first, then merge with `--delete-branch`, then `git fetch --prune`. Relying on the `--delete-branch` flag alone leaves survivor refs on origin.
- **Post-merge branch-delete scope ambiguity.** The post-merge cleanup must only auto-delete branches whose HEAD was created in the current iter. Pre-existing branches marked `[gone]` should be reported to METRICS as cleanup debt and left for operator review; auto-deleting them has already been reported as data-loss-risk.
- **Focused test filter silently returns 0 matches.** Many test runners "succeed" on an empty filter result. A verification step that runs `--filter X` and reports pass must also assert `matched_count > 0` and that the ran set == requested set; otherwise a typo in the filter reads as all-green.
- **`budget_exceeded` saturates the signal.** If every iter flags budget overrun, the flag carries no information. Calibrate the soft caps from observed p75 after ~20 iters; keep `budget_exceeded` as the rare loud signal it was designed to be.
- **METRICS.jsonl schema drift.** Tier 1 fields (including `ts`) are required on every line. Project-specific extensions must use a `<project>_` prefix to avoid collisions between the relay's Tier-3 fields and a downstream repo's. Validate via `tools/Validate-Metrics.ps1` where shipped.

## Project additions (loop appends below this line)
