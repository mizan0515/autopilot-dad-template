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
    try { [datetime]::Parse($obj.ts) | Out-Null }
    catch { $problems += "L${lineNo}: ts='$($obj.ts)' does not parse as ISO-8601" }
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
