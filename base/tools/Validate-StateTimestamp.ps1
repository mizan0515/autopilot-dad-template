# Validate-StateTimestamp.ps1
#
# Round-7 F64 — STATE.md self-reported timestamp invariant.
#
# Operator-reported real failure (round-4/5 audit, P1, retained from
# the Unity-card-game incident ledger): on iter 119 (2026-04-25),
# `STATE.md` contained `build_status_timestamp = 2026-04-25T14:45:00`
# while the file's filesystem mtime was 11:38:38 — a 2h+ self-reported
# time in the future relative to the actual on-disk write. The operator
# dashboard and any "last updated" panel reading STATE.md would then
# show a misleading future timestamp, and downstream stale-state
# detection (F44) had no signal to fire on.
#
# Universal: any project — Python service, Node CLI, Go daemon, web
# app, embedded firmware, game engine — that records its own state
# timestamps in STATE.md is vulnerable. The default template ships no
# timestamp fields, so well-behaved projects pass silently. Operators
# who add `build_status_timestamp`, `last_iter_ts`, `next_due_at`, or
# any other ISO8601-shaped field opt into the protection automatically.
#
# Invariant:
#   For every ISO8601 datetime string embedded in STATE.md
#   (full datetime — date-only strings are ignored), that timestamp
#   must NOT exceed:
#     - file's filesystem mtime + skewAllowance, AND
#     - validator's wall clock      + skewAllowance.
#
# `state-ts-future-of-mtime`     — self-reported time > actual write time.
# `state-ts-future-of-wallclock` — self-reported time > now (clock skew
#                                  or operator typo).
#
# Configuration (`.autopilot/config.json`, optional):
#   state_timestamp_skew_minutes : int — skew tolerance, default 5.
#   skip_state_timestamp_check   : bool — true to skip entirely.
#
# Soft-deployed (run with `-Soft`): drift is logged to FAILURES.jsonl
# with run_id correlation but does not block the commit.
#
# Usage:
#   pwsh tools/Validate-StateTimestamp.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no drift, OR -Soft set, OR not enough info (no STATE.md, no
#       parseable timestamps, skip_state_timestamp_check=true).
#   1 — drift detected (hard mode only).

param(
  [string]$AutopilotRoot = '.autopilot',
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$statePath    = Join-Path $AutopilotRoot 'STATE.md'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$cfgPath      = Join-Path $AutopilotRoot 'config.json'

if (-not (Test-Path -LiteralPath $statePath)) {
  Write-Host "[state-timestamp] no STATE.md at $statePath (OK on fresh repo)"
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config (optional knobs) ---------------------------------------------

$skewMinutes = 5
$skip = $false
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'state_timestamp_skew_minutes') {
      $val = $cfg.state_timestamp_skew_minutes
      if ($val -is [int] -and $val -ge 0) { $skewMinutes = [int]$val }
    }
    if ($cfg.PSObject.Properties.Name -contains 'skip_state_timestamp_check') {
      $skip = [bool]$cfg.skip_state_timestamp_check
    }
  } catch { }
}

if ($skip) {
  Write-Host "[state-timestamp] skip_state_timestamp_check=true in config — skipping"
  exit 0
}

$skew = [TimeSpan]::FromMinutes($skewMinutes)
$mtimeUtc = (Get-Item -LiteralPath $statePath).LastWriteTimeUtc
$nowUtc   = [DateTime]::UtcNow

# --- scan for ISO8601 timestamps -----------------------------------------

# Require the `T` separator so date-only strings (e.g. "2026-04-25" in
# operator-approval log lines) are ignored. Optional seconds, fractional
# seconds, and timezone offset (Z or ±HH:MM / ±HHMM).
$tsPattern = '\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?\b'

$rawText = [System.IO.File]::ReadAllText($statePath)
$lines   = $rawText -split "`r?`n"

