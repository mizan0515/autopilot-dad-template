# Validate-DoctorEmissions.ps1
#
# Round-7 F69 — doctor self-emission run_id contract (F57 closeout).
#
# Operator-reported pattern (round-6 F53 evidence): a project's local
# `doctor` extension performed an auto-repair pass that normalized 14
# backwards-going METRICS rows in one shot, emitting a synthetic row
# `metrics-time-regression-normalized` with `repair_count=14` — but
# without a `run_id`. The base template's `project.ps1 doctor`
# currently has no auto-repair path, so the template ships clean. The
# risk is asymmetric: the moment any operator extends doctor to
# auto-repair (a normal operation in mature projects), the round-4 F37
# correlation contract silently breaks for those synthetic rows. F38
# (ledger-consistency) and F40 (failures-logged) need run_id to
# correlate; without it, the gates can't tell which iter the repair
# belongs to.
#
# This validator scans the tail of METRICS.jsonl and FAILURES.jsonl
# for rows that look like they came from doctor (or any auto-repair
# pass) and flags any that are missing a run_id. Engine-agnostic by
# construction — the row classification is convention-based, not
# project-specific.
#
# Doctor-origin classification (a row matches if ANY is true):
#   - `source` field present and value is in the source-value list
#     (default: `doctor`, `auto-repair`)
#   - `event` field matches one of the event regex patterns
#     (default: `^doctor-`, `^auto-repair-`, `-normalized$`)
#   - `repair_count` field present (auto-repair signature)
#
# Drift kind:
#   `doctor-emission-missing-run-id` — row classified as doctor-origin
#                                       but run_id is missing or empty.
#
# Configuration (`.autopilot/config.json`, optional):
#   skip_doctor_emissions_check       : bool — true to skip entirely.
#   doctor_origin_extra_event_patterns: string[] — extra event regex.
#   doctor_origin_extra_source_values : string[] — extra `source` values.
#
# Soft-deployed (run with `-Soft`): drift is logged with run_id
# correlation but does not block the commit.
#
# Usage:
#   pwsh tools/Validate-DoctorEmissions.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no drift, OR -Soft, OR no METRICS+FAILURES, OR
#       skip_doctor_emissions_check.
#   1 — drift detected (hard mode only).

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$TailLines = 30,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$metricsPath  = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$cfgPath      = Join-Path $AutopilotRoot 'config.json'

if (-not (Test-Path -LiteralPath $metricsPath) -and -not (Test-Path -LiteralPath $failuresPath)) {
  Write-Host "[doctor-emissions] no METRICS or FAILURES yet (skip — fresh repo)"
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config (optional knobs) ---------------------------------------------

$skip = $false
$extraEventPatterns = @()
$extraSourceValues = @()
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'skip_doctor_emissions_check') {
      $skip = [bool]$cfg.skip_doctor_emissions_check
    }
    if ($cfg.PSObject.Properties.Name -contains 'doctor_origin_extra_event_patterns') {
      $extraEventPatterns = @($cfg.doctor_origin_extra_event_patterns | ForEach-Object { [string]$_ })
    }
    if ($cfg.PSObject.Properties.Name -contains 'doctor_origin_extra_source_values') {
      $extraSourceValues = @($cfg.doctor_origin_extra_source_values | ForEach-Object { [string]$_ })
    }
  } catch { }
}
if ($skip) { Write-Host "[doctor-emissions] skip_doctor_emissions_check=true — skipping"; exit 0 }

# --- classification rules ------------------------------------------------

$defaultSourceValues = @('doctor', 'auto-repair')
$defaultEventPatterns = @('^doctor-', '^auto-repair-', '-normalized$')
$sourceValues = @($defaultSourceValues + $extraSourceValues | Sort-Object -Unique)
$eventPatterns = @($defaultEventPatterns + $extraEventPatterns | Sort-Object -Unique)

# Validator-own emission events that the regex would otherwise match
# (this validator's own `doctor-emission-missing-run-id` starts with
# `doctor-`, which would self-trigger and classify previous drift rows
# as fresh doctor emissions). Any row whose event is in this list is
# explicitly NOT a doctor-origin row.
$validatorOwnEvents = @('doctor-emission-missing-run-id')

