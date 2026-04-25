# base/tools/Validate-Metrics.ps1
#
# Line-by-line validator for .autopilot/METRICS.jsonl. Enforces:
#   HARD (exit 1 on failure):
#   - each line is valid UTF-8 JSON
#   - Tier-1 required fields present: iter, ts, outcome, duration_s
#   - ts parses as ISO-8601
#   - ts strictly non-decreasing within the file (F53)
#   - ts not in the future relative to wall clock w/ 5min skew (F53)
#
#   SOFT (logs to FAILURES.jsonl, returns exit 0):
#   - extension keys without the project's slug prefix (F54/F66)
#   - any key matching `^relay_` when relay_repo_path is empty (F66)
#
# Exit 0 = no hard failures. Exit 1 + prints offending line numbers if
# any hard check fails.
#
# Usage:
#   pwsh tools/Validate-Metrics.ps1 -Path .autopilot/METRICS.jsonl
#       — auto-derives prefix from .autopilot/config.json `project_slug`
#         (set by apply.ps1) and emits soft drift if extension keys
#         don't match.
#   pwsh tools/Validate-Metrics.ps1 -Path .autopilot/METRICS.jsonl -ProjectPrefix myslug
#       — explicit override. Implies hard mode (exit 1 on prefix
#         mismatch) for backward compatibility with pre-F66 callers.

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [string]$ProjectPrefix,
  [string]$AutopilotRoot = ''
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Path)) {
  Write-Host "[validate-metrics] no METRICS file at $Path (OK on fresh repo)"
  exit 0
}

# Round-7 F66: auto-derive ProjectPrefix from config.json `project_slug`
# (apply.ps1 writes this). When auto-derived, prefix violations are SOFT
# (logged to FAILURES.jsonl, no exit 1). When -ProjectPrefix is passed
# explicitly, prefix violations are HARD (legacy callers).
$prefixIsExplicit = [bool]$ProjectPrefix
$relayRepoPath = ''
if (-not $AutopilotRoot) {
  # Default: sibling of $Path's parent.
  $pathParent = Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path
  $AutopilotRoot = $pathParent
}
$cfgPath = Join-Path $AutopilotRoot 'config.json'
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if (-not $prefixIsExplicit -and $cfg.PSObject.Properties.Name -contains 'project_slug') {
      $autoSlug = [string]$cfg.project_slug
      if ($autoSlug) { $ProjectPrefix = $autoSlug }
    }
    if ($cfg.PSObject.Properties.Name -contains 'relay_repo_path') {
      $relayRepoPath = [string]$cfg.relay_repo_path
    }
  } catch { }
}

$required = @('iter', 'ts', 'outcome', 'duration_s')
# Universal extension keys that may appear without a slug prefix. These
# are explicitly engine-agnostic — any project shape (Node service, Go
# daemon, Python web, embedded firmware, game engine) can use them.
# `editmode_tests` was previously here but was removed in F66 because it
# bakes a single-engine concept (Unity Edit Mode) into a "universal"
# allowlist. Engine-specific counters belong in `<slug>_*` extension
# keys, where Validate-Metrics can lint them without false universality.
$universalExtensionKeys = @('tokens','pr_url','mode','status','files_read','bash_calls',
                            'mcp_calls','commits','prs','merged','screenshots',
                            'budget_exceeded','cache_read_ratio','run_id','runtime_evidence',
                            'token_economy','session_id','retry_count','outcome_reason')
# Round-7 F66: any key matching `^relay_` is reserved for the relay
# broker's Tier-3 schema. A non-relay project (relay_repo_path empty)
# emitting a relay_* key is a contract leak — soft drift.
$relayPrefix = '^relay_'

$lineNo = 0
$problems = @()
# Round-6 F53 — METRICS time-monotonicity gate.
#
# Real failures observed on `D:\Unity\card game\.autopilot\` (iter 119,
# 2026-04-25): doctor's auto-repair normalized 14 backwards-going rows
# in one shot (`metrics-time-regression-normalized`, repair_count=14),
# AND a separate row showed `build_status_timestamp = 2026-04-25T14:45:00`
# while the file mtime was 11:38:38 (2h+ in the future).
#
# Universal: any append-only telemetry log that's read by dashboards or
# token-economy gates (F45 reads tail-N to compute window) is corrupted
# by ts regressions. This applies to Python/web/CLI/embedded as much as
# to Unity-shaped projects.
#
# Two checks:
#   (1) `ts` strictly non-decreasing line-to-line (within the same file).
#   (2) `ts` not in the future relative to the validator's wall clock
#       (with a generous 5-minute skew allowance for clock drift).
$prevTs = $null
$prevLineNo = 0
$nowUtc = [DateTime]::UtcNow
$futureSkewAllowance = [TimeSpan]::FromMinutes(5)
# Round-7 F66: soft-drift accumulator for prefix / reserved-key issues.
# Hard issues (JSON validity, Tier-1 missing, ts regression) still go to
# $problems and exit 1.
$script:softDrifts = @()

