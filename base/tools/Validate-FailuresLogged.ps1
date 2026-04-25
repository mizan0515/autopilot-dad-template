# Validate-FailuresLogged.ps1
#
# Round-4 F40 — structured FAILURES.jsonl logging contract.
#
# When the agent's most recent METRICS.jsonl row records a non-clean
# outcome (anything except `shipped` / `doc-only` / `idle-upkeep` /
# `bootstrap`), the corresponding `run_id` MUST also appear in the
# tail of FAILURES.jsonl with a structured `event=outcome-non-clean`
# (or any other concrete failure event).
#
# Background — operator-reported real failure (round-4):
# `FAILURES.jsonl` was *empty* on Unity-card-game even though real
# operational failures existed (runner stale at retained-dirty for
# 15 hours, draft PR #292 languishing, Unity-MCP evidence missing
# across 9 PRs, relay reports blocked). The cause was that nothing
# required the agent to write structured failure rows — METRICS could
# carry `outcome=excluded` or `outcome=blocked` and there'd be no
# FAILURES counterpart, so downstream tools that scan FAILURES had
# nothing to triage.
#
# This validator pairs with the new PROMPT.md "Structured failure
# logging" section, which tells the agent: any outcome outside the
# clean set MUST be accompanied by a FAILURES row sharing the same
# run_id (F37 correlation key).
#
# Clean outcomes (no FAILURES row required):
#   shipped, doc-only, idle-upkeep, bootstrap
#
# Non-clean outcomes (FAILURES row required):
#   excluded, blocked, escalated, partial, deferred, error,
#   aborted, halted, abandoned, fast-aborted, recovery, * (anything else)
#
# Initial deployment: soft mode (logged + exit clean) so operators
# observe false-positive rate before the gate becomes blocking.
#
# Usage:
#   pwsh tools/Validate-FailuresLogged.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Validate-FailuresLogged.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — last METRICS row has clean outcome, OR non-clean outcome
#       with matching FAILURES row, OR no METRICS yet
#   1 — non-clean outcome but no matching FAILURES row (hard mode)
#   0 — same drift but `-Soft` set

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$TailLines = 20,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$metricsPath  = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

if (-not (Test-Path -LiteralPath $metricsPath)) { exit 0 }

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Outcomes that don't require a FAILURES row.
$cleanOutcomes = @('shipped', 'doc-only', 'idle-upkeep', 'bootstrap')

function Get-LastRow {
  param([string]$Path, [int]$Count)
  try {
    # Round-4 F39 lesson: force array context — single-line files
    # otherwise return String not String[] and `$lines[0]` becomes
    # the first CHAR.
    $lines = @(Get-Content -LiteralPath $Path -Tail $Count -ErrorAction Stop)
  } catch { return $null }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { return ($line | ConvertFrom-Json -ErrorAction Stop) } catch { }
  }
  return $null
}

function Test-FailuresContainsRunId {
  param([string]$Path, [string]$RunId, [int]$Count)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $lines = @(Get-Content -LiteralPath $Path -Tail $Count -ErrorAction Stop)
  } catch { return $false }
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
      $row = $line | ConvertFrom-Json -ErrorAction Stop
      if ($row.PSObject.Properties.Name -contains 'run_id' -and $row.run_id -eq $RunId) {
        return $true
      }
    } catch { }
  }
  return $false
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[failures-logged] failed to append: $_" }
}

# --- main -----------------------------------------------------------------

$lastRow = Get-LastRow -Path $metricsPath -Count $TailLines
if (-not $lastRow) {
  exit 0
}

$outcome = [string]$lastRow.outcome
$runId   = if ($lastRow.PSObject.Properties.Name -contains 'run_id') { [string]$lastRow.run_id } else { '' }

if (-not $outcome) {
  Write-Host "[failures-logged] last METRICS row has no `outcome` field — skip"
  exit 0
}

if ($cleanOutcomes -contains $outcome) {
  Write-Host "[failures-logged] OK — last outcome='$outcome' (clean), no FAILURES row required"
  exit 0
}

if (-not $runId) {
  # Pre-F37 row without run_id; we have no correlation key. Inform but
  # don't drift-flag (would false-positive on legacy data).
  Write-Host "[failures-logged] last METRICS row outcome='$outcome' has no run_id (pre-F37 row?) — cannot correlate, skipping"
  exit 0
}

$matched = Test-FailuresContainsRunId -Path $failuresPath -RunId $runId -Count ($TailLines * 2)

if ($matched) {
  Write-Host "[failures-logged] OK — outcome='$outcome' has matching FAILURES row with run_id='$runId'"
  exit 0
}

# --- drift: non-clean outcome but no FAILURES row -------------------------

$row = [ordered]@{
  ts       = (Get-Date -Format 'o')
  run_id   = $runId
  event    = 'failures-row-missing'
  result   = 'non-clean-outcome-without-failures-row'
  outcome  = $outcome
  detail   = "An iter recorded outcome='$outcome' (non-clean) in METRICS.jsonl, but no row with run_id='$runId' was found in the last $($TailLines * 2) FAILURES.jsonl entries. Per the structured-failure-logging contract (PROMPT.md, F40), every non-clean outcome must be accompanied by a FAILURES row sharing the same run_id, with at least an `event` field describing what went wrong. Operator's real Unity-card-game audit found FAILURES.jsonl was empty despite multiple real failures (runner stale, draft PR languishing, MCP unobserved); F40 closes that gap. To resolve: append the missing row, or relabel outcome to one of {shipped, doc-only, idle-upkeep, bootstrap}."
}
$h = @{}
foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
Write-DriftRow -Path $failuresPath -Row $h

Write-Host ""
Write-Host "[failures-logged] STRUCTURED FAILURE MISSING" -ForegroundColor Red
Write-Host "  METRICS row outcome='$outcome' run_id='$runId'"
Write-Host "  expected: a FAILURES.jsonl row with run_id='$runId' and a concrete event"
Write-Host "  found:    none in last $($TailLines * 2) lines"
Write-Host "  drift event appended to FAILURES.jsonl with run_id='$runId'"

if ($Soft) {
  Write-Host ""
  Write-Host "[failures-logged] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
