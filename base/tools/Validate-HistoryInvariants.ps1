# Validate-HistoryInvariants.ps1
#
# Round-5 F42 — HISTORY.md ordering / duplicate / size invariants.
#
# Operator-reported real failure (round-5 audit, P1):
# Unity-card-game's HISTORY.md violated both stated invariants —
# entries appeared as 111 → 113 → 10898 → 114 → 115 → 116 → 117 → 118
# (out-of-order, also a typo / corruption iter "10898" between two
# legitimate entries), plus mojibake on some lines, while the file
# header still claimed "newest first, keep last 10". The operator
# dashboard reads HISTORY as evidence; broken ordering and stale
# entries quietly poisoned the operator's view.
#
# Engine-agnostic invariants checked:
#   I1. Entry headers match `## iter <N>` (decimal). Lines that look
#       like headers but don't (typos, copy-paste corruption) are
#       flagged.
#   I2. Iter numbers strictly decreasing top-to-bottom (newest first).
#   I3. No duplicate iter numbers.
#   I4. Visible-entry count ≤ MaxEntries (default 10). Beyond that,
#       expect older entries to have been moved to `.archive/`
#       per PROMPT.md row 15.
#
# When any invariant fails, append a structured `history-invariant-
# violated` row to FAILURES.jsonl (with F37 run_id correlation when
# available) and exit non-zero unless `-Soft` is passed.
#
# Usage:
#   pwsh tools/Validate-HistoryInvariants.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Validate-HistoryInvariants.ps1 -AutopilotRoot .autopilot -Soft
#   pwsh tools/Validate-HistoryInvariants.ps1 -AutopilotRoot .autopilot -MaxEntries 15
#
# Exit codes:
#   0 — all invariants pass, OR HISTORY.md absent (skip)
#   1 — at least one invariant violated (hard mode)
#   0 — same drift but `-Soft` set

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$MaxEntries = 10,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$historyPath  = Join-Path $AutopilotRoot 'HISTORY.md'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

if (-not (Test-Path -LiteralPath $historyPath)) { exit 0 }

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[history-invariants] failed to append: $_" }
}

# --- parse HISTORY.md -----------------------------------------------------

$text = ''
try { $text = [System.IO.File]::ReadAllText($historyPath) } catch { exit 0 }
$lines = $text -split "`r?`n"

# Match `## iter <decimal>` at beginning of line. Tolerate trailing
# punctuation, em-dashes, hyphens, language-locale extras. The
# capture group is the iter number as a literal decimal string.
$entryHeaders = @()
$badLooking   = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  if ($line -match '^##\s+iter\s+(\d+)\b') {
    $entryHeaders += [ordered]@{
      lineno = $i + 1
      iter   = [int]$matches[1]
      raw    = $line.Trim()
    }
    continue
  }
  # Heuristic for "looks like a header but isn't": starts with `## iter`
  # but no decimal follows. Catches typos like `## iter abc`,
  # `## iter `, etc.
  if ($line -match '^##\s+iter\s+\S') {
    $badLooking += [ordered]@{
      lineno = $i + 1
      raw    = $line.Trim()
    }
  }
}

# --- I1: malformed headers -----------------------------------------------

$violations = @()
foreach ($b in $badLooking) {
  $violations += [ordered]@{
    type   = 'malformed-header'
    lineno = $b.lineno
    raw    = $b.raw
    detail = "Line looks like an iter header but has no decimal iter number after `## iter`."
  }
}

# --- I2: ordering (newest first → strictly decreasing top-to-bottom) ----

for ($i = 1; $i -lt $entryHeaders.Count; $i++) {
  $prev = $entryHeaders[$i - 1]
  $cur  = $entryHeaders[$i]
  if ($cur.iter -ge $prev.iter) {
    $violations += [ordered]@{
      type   = 'order-violated'
      lineno = $cur.lineno
      raw    = $cur.raw
      detail = "iter $($cur.iter) appears after iter $($prev.iter) — entries must be strictly decreasing (newest first)."
    }
  }
}

# --- I3: duplicates -------------------------------------------------------

$seen = @{}
foreach ($h in $entryHeaders) {
  if ($seen.ContainsKey($h.iter)) {
    $violations += [ordered]@{
      type   = 'duplicate-iter'
      lineno = $h.lineno
      raw    = $h.raw
      detail = "iter $($h.iter) appears at line $($h.lineno) and also at line $($seen[$h.iter])."
    }
  } else {
    $seen[$h.iter] = $h.lineno
  }
}

# --- I4: size cap (visible entries) --------------------------------------

if ($entryHeaders.Count -gt $MaxEntries) {
  $violations += [ordered]@{
    type   = 'size-exceeded'
    lineno = ($entryHeaders[$MaxEntries].lineno)
    raw    = ($entryHeaders[$MaxEntries].raw)
    detail = "HISTORY.md has $($entryHeaders.Count) visible iter entries; exceeds soft cap of $MaxEntries. Per PROMPT.md row 15, rotate older entries into `.autopilot/.archive/HISTORY-<iter>.md`."
  }
}

# --- result ---------------------------------------------------------------

if ($violations.Count -eq 0) {
  Write-Host "[history-invariants] OK — $($entryHeaders.Count) entries, ordering valid, no duplicates, no malformed headers"
  exit 0
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }

# Round-6 F62 — de-dup unchanged drift signals.
# Surfaced by 10-iter dogfood: every pre-commit while HISTORY.md exceeds the
# soft cap re-emits an identical `size-exceeded` row, polluting the operator
# dashboard with N copies of the same finding. Universal: any drift validator
# that re-evaluates a persistent condition. Skip emission when the most
# recent FAILURES entry for the same `(event, result, lineno)` triple
# matches what we'd emit now.
$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -ErrorAction Stop) } catch { }
}
function Test-RecentDriftEcho($result, $lineno) {
  # Key on result-type only (not lineno): adding new HISTORY entries shifts
  # the lineno of every prior entry, so a lineno-keyed de-dup misses the
  # echo. The semantic "same drift class still present" is what matters
  # for operator dashboard noise. Different result classes (size-exceeded
  # vs order-violated vs malformed-header) still emit independently.
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'history-invariant-violated' -and
          $r.PSObject.Properties.Name -contains 'result' -and [string]$r.result -eq $result) {
        return $true
      }
    } catch { }
  }
  return $false
}

$emittedCount = 0
foreach ($v in $violations) {
  if (Test-RecentDriftEcho -result $v.type -lineno $v.lineno) {
    Write-Host ("  [{0}] line {1}: same drift already in FAILURES tail — skipping duplicate" -f $v.type, $v.lineno)
    continue
  }
  $row = [ordered]@{
    ts      = (Get-Date -Format 'o')
    run_id  = $runId
    event   = 'history-invariant-violated'
    result  = $v.type
    lineno  = $v.lineno
    line    = $v.raw
    detail  = $v.detail
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emittedCount++
}

Write-Host ""
Write-Host "[history-invariants] VIOLATIONS DETECTED ($($violations.Count))" -ForegroundColor Red
foreach ($v in $violations) {
  Write-Host ("  [{0}] line {1}: {2}" -f $v.type, $v.lineno, $v.raw)
}
Write-Host "  $emittedCount drift event(s) appended to FAILURES.jsonl ($($violations.Count - $emittedCount) duplicates skipped)"

if ($Soft) {
  Write-Host ""
  Write-Host "[history-invariants] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