Get-Content -LiteralPath $Path -Encoding utf8 | ForEach-Object {
  $lineNo++
  $raw = $_.Trim()
  if (-not $raw) { return }
  try {
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    $problems += "L${lineNo}: invalid JSON — $_"
    return
  }

  foreach ($k in $required) {
    if ($null -eq $obj.$k) { $problems += "L${lineNo}: missing required key '$k'" }
  }

  if ($obj.ts) {
    # Capture the original ISO string from the raw line BEFORE ConvertFrom-Json
    # coerces it to [datetime] (which would localize it on rendering — the
    # same F48-class trap). Fall back to $obj.ts ToString() if extraction fails.
    $tsRaw = $null
    $tsRawMatch = [regex]::Match($raw, '"ts"\s*:\s*"([^"]+)"')
    if ($tsRawMatch.Success) { $tsRaw = $tsRawMatch.Groups[1].Value } else { $tsRaw = [string]$obj.ts }

    $parsedTs = $null
    try {
      # Use DateTimeOffset to keep timezone awareness; convert to UTC for
      # comparison. AssumeUniversal handles ts strings without explicit offset.
      $parsedDto = [DateTimeOffset]::Parse($tsRaw, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal)
      $parsedTs = $parsedDto.UtcDateTime
    } catch {
      $problems += "L${lineNo}: ts='$tsRaw' does not parse as ISO-8601"
    }

    if ($null -ne $parsedTs) {
      # F53 (1) — non-decreasing within the file.
      if ($null -ne $prevTs -and $parsedTs -lt $prevTs) {
        $problems += "L${lineNo}: ts='$tsRaw' regresses from L${prevLineNo} ts (time monotonicity violated)"
      } else {
        $prevTs = $parsedTs
        $prevLineNo = $lineNo
      }
      # F53 (2) — not in the future.
      if ($parsedTs -gt $nowUtc.Add($futureSkewAllowance)) {
        $problems += "L${lineNo}: ts='$tsRaw' is in the future relative to wall clock (>5min skew)"
      }
    }
  }

  if ($ProjectPrefix) {
    $prefixPattern = "^$([regex]::Escape($ProjectPrefix))_"
    foreach ($prop in $obj.PSObject.Properties) {
      $name = $prop.Name
      if ($name -in $required) { continue }
      if ($name -in $universalExtensionKeys) { continue }
      # Round-7 F66: relay_* namespace is owned by the broker.
      # A non-relay project (empty relay_repo_path) leaking a relay_*
      # key is a Tier-3 contract violation. Soft drift always (the
      # operator may have copy-pasted from a relay-aware project and
      # not realized the field is reserved).
      if ($name -match $relayPrefix) {
        if (-not $relayRepoPath) {
          $script:softDrifts += [pscustomobject]@{
            type   = 'relay-reserved-key-leak'
            lineno = $lineNo
            key    = $name
            detail = "L${lineNo}: METRICS row contains key '$name' which matches the reserved relay_* namespace, but this project has no relay_repo_path configured. Either configure the relay (set relay_repo_path in .autopilot/config.json) or rename the field with the project's '${ProjectPrefix}_' prefix."
          }
        }
        continue
      }
      if ($name -notmatch $prefixPattern) {
        if ($prefixIsExplicit) {
          # Legacy hard-mode caller passed -ProjectPrefix explicitly.
          $problems += "L${lineNo}: project extension key '$name' missing required '${ProjectPrefix}_' prefix"
        } else {
          # F66 auto-derived: surface as soft drift, don't block.
          $script:softDrifts += [pscustomobject]@{
            type   = 'extension-key-missing-prefix'
            lineno = $lineNo
            key    = $name
            detail = "L${lineNo}: METRICS extension key '$name' should start with '${ProjectPrefix}_' (auto-derived from `project_slug` in config.json). Universal Tier-1/Tier-2 keys are exempt; engine- or project-specific counters belong in the slug namespace to avoid future schema collisions."
          }
        }
      }
    }
  }
}

# Round-7 F66: emit accumulated soft drifts to FAILURES.jsonl with
# F62-style dedup. Hard problems still take priority (exit 1 happens
# below regardless of soft-drift count).
if ($script:softDrifts.Count -gt 0) {
  $failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
  $existingTail = @()
  if (Test-Path -LiteralPath $failuresPath) {
    try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
  }
  function Test-RecentMetricsDriftEcho($result, $key) {
    for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
      $ln = $existingTail[$i]
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      try {
        $r = $ln | ConvertFrom-Json -ErrorAction Stop
        if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'metrics-schema-drift')) { continue }
        if (-not ($r.PSObject.Properties.Name -contains 'result' -and [string]$r.result -eq $result)) { continue }
        if (-not ($r.PSObject.Properties.Name -contains 'key' -and [string]$r.key -eq $key)) { continue }
        return $true
      } catch { }
    }
    return $false
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  $runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
  $emitted = 0
  foreach ($d in $script:softDrifts) {
    if (Test-RecentMetricsDriftEcho -result $d.type -key $d.key) { continue }
    $row = [ordered]@{
      ts     = (Get-Date -Format 'o')
      run_id = $runId
      event  = 'metrics-schema-drift'
      result = $d.type
      lineno = $d.lineno
      key    = $d.key
      detail = $d.detail
    }
    $h = @{}
    foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
    try {
      $line = ($h | ConvertTo-Json -Compress -Depth 6) + "`n"
      [System.IO.File]::AppendAllText($failuresPath, $line, $utf8NoBom)
      $emitted++
    } catch { Write-Warning "[validate-metrics] failed to append soft drift: $_" }
  }
  Write-Host "[validate-metrics] soft drift detected ($($script:softDrifts.Count) issue(s), $emitted emitted to FAILURES.jsonl):"
  foreach ($d in $script:softDrifts) {
    Write-Host ("  [{0}] {1}" -f $d.type, $d.detail)
  }
}

if ($problems.Count -gt 0) {
  Write-Host "[validate-metrics] FAILED ($($problems.Count) issue(s)):"
  foreach ($p in $problems) { Write-Host "  $p" }
  exit 1
}

Write-Host "[validate-metrics] OK ($lineNo line(s) checked)"
exit 0
