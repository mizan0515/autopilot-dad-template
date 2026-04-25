# Validate-ConfigToolingDrift.ps1
#
# Round-7 F67 — config-vs-local-tooling drift gate (N4 closeout).
#
# When operators tune `.autopilot/config.json` AND modify the matching
# in-file default of a consumer script independently, the two values
# can drift apart silently. The dashboard reads the config; the
# validator reads its own default. They disagree, nobody notices.
#
# Example pattern: `stale_draft_pr_hours` lives both in config.json
# (operator-tunable) and as `$stalePrHours = 72` inside
# `tools/Validate-StaleStateDetection.ps1` (in-file default). If the
# operator drops the cap to 48 in config but also patches the
# validator default to 24, the two are mutually inconsistent.
# Future code paths that read either source will produce divergent
# behavior depending on which one fires first.
#
# Universal: applies to any project shape (Node service / Go daemon /
# Python CLI / web app / embedded firmware / game engine). The
# manifest at `.autopilot/config-tooling-contract.json` lists each
# (config_key, consumer_file) pair that the template considers
# "must agree when both are set."
#
# Manifest schema (v1):
#   {
#     "schema_version": 1,
#     "checks": [
#       {
#         "config_key":    "<key in config.json>",
#         "consumer_file": "<repo-relative path>",
#         "pattern":       "<regex; capture group 1 is the value>",
#         "kind":          "integer" | "string",
#         "detail":        "human description"
#       }
#     ]
#   }
#
# Drift kinds:
#   `consumer-file-missing`     — manifest names a file that doesn't
#                                  exist locally. Either operator
#                                  removed it intentionally or the
#                                  manifest is stale.
#   `pattern-no-match`          — file exists but the pattern didn't
#                                  match. Likely operator refactored
#                                  the in-file default away (e.g.
#                                  moved it into a helper). Manifest
#                                  needs updating.
#   `value-mismatch`            — config sets the key to one value;
#                                  consumer file's default is a
#                                  different value. The drift case.
#
# Configuration (`.autopilot/config.json`, optional):
#   skip_config_tooling_check : bool — true to skip entirely.
#   config_tooling_skip       : string[] — config_key entries to ignore.
#
# Soft-deployed (run with `-Soft`): drift is logged with run_id
# correlation but does not block the commit.
#
# Usage:
#   pwsh tools/Validate-ConfigToolingDrift.ps1 -RepoRoot . -Soft
#
# Exit codes:
#   0 — no drift, OR -Soft, OR no manifest, OR skip_config_tooling_check.
#   1 — drift detected (hard mode only).

param(
  [string]$RepoRoot = '.',
  [string]$AutopilotRoot = '',
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

$repoRootResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $AutopilotRoot) { $AutopilotRoot = Join-Path $repoRootResolved '.autopilot' }
if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$contractPath = Join-Path $AutopilotRoot 'config-tooling-contract.json'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$cfgPath      = Join-Path $AutopilotRoot 'config.json'

if (-not (Test-Path -LiteralPath $contractPath)) {
  Write-Host "[config-tooling] no manifest at $contractPath (skip)"
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config (optional knobs) ---------------------------------------------

$skip = $false
$skipKeys = @()
$cfg = $null
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'skip_config_tooling_check') {
      $skip = [bool]$cfg.skip_config_tooling_check
    }
    if ($cfg.PSObject.Properties.Name -contains 'config_tooling_skip') {
      $skipKeys = @($cfg.config_tooling_skip | ForEach-Object { [string]$_ })
    }
  } catch { }
}

if ($skip) {
  Write-Host "[config-tooling] skip_config_tooling_check=true in config — skipping"
  exit 0
}

# --- load manifest -------------------------------------------------------

try {
  $manifest = [System.IO.File]::ReadAllText($contractPath) | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Warning "[config-tooling] failed to parse $contractPath — skipping"
  exit 0
}

if (-not ($manifest.PSObject.Properties.Name -contains 'checks')) {
  Write-Host "[config-tooling] manifest has no .checks — skipping"
  exit 0
}

# --- run each check ------------------------------------------------------

$drifts = @()

