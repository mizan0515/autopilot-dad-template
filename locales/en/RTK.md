# RTK — Shell Output Compression (optional)

RTK is an **operator-machine** CLI proxy that compresses noisy shell output. It is not a project dependency — if RTK is not installed on this machine, ignore this file.

## Typical install path

- Windows: `C:\Users\<you>\.local\bin\rtk.exe`
- macOS / Linux: `~/.local/bin/rtk`

Detect with `rtk --version` or `which rtk`. If the command is missing, skip the RTK section entirely.

## Purpose

RTK reduces token noise for shell output. Use it when the exact stdout is not the artifact being reviewed.

This project also relies on document validators, Git hooks, MCP tools, encoding checks, and dashboard diagnostics. Those often require raw output, so RTK is intentionally not a blanket wrapper.

## Use RTK

Good candidates:

```
rtk git status --short --branch
rtk git diff --stat
rtk git diff --name-only
rtk git log --oneline -10
rtk rg -n "<term>" <search-root>
rtk rg --files <search-root>
rtk gh pr list --state open --limit 20
```

Typical uses:

- broad `rg` searches and `rg --files`
- Git status, short log, diff summaries, name-only diffs
- GitHub list/search commands where a compact result is enough
- successful high-volume test output after failing diagnostics are already captured

For path-limited searches, prefer explicit roots declared in `.autopilot/config.json` → `search_roots`.

## Use raw output

Run directly (or use `rtk proxy <command>`) when exact output, hooks, or side effects matter:

- mutating Git: `git add`, `git commit`, `git push`
- Git checks whose source lines matter: `git diff --check`, `git check-ignore -v`, `git ls-files --others -i --exclude-standard`
- project validators and hooks: `tools\Validate-Documents.ps1`, `.githooks\pre-commit`
- autopilot diagnostics: `.autopilot\project.ps1 status`, `doctor`, `test`, `start`
- PowerShell cmdlets: `Get-Content`, `Get-ChildItem`, `Select-String`, `Format-Hex`, `Test-Path`
- explicit encoding / BOM / localized text reads and writes
- dashboard debugging: `node`, `npx playwright`, screenshot capture
- downloads, installers, package install, interactive commands
- failing test logs that need full stack traces
- binary, image, media, archive, or generated runtime output

RTK does not apply to MCP tools, file editing tools, image tools, or web browsing tools.

## Failure fallback

If RTK output hides the cause of a failure, rerun the same command directly or with `rtk proxy`.

Do not commit or push based only on compressed output. Confirm the final staged and branch state with raw `git status --short --branch` when the result matters.

## Verification

```
rtk --version
rtk gain
rtk init --show
```

If any of these fail, skip RTK for this session and run commands directly.