$violations = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  $matches = [regex]::Matches($line, $tsPattern)
  foreach ($m in $matches) {
    $tsRaw = $m.Value
    $parsed = $null
    try {
      $dto = [DateTimeOffset]::Parse($tsRaw, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal)
      $parsed = $dto.UtcDateTime
    } catch { continue }

    if ($parsed -gt $mtimeUtc.Add($skew)) {
      $deltaMin = [int][math]::Round(($parsed - $mtimeUtc).TotalMinutes)
      $violations += [pscustomobject]@{
        type   = 'state-ts-future-of-mtime'
        lineno = ($i + 1)
        ts     = $tsRaw
        detail = "STATE.md line $($i+1) has timestamp '$tsRaw' which is $deltaMin min ahead of the file's mtime ($($mtimeUtc.ToString('o'))). Self-reported state time should not lead the actual write — operator dashboards reading the field will display a misleading future value."
      }
    }
    if ($parsed -gt $nowUtc.Add($skew)) {
      $deltaMin = [int][math]::Round(($parsed - $nowUtc).TotalMinutes)
      $violations += [pscustomobject]@{
        type   = 'state-ts-future-of-wallclock'
        lineno = ($i + 1)
        ts     = $tsRaw
        detail = "STATE.md line $($i+1) has timestamp '$tsRaw' which is $deltaMin min ahead of the validator's wall clock ($($nowUtc.ToString('o'))). Likely operator typo or clock skew — investigate before downstream gates trust the field."
      }
    }
  }
}

# --- de-dup against recent FAILURES tail (F62 pattern) -------------------

$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
}

function Test-RecentDriftEcho($result, $tsValue) {
  # Key on (result, ts-value). Lineno can shift as STATE.md grows; the
  # offending self-reported timestamp string is the stable identity.
  #
  # F48-class trap: ConvertFrom-Json auto-coerces ISO8601-shaped string
  # values to [datetime] objects. `[string]$r.ts_value` would then render
  # in the current culture (e.g. Korean: "2099. 1. 1. 오전 12:00:00"),
  # never matching the original "2099-01-01T00:00:00Z". Extract ts_value
  # via regex on the raw JSON line BEFORE coercion happens.
  $tsRawPattern = '"ts_value"\s*:\s*"([^"]+)"'
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'state-timestamp-drift')) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'result' -and [string]$r.result -eq $result)) { continue }
      $m = [regex]::Match($ln, $tsRawPattern)
      if (-not $m.Success) { continue }
      if ($m.Groups[1].Value -eq $tsValue) { return $true }
    } catch { }
  }
  return $false
}

# --- result ---------------------------------------------------------------

if ($violations.Count -eq 0) {
  Write-Host "[state-timestamp] OK — no future timestamps in STATE.md (skew tolerance ${skewMinutes}m)"
  exit 0
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[state-timestamp] failed to append: $_" }
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$emittedCount = 0

foreach ($v in $violations) {
  if (Test-RecentDriftEcho -result $v.type -tsValue $v.ts) {
    Write-Host ("  [{0}] line {1}: same drift already in FAILURES tail — skipping duplicate" -f $v.type, $v.lineno)
    continue
  }
  $row = [ordered]@{
    ts        = (Get-Date -Format 'o')
    run_id    = $runId
    event     = 'state-timestamp-drift'
    result    = $v.type
    lineno    = $v.lineno
    ts_value  = $v.ts
    detail    = $v.detail
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emittedCount++
}

Write-Host ""
Write-Host "[state-timestamp] DRIFT DETECTED ($($violations.Count) violation(s), $emittedCount emitted)" -ForegroundColor Red
foreach ($v in $violations) {
  Write-Host ("  [{0}] line {1}: ts='{2}'" -f $v.type, $v.lineno, $v.ts)
}
if ($emittedCount -gt 0) {
  Write-Host "  $emittedCount drift event(s) appended to FAILURES.jsonl"
}

if ($Soft) {
  Write-Host ""
  Write-Host "[state-timestamp] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