foreach ($check in $manifest.checks) {
  $key = [string]$check.config_key
  if ($skipKeys -contains $key) { continue }
  $consumerRel = [string]$check.consumer_file
  $pattern = [string]$check.pattern
  $kind = if ($check.PSObject.Properties.Name -contains 'kind') { [string]$check.kind } else { 'integer' }
  $detail = if ($check.PSObject.Properties.Name -contains 'detail') { [string]$check.detail } else { '' }

  $consumerPath = Join-Path $repoRootResolved $consumerRel
  if (-not (Test-Path -LiteralPath $consumerPath)) {
    $drifts += [pscustomobject]@{
      type   = 'consumer-file-missing'
      key    = $key
      file   = $consumerRel
      detail = "Manifest pins '$key' to '$consumerRel' but the file does not exist. Either the operator removed it (add '$key' to config_tooling_skip in config.json) or the manifest is stale."
    }
    continue
  }

  $consumerText = [System.IO.File]::ReadAllText($consumerPath)
  $m = [regex]::Match($consumerText, $pattern)
  if (-not $m.Success -or $m.Groups.Count -lt 2) {
    $drifts += [pscustomobject]@{
      type   = 'pattern-no-match'
      key    = $key
      file   = $consumerRel
      detail = "Pattern for '$key' did not match in '$consumerRel'. Likely the operator refactored the in-file default; the manifest's pattern needs updating, or add '$key' to config_tooling_skip in config.json."
    }
    continue
  }

  $consumerValue = [string]$m.Groups[1].Value

  # If the operator hasn't set the key in config.json, the consumer
  # file's default is authoritative — no drift to flag.
  if (-not $cfg -or -not ($cfg.PSObject.Properties.Name -contains $key)) { continue }
  $rawConfigValue = $cfg.$key
  $configValue = $null
  if ($null -eq $rawConfigValue) { continue }

  switch ($kind) {
    'integer' {
      try { $configValue = [int]$rawConfigValue } catch { continue }
      $consumerInt = $null
      if ([int]::TryParse($consumerValue, [ref]$consumerInt)) {
        if ($configValue -ne $consumerInt) {
          $drifts += [pscustomobject]@{
            type   = 'value-mismatch'
            key    = $key
            file   = $consumerRel
            config_value   = $configValue
            consumer_value = $consumerInt
            detail = "config.json '$key' = $configValue, but '$consumerRel' carries default = $consumerInt. The two should agree when both are set; one source will silently win at runtime depending on the code path. Re-sync to a single value, or add '$key' to config_tooling_skip in config.json once the divergence is intentional. ($detail)"
          }
        }
      }
    }
    default {
      if ([string]$configValue -ne [string]$rawConfigValue) { $configValue = [string]$rawConfigValue }
      if ([string]$rawConfigValue -ne $consumerValue) {
        $drifts += [pscustomobject]@{
          type   = 'value-mismatch'
          key    = $key
          file   = $consumerRel
          config_value   = [string]$rawConfigValue
          consumer_value = $consumerValue
          detail = "config.json '$key' = '$rawConfigValue', but '$consumerRel' carries default = '$consumerValue'. ($detail)"
        }
      }
    }
  }
}

# --- de-dup against recent FAILURES tail (F62 pattern) -------------------

$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
}

function Test-RecentDriftEcho($result, $key) {
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'config-tooling-drift')) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'result' -and [string]$r.result -eq $result)) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'key' -and [string]$r.key -eq $key)) { continue }
      return $true
    } catch { }
  }
  return $false
}

# --- emit ----------------------------------------------------------------

if ($drifts.Count -eq 0) {
  $checkCount = if ($manifest.checks) { @($manifest.checks).Count } else { 0 }
  Write-Host "[config-tooling] OK — $checkCount check(s) pass"
  exit 0
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[config-tooling] failed to append: $_" }
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$emitted = 0

foreach ($d in $drifts) {
  if (Test-RecentDriftEcho -result $d.type -key $d.key) {
    Write-Host ("  [{0}] {1}: same drift already in FAILURES tail — skipping duplicate" -f $d.type, $d.key)
    continue
  }
  $row = [ordered]@{
    ts     = (Get-Date -Format 'o')
    run_id = $runId
    event  = 'config-tooling-drift'
    result = $d.type
    key    = $d.key
    file   = $d.file
    detail = $d.detail
  }
  if ($d.PSObject.Properties.Name -contains 'config_value') {
    $row['config_value']   = $d.config_value
    $row['consumer_value'] = $d.consumer_value
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emitted++
}

Write-Host ""
Write-Host "[config-tooling] DRIFT DETECTED ($($drifts.Count) total, $emitted emitted)" -ForegroundColor Red
foreach ($d in $drifts) {
  Write-Host ("  [{0}] {1} ({2})" -f $d.type, $d.key, $d.file)
}

if ($Soft) {
  Write-Host ""
  Write-Host "[config-tooling] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
