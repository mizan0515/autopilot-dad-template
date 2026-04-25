# base/tools/Validate-Metrics.ps1
#
# Line-by-line validator for .autopilot/METRICS.jsonl. Enforces:
#   - each line is valid UTF-8 JSON
#   - Tier-1 required fields present: iter, ts, outcome, duration_s
#   - ts parses as ISO-8601
#   - project-scoped extension keys use the project's SKILL_PREFIX
#     (collisions with relay Tier-3 keys cause silent schema drift)
#
# Exit 0 = all good. Exit 1 + prints offending line numbers if any fail.
#
# Usage:
#   pwsh base/tools/Validate-Metrics.ps1 -Path .autopilot/METRICS.jsonl -ProjectPrefix myslug
#   pwsh base/tools/Validate-Metrics.ps1 -Path .autopilot/METRICS.jsonl  # skip prefix check

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [string]$ProjectPrefix
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Path)) {
  Write-Host "[validate-metrics] no METRICS file at $Path (OK on fresh repo)"
  exit 0
}

$required = @('iter', 'ts', 'outcome', 'duration_s')
# Tier-3 keys that the relay owns — downstream projects must NOT collide.
$reservedTier3 = @('relay_session_id', 'relay_broker_version', 'relay_turn_index',
                   'relay_carry_bytes', 'relay_rotation_count')

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
      if ($name -in @('tokens','pr_url','mode','status','files_read','bash_calls',
                       'mcp_calls','commits','prs','merged','screenshots',
                       'editmode_tests','budget_exceeded','cache_read_ratio')) { continue }
      if ($name -in $reservedTier3) {
        $problems += "L${lineNo}: key '$name' is reserved for relay Tier-3"
        continue
      }
      if ($name -notmatch $prefixPattern) {
        $problems += "L${lineNo}: project extension key '$name' missing required '${ProjectPrefix}_' prefix"
      }
    }
  }
}

if ($problems.Count -gt 0) {
  Write-Host "[validate-metrics] FAILED ($($problems.Count) issue(s)):"
  foreach ($p in $problems) { Write-Host "  $p" }
  exit 1
}

Write-Host "[validate-metrics] OK ($lineNo line(s) checked)"
exit 0
