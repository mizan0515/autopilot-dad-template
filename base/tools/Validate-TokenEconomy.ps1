# Validate-TokenEconomy.ps1
#
# Round-5 F45 — token-economy reporting gate.
#
# Operator-reported P2 / strategy finding (round-4 audit):
# Token-economy data (carry_forward_bytes, cache_read_ratio,
# cumulative_output_tokens, rotation_reason, truncation) wasn't
# making it to the operator dashboard. When token pressure
# existed but no rotation/summary evidence was recorded, the
# relay run should be treated as failed — but no validator
# enforced that.
#
# Engine-agnostic / project-shape-aware design:
#
#   UNIVERSAL fields (apply to every Claude API workload, with or
#   without DAD relay):
#     - cache_read_ratio          (Anthropic prompt-cache read ratio)
#     - cumulative_output_tokens  (running total per session/iter)
#
#   RELAY-ONLY fields (only meaningful when a DAD relay is in use;
#   non-relay projects should omit them entirely):
#     - carry_forward_bytes       (handoff.context byte size)
#     - truncation                (bool — handoff.context was clipped)
#     - rotation_reason           (relay broker rotation cause)
#
# This validator only enforces the universal rule:
#   "cache_read_ratio < 0.25 for 2 consecutive iters" → drift.
# That rule already lives in PROMPT.md budget IMMUTABLE; this
# validator just makes it programmatically detectable instead of
# relying on the agent's self-report.
#
# Relay-only fields are documented in PROMPT.md for operators who
# use a relay, but this validator does NOT require them. A non-
# relay project's METRICS rows can omit token_economy entirely
# (or include only the universal subset).
#
# This separation is the round-5 lesson from F39→F43 (where the
# original gate bias toward Unity-specific fields confused non-
# Unity operators). The template ships engine-agnostic; relay
# adoption is operator-optional.
#
# Usage:
#   pwsh tools/Validate-TokenEconomy.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Validate-TokenEconomy.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no drift, OR not enough METRICS history yet, OR cache_read
#       _ratio threshold not breached
#   1 — drift detected (hard mode)
#   0 — same drift but `-Soft` set

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$ConsecutiveLowThreshold = 2,
  [double]$CacheReadRatioFloor = 0.25,
  [int]$TailLines = 20,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$metricsPath  = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

if (-not (Test-Path -LiteralPath $metricsPath)) { exit 0 }

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[token-economy] failed to append: $_" }
}

# --- collect last N rows that have a cache_read_ratio reading -------------

try {
  $lines = @(Get-Content -LiteralPath $metricsPath -Tail $TailLines -ErrorAction Stop)
} catch { exit 0 }

$rowsWithRatio = @()
foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  try {
    $row = $line | ConvertFrom-Json -ErrorAction Stop
    $te = $null
    if ($row.PSObject.Properties.Name -contains 'token_economy') { $te = $row.token_economy }
    if ($null -eq $te) { continue }
    if ($te.PSObject.Properties.Name -notcontains 'cache_read_ratio') { continue }
    $val = $te.cache_read_ratio
    # Only treat as "reported" if it's a number; skip nulls / strings.
    if ($val -is [int] -or $val -is [long] -or $val -is [double] -or $val -is [decimal]) {
      $rowsWithRatio += [ordered]@{
        run_id = if ($row.PSObject.Properties.Name -contains 'run_id') { [string]$row.run_id } else { '' }
        iter   = if ($row.PSObject.Properties.Name -contains 'iter')   { [int]$row.iter }     else { 0 }
        ratio  = [double]$val
      }
    }
  } catch { }
}

if ($rowsWithRatio.Count -lt $ConsecutiveLowThreshold) {
  # Not enough data to make a multi-iter judgment yet.
  Write-Host "[token-economy] OK — only $($rowsWithRatio.Count) row(s) with cache_read_ratio in last $TailLines METRICS lines (need ≥ $ConsecutiveLowThreshold)"
  exit 0
}

# --- check the last N consecutive rows for sustained low ratio ------------

$tail = $rowsWithRatio[-$ConsecutiveLowThreshold..-1]
$allLow = $true
foreach ($r in $tail) {
  if ($r.ratio -ge $CacheReadRatioFloor) { $allLow = $false; break }
}

if (-not $allLow) {
  Write-Host "[token-economy] OK — cache_read_ratio above floor ($CacheReadRatioFloor) within recent window"
  exit 0
}

# --- drift: consecutive low ratio ----------------------------------------

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$ratiosStr = ($tail | ForEach-Object { '{0:F3}' -f $_.ratio }) -join ', '
$itersStr  = ($tail | ForEach-Object { $_.iter }) -join ', '

$row = [ordered]@{
  ts                = (Get-Date -Format 'o')
  run_id            = $runId
  event             = 'token-economy-drift'
  result            = 'cache-read-ratio-below-floor'
  threshold         = $CacheReadRatioFloor
  consecutive_count = $ConsecutiveLowThreshold
  observed_ratios   = $ratiosStr
  observed_iters    = $itersStr
  detail            = "Last $ConsecutiveLowThreshold consecutive METRICS rows with token_economy.cache_read_ratio reported all show ratios below the floor ($CacheReadRatioFloor): [$ratiosStr] for iters [$itersStr]. Per PROMPT.md budget IMMUTABLE rule, this should immediately trigger work reduction + summarization. Operator finding: token pressure without rotation/summary evidence should be treated as a failed run. Recovery: next iter should be doc-only summarization, OR rotate the relay broker session, OR raise the cache hit ratio (e.g. by re-reading the system prompt early so caching actually applies)."
}
$h = @{}
foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
Write-DriftRow -Path $failuresPath -Row $h

Write-Host ""
Write-Host "[token-economy] CACHE-READ-RATIO DRIFT" -ForegroundColor Red
Write-Host "  threshold: < $CacheReadRatioFloor for $ConsecutiveLowThreshold consecutive iters"
Write-Host "  observed:  ratios=[$ratiosStr] iters=[$itersStr]"
Write-Host "  drift event appended to FAILURES.jsonl"

if ($Soft) {
  Write-Host ""
  Write-Host "[token-economy] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