function Test-DoctorOrigin($row) {
  if ($row.PSObject.Properties.Name -contains 'event') {
    $ev = [string]$row.event
    if ($validatorOwnEvents -contains $ev) { return $false }
  }
  if ($row.PSObject.Properties.Name -contains 'repair_count') { return $true }
  if ($row.PSObject.Properties.Name -contains 'source') {
    $sv = [string]$row.source
    if ($sourceValues -contains $sv) { return $true }
  }
  if ($row.PSObject.Properties.Name -contains 'event') {
    $ev = [string]$row.event
    foreach ($pat in $eventPatterns) {
      if ($ev -match $pat) { return $true }
    }
  }
  return $false
}

# --- scan tails ----------------------------------------------------------

$drifts = @()

function Scan-File($path, $basename) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $tail = @(Get-Content -LiteralPath $path -Tail $TailLines -Encoding utf8)
  for ($i = 0; $i -lt $tail.Count; $i++) {
    $ln = $tail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
    } catch { continue }
    if (-not (Test-DoctorOrigin $r)) { continue }
    $hasRunId = $r.PSObject.Properties.Name -contains 'run_id'
    $rid = if ($hasRunId) { [string]$r.run_id } else { '' }
    if ($rid) { continue }
    # Capture the row's ts via raw regex (F48-class trap mitigation).
    $tsRaw = ''
    $m = [regex]::Match($ln, '"ts"\s*:\s*"([^"]+)"')
    if ($m.Success) { $tsRaw = $m.Groups[1].Value }
    $event = if ($r.PSObject.Properties.Name -contains 'event') { [string]$r.event } else { '' }
    $script:drifts += [pscustomobject]@{
      type     = 'doctor-emission-missing-run-id'
      file     = $basename
      ts_value = $tsRaw
      event    = $event
      detail   = "Row in $basename (event='$event', ts='$tsRaw') classified as doctor-origin (matched source/event pattern or carried repair_count) but has no run_id. Round-4 F37 contract requires every emission tagged with the iter's run_id; without it, F38 (ledger consistency) and F40 (failures-logged) cannot correlate. Set `\$AUTOPILOT_RUN_ID` before doctor's auto-repair appends, or include `run_id` in the synthetic row."
    }
  }
}

Scan-File $metricsPath  'METRICS.jsonl'
Scan-File $failuresPath 'FAILURES.jsonl'

# --- de-dup --------------------------------------------------------------

$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
}

function Test-RecentDriftEcho($file, $tsValue) {
  $tsRawPattern = '"ts_value"\s*:\s*"([^"]+)"'
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'doctor-emission-missing-run-id')) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'file' -and [string]$r.file -eq $file)) { continue }
      $m = [regex]::Match($ln, $tsRawPattern)
      if (-not $m.Success) { continue }
      if ($m.Groups[1].Value -eq $tsValue) { return $true }
    } catch { }
  }
  return $false
}

# --- emit ---------------------------------------------------------------

if ($drifts.Count -eq 0) {
  Write-Host "[doctor-emissions] OK — no doctor-origin rows missing run_id (last $TailLines lines per file)"
  exit 0
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[doctor-emissions] failed to append: $_" }
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$emitted = 0

foreach ($d in $drifts) {
  if (Test-RecentDriftEcho -file $d.file -tsValue $d.ts_value) {
    Write-Host ("  [{0}] {1} (ts={2}): same drift already in FAILURES tail — skipping" -f $d.type, $d.file, $d.ts_value)
    continue
  }
  $row = [ordered]@{
    ts          = (Get-Date -Format 'o')
    run_id      = $runId
    event       = 'doctor-emission-missing-run-id'
    result      = 'doctor-emission-missing-run-id'
    file        = $d.file
    ts_value    = $d.ts_value
    source_event = $d.event
    detail      = $d.detail
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emitted++
}

Write-Host ""
Write-Host "[doctor-emissions] DRIFT DETECTED ($($drifts.Count) total, $emitted emitted)" -ForegroundColor Red
foreach ($d in $drifts) {
  Write-Host ("  [{0}] {1} ts='{2}' event='{3}'" -f $d.type, $d.file, $d.ts_value, $d.event)
}

if ($Soft) {
  Write-Host ""
  Write-Host "[doctor-emissions] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
