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
$rowsWithRatioField = @()  # F58: rows that mention cache_read_ratio at all (number OR null)
foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  try {
    $row = $line | ConvertFrom-Json -ErrorAction Stop
    $te = $null
    if ($row.PSObject.Properties.Name -contains 'token_economy') { $te = $row.token_economy }
    if ($null -eq $te) { continue }
    if ($te.PSObject.Properties.Name -notcontains 'cache_read_ratio') { continue }
    $val = $te.cache_read_ratio
    $iter = if ($row.PSObject.Properties.Name -contains 'iter') { [int]$row.iter } else { 0 }
    $rowsWithRatioField += [ordered]@{
      iter      = $iter
      isNumeric = ($val -is [int] -or $val -is [long] -or $val -is [double] -or $val -is [decimal])
    }
    # Only treat as "reported" if it's a number; skip nulls / strings.
    if ($val -is [int] -or $val -is [long] -or $val -is [double] -or $val -is [decimal]) {
      $rowsWithRatio += [ordered]@{
        run_id = if ($row.PSObject.Properties.Name -contains 'run_id') { [string]$row.run_id } else { '' }
        iter   = $iter
        ratio  = [double]$val
      }
    }
  } catch { }
}

# Round-6 F58 — cache_read_ratio null-streak gate.
#
# Real failure on `D:\Unity\card game\.autopilot\` iters 112-118 (7 consecutive):
# every iter recorded `cache_read_ratio: null`. F45's threshold gate skips
# null silently, producing a complete observability blind-spot exactly when
# the operator most needs telemetry. Universal pattern: any non-Anthropic-
# prompt-cached engine (Codex CLI, openai CLI, future adapters) reports
# null and the operator has no signal.
#
# Heuristic: if ≥ NullStreakThreshold (default 5) consecutive recent rows
# carry the field but with null/non-numeric value, surface a structured
# `token-telemetry-broken` row to FAILURES.jsonl. This is a presence-streak
# gate, NOT a threshold gate — it fires even when threshold can't be
# computed.
$NullStreakThreshold = 5
if ($rowsWithRatioField.Count -ge $NullStreakThreshold) {
  $tailField = $rowsWithRatioField[-$NullStreakThreshold..-1]
  $allNull = $true
  foreach ($r in $tailField) { if ($r.isNumeric) { $allNull = $false; break } }
  if ($allNull) {
    $itersStr = ($tailField | ForEach-Object { $_.iter }) -join ', '
    # Round-6 F61 — de-dup: skip emission if the null streak hasn't been
    # interrupted since the last token-telemetry-broken row was emitted.
    # The streak is a sliding window (iters 4-8 → 5-9 → 6-10 → …) so a
    # naive observed_iters string-equality check misses the dup. Better
    # heuristic: if the previous row's max iter is one less than this
    # row's max iter AND there's been NO numeric cache_read_ratio reading
    # in between, the streak is the same one — skip.
    $currentMaxIter = ($tailField | ForEach-Object { $_.iter } | Measure-Object -Maximum).Maximum
    $skipDup = $false
    if (Test-Path -LiteralPath $failuresPath) {
      try {
        $tailFails = @(Get-Content -LiteralPath $failuresPath -Tail 20 -ErrorAction Stop)
        for ($idx = $tailFails.Count - 1; $idx -ge 0; $idx--) {
          $fl = $tailFails[$idx]
          if ([string]::IsNullOrWhiteSpace($fl)) { continue }
          try {
            $fr = $fl | ConvertFrom-Json -ErrorAction Stop
            if ($fr.PSObject.Properties.Name -contains 'event' -and [string]$fr.event -eq 'token-telemetry-broken') {
              if ($fr.PSObject.Properties.Name -contains 'observed_iters') {
                $prevIters = ([string]$fr.observed_iters) -split ',\s*' | ForEach-Object { try { [int]$_ } catch { $null } } | Where-Object { $_ -ne $null }
                if ($prevIters.Count -gt 0) {
                  $prevMaxIter = ($prevIters | Measure-Object -Maximum).Maximum
                  # Same ongoing streak iff (a) previous max is within the current streak window, and
                  # (b) no numeric reading has appeared since previous emission (which would reset).
                  $hasNumericSince = $false
                  foreach ($r in $rowsWithRatioField) {
                    if ($r.iter -gt $prevMaxIter -and $r.isNumeric) { $hasNumericSince = $true; break }
                  }
                  if (-not $hasNumericSince -and $prevMaxIter -le $currentMaxIter -and $prevMaxIter -ge ($currentMaxIter - $NullStreakThreshold + 1)) {
                    $skipDup = $true
                  }
                }
              }
              break
            }
          } catch { }
        }
      } catch { }
    }
    if ($skipDup) {
      Write-Host "[token-economy] telemetry-broken streak still present (iters [$itersStr]) — already logged, skipping duplicate"
      # exit-clean fall-through — let the threshold check below also run
    } else {
    $runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
    $tnRow = [ordered]@{
      ts                 = (Get-Date -Format 'o')
      run_id             = $runId
      event              = 'token-telemetry-broken'
      result             = 'cache-read-ratio-null-streak'
      threshold_iters    = $NullStreakThreshold
      observed_iters     = $itersStr
      detail             = "Last $NullStreakThreshold consecutive METRICS rows reported token_economy.cache_read_ratio as null/non-numeric: iters [$itersStr]. The threshold gate (F45) cannot fire — observability blind-spot. Likely cause: AI-engine adapter does not expose Anthropic prompt-cache stats (Codex CLI, openai CLI, etc.) OR the relay broker isn't propagating the field. Recovery: verify the relay/adapter writes a numeric ratio per iter; if the engine genuinely has no prompt-cache, omit the field entirely so F45 stays silent rather than recording null."
    }
    Write-DriftRow -Path $failuresPath -Row $tnRow
    Write-Host "[token-economy] TELEMETRY-BROKEN — cache_read_ratio null for $NullStreakThreshold consecutive iters [$itersStr]" -ForegroundColor Yellow
    Write-Host "  drift event appended to FAILURES.jsonl"
    if (-not $Soft) { exit 1 }
    }  # end else (not skipDup)
  }
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

# Round-6 F62 — de-dup: skip emission if the most recent token-economy-drift
# row in FAILURES tail already records the same observed_iters streak.
$skipEcho = $false
if (Test-Path -LiteralPath $failuresPath) {
  try {
    $tailFails = @(Get-Content -LiteralPath $failuresPath -Tail 30 -ErrorAction Stop)
    for ($idx = $tailFails.Count - 1; $idx -ge 0; $idx--) {
      $fl = $tailFails[$idx]
      if ([string]::IsNullOrWhiteSpace($fl)) { continue }
      try {
        $fr = $fl | ConvertFrom-Json -ErrorAction Stop
        if ($fr.PSObject.Properties.Name -contains 'event' -and [string]$fr.event -eq 'token-economy-drift') {
          if ($fr.PSObject.Properties.Name -contains 'observed_iters' -and [string]$fr.observed_iters -eq $itersStr) {
            $skipEcho = $true
          }
          break
        }
      } catch { }
    }
  } catch { }
}

if ($skipEcho) {
  Write-Host "[token-economy] cache-read-ratio drift unchanged (iters [$itersStr]) — already logged, skipping duplicate"
  if ($Soft) { exit 0 } else { exit 1 }
}

$row = [ordered]@{
  ts                = (Get-Date -Format 'o')
  run_id            = $runId
  event             = 'token-economy-drift'
  result            = 'cache-read-ratio-below-floor'
  threshold         = $CacheReadRatioFloor
  consecutive_count = $ConsecutiveLowThreshold
  observed_ratios   = $ratiosStr
  observed_iters    = $itersStr
  detail            = "Last $ConsecutiveLowThreshold consecutive METRICS rows with token_economy.cache_read_ratio reported all show ratios below the floor ($CacheReadRatioFloor): [$ratiosStr] for iters [$itersStr]. Per PROMPT.md budget IMMUTABLE rule, this should immediately trigger work reduction + summarization. Recovery: next iter should be doc-only summarization, OR rotate the relay broker session, OR raise the cache hit ratio (e.g. by re-reading the system prompt early so caching actually applies)."
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
