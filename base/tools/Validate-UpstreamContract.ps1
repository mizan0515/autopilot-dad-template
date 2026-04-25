# Validate-UpstreamContract.ps1
#
# Round-7 F65 — upstream-contract tripwire (R6).
#
# Operator-reported real failure pattern: when an operator copies a
# template validator (e.g. the 780-line `Validate-DadPacket.ps1`) into
# their own project for local customization, they sometimes bring only
# part of the file across — half the invariants quietly disappear and
# the truncated fork still passes its own pre-commit because the
# missing checks are simply absent. The truncation is silent; the
# project's gate coverage degrades without surfacing.
#
# This validator catches the truncation by comparing each local
# `tools/Validate-*.ps1` against the SHA256 + line-count manifest
# (`.autopilot/upstream-contract.json`) that the template ships at
# apply time. Three drift kinds:
#
#   `validator-missing`        — manifest names a validator the local
#                                project no longer has at all (operator
#                                may have deleted it intentionally; soft
#                                emit so the dashboard can flag it).
#   `truncated-fork-suspected` — local file's SHA differs from manifest
#                                AND line count is below
#                                `truncated_fork_threshold * manifest`
#                                (default 0.5). The R6 case.
#   `local-fork-detected`      — SHA differs but line count is at or
#                                above the threshold. Informational only
#                                by default; opt-in via config.
#
# Universal: applies to any project shape (Node service, Go daemon,
# Python CLI, web app, embedded firmware, game engine) that received
# the manifest through apply.ps1. Projects that intentionally diverge
# can opt out per-validator via `upstream_contract_skip` in
# config.json.
#
# Configuration (`.autopilot/config.json`, optional):
#   skip_upstream_contract_check : bool — true to skip entirely.
#   truncated_fork_threshold     : float — default 0.5. Local
#                                  line_count below
#                                  manifest.line_count * threshold
#                                  is flagged as truncation.
#   upstream_contract_skip       : string[] — validator basenames to
#                                  ignore (e.g. ["Validate-Foo.ps1"]).
#   report_local_forks           : bool — default false. When true,
#                                  local-fork-detected drift also
#                                  appends a FAILURES.jsonl row.
#
# Soft-deployed (run with `-Soft`): drift is logged with run_id
# correlation but does not block the commit.
#
# Usage:
#   pwsh tools/Validate-UpstreamContract.ps1 -RepoRoot . -Soft
#
# Exit codes:
#   0 — no drift, OR -Soft, OR no manifest, OR skip_upstream_contract_check.
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

$contractPath = Join-Path $AutopilotRoot 'upstream-contract.json'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$cfgPath      = Join-Path $AutopilotRoot 'config.json'
$toolsDir     = Join-Path $repoRootResolved 'tools'

if (-not (Test-Path -LiteralPath $contractPath)) {
  Write-Host "[upstream-contract] no manifest at $contractPath (skip — run Generate-UpstreamContract.ps1 to create one)"
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config (optional knobs) ---------------------------------------------

$skip = $false
$threshold = 0.5
$skipList = @()
$reportLocalForks = $false
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'skip_upstream_contract_check') {
      $skip = [bool]$cfg.skip_upstream_contract_check
    }
    if ($cfg.PSObject.Properties.Name -contains 'truncated_fork_threshold') {
      $val = $cfg.truncated_fork_threshold
      if ($val -is [double] -or $val -is [float] -or $val -is [int]) {
        $t = [double]$val
        if ($t -gt 0.0 -and $t -lt 1.0) { $threshold = $t }
      }
    }
    if ($cfg.PSObject.Properties.Name -contains 'upstream_contract_skip') {
      $skipList = @($cfg.upstream_contract_skip | ForEach-Object { [string]$_ })
    }
    if ($cfg.PSObject.Properties.Name -contains 'report_local_forks') {
      $reportLocalForks = [bool]$cfg.report_local_forks
    }
  } catch { }
}

if ($skip) {
  Write-Host "[upstream-contract] skip_upstream_contract_check=true in config — skipping"
  exit 0
}

# --- load manifest -------------------------------------------------------

try {
  $manifest = [System.IO.File]::ReadAllText($contractPath) | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Warning "[upstream-contract] failed to parse $contractPath — skipping"
  exit 0
}

if (-not ($manifest.PSObject.Properties.Name -contains 'validators')) {
  Write-Warning "[upstream-contract] manifest has no .validators field — skipping"
  exit 0
}

# --- compare each manifest entry against local tools/ --------------------

$drifts = @()

