# Validate-LongYellowState.ps1
#
# Round-7 F68 — long-yellow state aging gate (N8 closeout).
#
# Recoverable-but-not-green ("yellow") states tend to ossify: an
# operator marks a field as `ok_with_historical_drift` /
# `stale_but_recoverable` / `degraded` planning to revisit, then
# never does. The dashboard never says "RED", so nothing escalates,
# and the project quietly normalizes a partial-failure mode.
#
# This validator reads the last N+1 rows of METRICS.jsonl and, per
# manifest entry, checks: do all of those rows carry the same
# `field` value AND is that value in `yellow_values`? If so, emit
# `long-yellow-state-stuck` so the operator dashboard panel (F47
# `gate_signals`) can surface it.
#
# Universal: applies to any project shape (Node service / Go daemon /
# Python CLI / web app / embedded firmware / game engine). The
# template ships an empty `checks` array — yellow vocabulary is
# project-specific, so operators register their own (e.g. Node:
# `service_health: degraded`; Go: `dependency_status: outdated`;
# Web: `bundle_status: stale_in_cache`; embedded: `flash_state:
# partially_provisioned`).
#
# Manifest schema (v1):
#   {
#     "schema_version": 1,
#     "checks": [
#       {
#         "field":               "<METRICS row key>",
#         "yellow_values":       ["<string>", ...],
#         "max_unchanged_iters": <int>,
#         "detail":              "<human description>"
#       }
#     ]
#   }
#
# Drift kind:
#   `long-yellow-state-stuck` — last (max_unchanged_iters + 1) rows
#                                all share the same yellow value.
#
# Configuration (`.autopilot/config.json`, optional):
#   skip_long_yellow_check : bool — true to skip entirely.
#   long_yellow_skip       : string[] — field names to ignore.
#
# Soft-deployed (run with `-Soft`): drift is logged with run_id
# correlation but does not block the commit.
#
# Usage:
#   pwsh tools/Validate-LongYellowState.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no drift, OR -Soft, OR no manifest, OR empty checks, OR
#       skip_long_yellow_check, OR insufficient METRICS rows.
#   1 — drift detected (hard mode only).

param(
  [string]$AutopilotRoot = '.autopilot',
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$contractPath = Join-Path $AutopilotRoot 'long-yellow-contract.json'
$metricsPath  = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$cfgPath      = Join-Path $AutopilotRoot 'config.json'

if (-not (Test-Path -LiteralPath $contractPath)) {
  Write-Host "[long-yellow] no manifest at $contractPath (skip)"
  exit 0
}
if (-not (Test-Path -LiteralPath $metricsPath)) {
  Write-Host "[long-yellow] no METRICS at $metricsPath (skip — fresh repo)"
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config (optional knobs) ---------------------------------------------

$skip = $false
$skipFields = @()
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'skip_long_yellow_check') {
      $skip = [bool]$cfg.skip_long_yellow_check
    }
    if ($cfg.PSObject.Properties.Name -contains 'long_yellow_skip') {
      $skipFields = @($cfg.long_yellow_skip | ForEach-Object { [string]$_ })
    }
  } catch { }
}
if ($skip) { Write-Host "[long-yellow] skip_long_yellow_check=true — skipping"; exit 0 }

# --- load manifest -------------------------------------------------------

try {
  $manifest = [System.IO.File]::ReadAllText($contractPath) | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Warning "[long-yellow] failed to parse $contractPath — skipping"
  exit 0
}

if (-not ($manifest.PSObject.Properties.Name -contains 'checks')) { exit 0 }
$checks = @($manifest.checks)
if ($checks.Count -eq 0) {
  Write-Host "[long-yellow] manifest has empty checks — register fields to age out"
  exit 0
}

# --- per-check evaluation ------------------------------------------------

$drifts = @()

