# Validate-RuntimeEvidence.ps1
#
# Round-4 F39 — runtime-evidence admission gate.
#
# When the agent's most recent METRICS.jsonl row claims `outcome:"shipped"`
# AND the iter's Active Task carries a tag in the runtime-required set
# (`[ui]`, `[ux-visible]`, `[runtime]`, `[playmode]`, `[scene]`, etc.),
# the row MUST include a `runtime_evidence` field with at least one
# concrete artifact reference:
#
#   {
#     "screenshot_path"      : "<path/to/file>",   # captured screen
#     "smoke_exit_code"      : 0,                   # smoke test exit
#     "mcp_tool_response"    : "<short summary>",   # live MCP probe
#     "play_mode_session_id" : "<id>"               # play-mode session
#   }
#
# Background — operator-reported real failure (round-4):
# Unity-card-game autopilot shipped 9 PRs (#299-#307) labeled
# UX-visible without any Unity-MCP / Play-Mode capture. STATE.md and
# HISTORY.md repeatedly logged "MCP가 없어서 fresh QA 스크린샷 없음"
# while continuing to merge product PRs. The real cause wasn't MCP
# absence — it was that no validator demanded the evidence at all,
# so the agent self-excused and the operator dashboard had no signal.
#
# This validator is the engine-agnostic enforcement: it doesn't know
# what "Play Mode" means in your project — it only knows that a PR
# claiming shipped on a runtime-tagged task must carry SOME concrete
# artifact reference. The operator's project-specific
# `hooks/preflight-runtime-bridge.{ps1,sh}` decides what the artifact
# IS (Unity MCP capture, Selenium screenshot, e2e exit code, etc.).
#
# Initial deployment: soft mode (warning + structured FAILURES.jsonl
# row, no exit-1) so operators see false-positive rate before the
# gate becomes blocking. Hard-gate promotion in a future PR.
#
# Usage:
#   pwsh tools/Validate-RuntimeEvidence.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Validate-RuntimeEvidence.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — most recent shipped row carries adequate evidence, OR no
#       shipped row in tail, OR the row's task tags don't trigger
#       runtime requirement
#   1 — runtime-required shipped row has no `runtime_evidence` field
#       (hard mode)
#   0 — same drift but `-Soft` set (logged + exit clean)

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$TailLines = 20,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) {
  exit 0
}

$metricsPath  = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$backlogPath  = Join-Path $AutopilotRoot 'BACKLOG.md'
$statePath    = Join-Path $AutopilotRoot 'STATE.md'

if (-not (Test-Path -LiteralPath $metricsPath)) {
  # No METRICS.jsonl yet — runner has not produced any iter. Nothing
  # to validate.
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Round-5 F43: tag set is now engine-agnostic by default. Previously
# included Unity-specific tags (`[playmode]`, `[scene]`, `[battle]`,
# `[gameplay]`) which made non-Unity operators (Python, web, CLI)
# confused about whether the gate applied to them. Default tag list
# covers any project's runtime-touching surface; operator can extend
# via `.autopilot/config.json` `runtime_evidence_tags` array (their
# Unity / Unreal / Godot / domain-specific tags go there).
$runtimeTags = @(
  '[ui]', '[ux]', '[ux-visible]', '[runtime]',
  '[e2e]', '[smoke]'
)
$cfgPath = Join-Path $AutopilotRoot 'config.json'
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'runtime_evidence_tags') {
      $extra = @($cfg.runtime_evidence_tags)
      foreach ($t in $extra) {
        $tt = [string]$t
        if ($tt -and $runtimeTags -notcontains $tt) { $runtimeTags += $tt }
      }
    }
  } catch { }
}

# Evidence fields — at least one must be present + non-empty.
# Round-5 F43: renamed `play_mode_session_id` → `runtime_session_id`
# (the prior name implied Unity Play Mode specifically; the new name
# is project-neutral — covers Selenium/Playwright sessions, simulator
# runs, replay IDs, anything operators need to point at).
$evidenceFields = @('screenshot_path', 'smoke_exit_code', 'mcp_tool_response', 'runtime_session_id')

function Get-LastShippedRow {
  param([string]$Path, [int]$Count)
  try {
    # Force array context — when Get-Content returns one line, PowerShell
    # wraps as String not String[], and `$lines[0]` becomes the first
    # CHAR, not the line. `@()` keeps array semantics regardless of count.
    $lines = @(Get-Content -LiteralPath $Path -Tail $Count -ErrorAction Stop)
  } catch { return $null }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
      $row = $line | ConvertFrom-Json -ErrorAction Stop
      if ($row.outcome -eq 'shipped') { return $row }
    } catch { }
  }
  return $null
}