foreach ($prop in $manifest.validators.PSObject.Properties) {
  $name = $prop.Name
  if ($skipList -contains $name) { continue }
  $expected = $prop.Value
  $expectedSha = [string]$expected.sha256
  $expectedLines = [int]$expected.line_count
  $expectedBytes = [int]$expected.byte_size
  $localPath = Join-Path $toolsDir $name

  if (-not (Test-Path -LiteralPath $localPath)) {
    $drifts += [pscustomobject]@{
      type            = 'validator-missing'
      validator       = $name
      expected_sha    = $expectedSha
      expected_lines  = $expectedLines
      local_lines     = 0
      detail          = "Manifest names '$name' (line_count=$expectedLines) but tools/$name does not exist locally. Either the validator was intentionally removed (add it to upstream_contract_skip in config.json) or the local checkout is out of sync with the template."
      severity        = 'soft'
    }
    continue
  }

  $localBytes = [System.IO.File]::ReadAllBytes($localPath)
  $localSha = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash.ToLower()
  if ($localSha -eq $expectedSha) { continue }

  $localText = [System.Text.Encoding]::UTF8.GetString($localBytes)
  $newlineCount = ([regex]::Matches($localText, "`n")).Count
  $endsWithLf = $localText.EndsWith("`n")
  $localLines = if ($endsWithLf) { $newlineCount } else { $newlineCount + 1 }

  $minAllowed = [int][math]::Floor($expectedLines * $threshold)
  if ($localLines -lt $minAllowed) {
    $drifts += [pscustomobject]@{
      type            = 'truncated-fork-suspected'
      validator       = $name
      expected_sha    = $expectedSha
      expected_lines  = $expectedLines
      local_lines     = $localLines
      detail          = "Local tools/$name has $localLines line(s) but manifest expected $expectedLines (threshold=$threshold → min=$minAllowed). The local file is suspected of being a truncated fork — invariants from the upstream validator may be silently absent from this project's pre-commit chain. Re-sync from the template, or fork deliberately and add '$name' to upstream_contract_skip in config.json once the divergence is intentional."
      severity        = 'soft'
    }
  } else {
    $drifts += [pscustomobject]@{
      type            = 'local-fork-detected'
      validator       = $name
      expected_sha    = $expectedSha
      expected_lines  = $expectedLines
      local_lines     = $localLines
      detail          = "Local tools/$name SHA differs from manifest (local_lines=$localLines, manifest_lines=$expectedLines). Likely an intentional local fork. Set report_local_forks=true in config.json to log these as FAILURES rows; otherwise informational only."
      severity        = 'info'
    }
  }
}

# --- de-dup against recent FAILURES tail (F62 pattern) -------------------

$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
}

function Test-RecentDriftEcho($result, $validator) {
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'upstream-contract-drift')) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'result' -and [string]$r.result -eq $result)) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'validator' -and [string]$r.validator -eq $validator)) { continue }
      return $true
    } catch { }
  }
  return $false
}

# --- emit ----------------------------------------------------------------

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[upstream-contract] failed to append: $_" }
}

if ($drifts.Count -eq 0) {
  Write-Host "[upstream-contract] OK — all $($manifest.validators.PSObject.Properties.Name.Count) validator(s) match the manifest"
  exit 0
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$emittedCount = 0
$hardCount = 0

foreach ($d in $drifts) {
  if ($d.severity -eq 'info' -and -not $reportLocalForks) {
    Write-Host ("  [info] {0}: {1}" -f $d.type, $d.validator)
    continue
  }
  if (Test-RecentDriftEcho -result $d.type -validator $d.validator) {
    Write-Host ("  [{0}] {1}: same drift already in FAILURES tail — skipping duplicate" -f $d.type, $d.validator)
    continue
  }
  $row = [ordered]@{
    ts             = (Get-Date -Format 'o')
    run_id         = $runId
    event          = 'upstream-contract-drift'
    result         = $d.type
    validator      = $d.validator
    expected_lines = $d.expected_lines
    local_lines    = $d.local_lines
    expected_sha   = $d.expected_sha
    detail         = $d.detail
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emittedCount++
  if ($d.severity -ne 'info') { $hardCount++ }
}

Write-Host ""
Write-Host "[upstream-contract] DRIFT DETECTED ($($drifts.Count) total, $emittedCount emitted)" -ForegroundColor Red
foreach ($d in $drifts) {
  Write-Host ("  [{0}] {1}: local_lines={2} expected={3}" -f $d.type, $d.validator, $d.local_lines, $d.expected_lines)
}

if ($Soft) {
  Write-Host ""
  Write-Host "[upstream-contract] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

if ($hardCount -gt 0) { exit 1 }
exit 0