foreach ($check in $checks) {
  $field = [string]$check.field
  if (-not $field) { continue }
  if ($skipFields -contains $field) { continue }
  $yellowValues = @($check.yellow_values | ForEach-Object { [string]$_ })
  $maxUnchanged = if ($check.PSObject.Properties.Name -contains 'max_unchanged_iters') { [int]$check.max_unchanged_iters } else { 5 }
  if ($maxUnchanged -lt 1) { continue }
  $detailText = if ($check.PSObject.Properties.Name -contains 'detail') { [string]$check.detail } else { '' }

  $needed = $maxUnchanged + 1
  $tail = @(Get-Content -LiteralPath $metricsPath -Tail $needed -Encoding utf8)
  if ($tail.Count -lt $needed) { continue }

  $values = @()
  $iters = @()
  $ok = $true
  foreach ($ln in $tail) {
    if ([string]::IsNullOrWhiteSpace($ln)) { $ok = $false; break }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains $field)) { $ok = $false; break }
      $v = $r.$field
      $values += [string]$v
      if ($r.PSObject.Properties.Name -contains 'iter') { $iters += [string]$r.iter } else { $iters += '?' }
    } catch { $ok = $false; break }
  }
  if (-not $ok) { continue }

  $first = $values[0]
  $allSame = $true
  for ($i = 1; $i -lt $values.Count; $i++) {
    if ($values[$i] -ne $first) { $allSame = $false; break }
  }
  if (-not $allSame) { continue }
  if (-not ($yellowValues -contains $first)) { continue }

  $drifts += [pscustomobject]@{
    type           = 'long-yellow-state-stuck'
    field          = $field
    value          = $first
    iters          = ($iters -join ',')
    streak_length  = $values.Count
    detail         = "METRICS field '$field' has carried the yellow value '$first' for the last $($values.Count) consecutive rows (iters: $($iters -join ', ')). Investigate whether the underlying condition can be resolved or whether the project should escalate. ($detailText)"
  }
}

# --- de-dup --------------------------------------------------------------

$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
}

function Test-RecentDriftEcho($field, $value, $iters) {
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'long-yellow-state-stuck')) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'field' -and [string]$r.field -eq $field)) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'value' -and [string]$r.value -eq $value)) { continue }
      # Same-window check: if the previous emission's iters list shares
      # ANY iter with the current window, this is the same yellow streak
      # and we should not re-emit. New iters causing the streak to
      # advance forward (without breaking) thus emit at most once until
      # the streak resets.
      if ($r.PSObject.Properties.Name -contains 'iters') {
        $prevIters = ([string]$r.iters) -split ',' | ForEach-Object { $_.Trim() }
        $currIters = ($iters -split ',') | ForEach-Object { $_.Trim() }
        foreach ($pi in $prevIters) {
          if ($currIters -contains $pi) { return $true }
        }
      } else {
        return $true
      }
    } catch { }
  }
  return $false
}

# --- emit ---------------------------------------------------------------

if ($drifts.Count -eq 0) {
  Write-Host "[long-yellow] OK — $($checks.Count) check(s), no stuck states"
  exit 0
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[long-yellow] failed to append: $_" }
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$emitted = 0

foreach ($d in $drifts) {
  if (Test-RecentDriftEcho -field $d.field -value $d.value -iters $d.iters) {
    Write-Host ("  [{0}] {1}={2} (iters {3}): same streak already in FAILURES tail — skipping" -f $d.type, $d.field, $d.value, $d.iters)
    continue
  }
  $row = [ordered]@{
    ts             = (Get-Date -Format 'o')
    run_id         = $runId
    event          = 'long-yellow-state-stuck'
    result         = 'long-yellow-state-stuck'
    field          = $d.field
    value          = $d.value
    iters          = $d.iters
    streak_length  = $d.streak_length
    detail         = $d.detail
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emitted++
}

Write-Host ""
Write-Host "[long-yellow] STUCK STATE(S) DETECTED ($($drifts.Count) total, $emitted emitted)" -ForegroundColor Red
foreach ($d in $drifts) {
  Write-Host ("  [{0}] {1}={2} streak={3} (iters {4})" -f $d.type, $d.field, $d.value, $d.streak_length, $d.iters)
}

if ($Soft) {
  Write-Host ""
  Write-Host "[long-yellow] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