function Get-ActiveTaskTags {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $text = ''
  try { $text = [System.IO.File]::ReadAllText($Path) } catch { return @() }
  # Look at the first 80 lines for `[active]` / `[xxx]` tags. Operators
  # typically mark the active item with `[active]` plus a kind tag.
  $tags = New-Object System.Collections.Generic.HashSet[string]
  $lines = $text -split "`r?`n"
  for ($i = 0; $i -lt [Math]::Min($lines.Count, 80); $i++) {
    $matches = [regex]::Matches($lines[$i], '\[[a-z][a-z0-9-]*\]')
    foreach ($m in $matches) { [void]$tags.Add($m.Value.ToLowerInvariant()) }
  }
  return @($tags)
}

function Test-HasEvidence {
  param($Row)
  if (-not $Row) { return $false }
  if ($Row.PSObject.Properties.Name -notcontains 'runtime_evidence') { return $false }
  $ev = $Row.runtime_evidence
  if (-not $ev) { return $false }
  foreach ($f in $evidenceFields) {
    if ($ev.PSObject.Properties.Name -contains $f) {
      $val = $ev.$f
      if ($null -ne $val -and "$val".Trim().Length -gt 0) { return $true }
    }
  }
  return $false
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[runtime-evidence] failed to append: $_" }
}

# --- main -----------------------------------------------------------------

$lastRow = Get-LastShippedRow -Path $metricsPath -Count $TailLines
if (-not $lastRow) {
  # No shipped iter in tail — no claim to verify.
  exit 0
}

$activeTags = @(Get-ActiveTaskTags -Path $statePath)
if ($activeTags.Count -eq 0) {
  $activeTags = @(Get-ActiveTaskTags -Path $backlogPath)
}

$runtimeTagsLc = $runtimeTags | ForEach-Object { $_.ToLowerInvariant() }
$triggered = @()
foreach ($t in $activeTags) {
  if ($runtimeTagsLc -contains $t) { $triggered += $t }
}

if ($triggered.Count -eq 0) {
  Write-Host "[runtime-evidence] last shipped iter has no runtime-required tags (active tags: $($activeTags -join ' ')) — skip"
  exit 0
}

if (Test-HasEvidence -Row $lastRow) {
  Write-Host "[runtime-evidence] OK — shipped row carries runtime_evidence (triggered tags: $($triggered -join ' '))"
  exit 0
}

# --- drift: shipped + runtime tag + no evidence ---------------------------

$row = [ordered]@{
  ts            = (Get-Date -Format 'o')
  run_id        = if ($lastRow.PSObject.Properties.Name -contains 'run_id') { [string]$lastRow.run_id } else { '' }
  event         = 'runtime-evidence-missing'
  result        = 'shipped-without-evidence'
  outcome       = 'shipped'
  triggered_tags = ($triggered -join ' ')
  active_tags    = ($activeTags -join ' ')
  detail        = "An iter recorded outcome='shipped' on a task tagged with one of the runtime-required tags ($($triggered -join ', ')), but its METRICS row did not include a `runtime_evidence` field with any of: $($evidenceFields -join ', '). Operator's real Unity-card-game incident shipped 9 PRs in this state. See AUDIT.md row 81 (F39) and row 84 (F43 round-5 generalization) for context. To resolve: rerun the iter with a runtime-bridge probe (preflight-runtime-bridge.{ps1,sh}) producing one of the four artifact kinds, or re-tag the task as `[doc-only]` if the work was non-runtime."
}
$h = @{}
foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
Write-DriftRow -Path $failuresPath -Row $h

Write-Host ""
Write-Host "[runtime-evidence] EVIDENCE MISSING" -ForegroundColor Red
Write-Host "  shipped row run_id='$($row['run_id'])' triggered tags: $($triggered -join ' ')"
Write-Host "  expected: runtime_evidence.{$($evidenceFields -join ' | ')}"
Write-Host "  drift event appended to FAILURES.jsonl"

if ($Soft) {
  Write-Host ""
  Write-Host "[runtime-evidence] -Soft mode: drift logged, returning exit 0 so chain continues." -ForegroundColor Yellow
  exit 0
}

exit 1
