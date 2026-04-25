# Validate-LedgerConsistency.ps1
#
# Round-4 F38 — operational ledger reconciliation gate.
#
# Detects drift between `.autopilot/RUNNER-LIVE.json` (last phase + run_id)
# and the corresponding tail rows in `.autopilot/METRICS.jsonl` /
# `.autopilot/FAILURES.jsonl`. The shared `run_id` UUID was added in F37
# (#64); this validator is the first consumer.
#
# Background — operator-reported real failure (round-4):
# `D:\Unity\card game\.autopilot\RUNNER-LIVE.json` was stuck at
# `phase: retained-dirty` for ~15 hours while STATE.md, HISTORY.md, and
# METRICS.jsonl advanced through 9 PRs (#299-#307). Nothing surfaced the
# inconsistency because no programmatic check tied the four ledgers' rows
# back to the same iter. F37 supplied the correlation key; this validator
# uses it.
#
# Drift detection rules (terminal phases — iter is "done"):
#   - phase ∈ {removed-clean, wip-rescued}
#       → expect METRICS.jsonl tail to contain a row with the same run_id
#       → no match → drift
#   - phase ∈ {preflight-failed, llm-timeout, consecutive-stall-halt,
#              wip-commit-failed-snapshotted, wip-failed-no-snapshot,
#              wip-local-only-snapshotted}
#       → expect FAILURES.jsonl tail to contain a row with the same run_id
#       → no match → drift
#
# Skipped phases (iter is in-flight or transient — no expectation yet):
#   - phase ∈ {startup, running, retained-dirty, stalled-fallback, halted}
#
# When drift is detected:
#   - append a `{ event: 'ledger-drift', ... }` row to FAILURES.jsonl
#     (ironically using F37's stamp pattern — the drift event itself
#     gets ledger-correlated with the offending run_id)
#   - emit a structured stderr line and exit non-zero
#
# Initial deployment (per round-4 plan): wire into preflight as a SOFT
# check that emits the drift event but doesn't block the iter. Once
# operators have seen drift events fire on real workloads and confirmed
# the rules don't false-positive, promote to a HARD preflight gate that
# forces the next iter into recovery mode.
#
# Usage (standalone):
#   pwsh tools/Validate-LedgerConsistency.ps1 -AutopilotRoot .autopilot
#
# Usage (preflight call site):
#   pwsh tools/Validate-LedgerConsistency.ps1 -AutopilotRoot $autopilotRoot -Soft
#
# Exit codes:
#   0 — no drift, or only skipped/transient phases
#   1 — drift detected (hard mode)
#   0 — drift detected but `-Soft` set (drift logged, exit clean so
#       preflight chain continues; operator dashboard surfaces the event)

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$TailLines = 10,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) {
  Write-Host "[ledger] AutopilotRoot not found: $AutopilotRoot — skipping"
  exit 0
}

$runnerLivePath = Join-Path $AutopilotRoot 'RUNNER-LIVE.json'
$metricsPath    = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath   = Join-Path $AutopilotRoot 'FAILURES.jsonl'

if (-not (Test-Path -LiteralPath $runnerLivePath)) {
  Write-Host "[ledger] $runnerLivePath not present — runner has not yet recorded any phase. Skipping."
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Read-RunnerLive {
  param([string]$Path)
  try {
    $raw = [System.IO.File]::ReadAllText($Path)
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
  } catch {
    Write-Warning "[ledger] failed to parse RUNNER-LIVE.json: $_"
    return $null
  }
}

function Get-JsonlTail {
  param([string]$Path, [int]$Count)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  try {
    $lines = Get-Content -LiteralPath $Path -Tail $Count -ErrorAction Stop
    $rows = @()
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try {
        $rows += ($line | ConvertFrom-Json -ErrorAction Stop)
      } catch {
        # Tolerate one bad line — log + continue, since the operator
        # may have hand-edited or migration scripts may have left
        # legacy rows. Drift detection only needs to find ONE matching
        # row to declare the iter healthy.
      }
    }
    return $rows
  } catch {
    return @()
  }
}

function Test-RowsContainRunId {
  param($Rows, [string]$RunId)
  if (-not $RunId) { return $false }
  foreach ($r in $Rows) {
    if ($r.PSObject.Properties.Name -contains 'run_id' -and $r.run_id -eq $RunId) {
      return $true
    }
  }
  return $false
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch {
    Write-Warning "[ledger] failed to append drift row to $Path : $_"
  }
}

# --- read ledger state ----------------------------------------------------

$runner = Read-RunnerLive -Path $runnerLivePath
if (-not $runner) {
  Write-Host "[ledger] RUNNER-LIVE.json unparseable — skipping (preflight will likely fail elsewhere)"
  exit 0
}

$phase = [string]$runner.phase
$runId = [string]$runner.run_id
$ts    = [string]$runner.ts

# Phases that don't expect a terminal ledger row yet.
$skipPhases = @('startup', 'running', 'retained-dirty', 'stalled-fallback', 'halted')
if ($skipPhases -contains $phase) {
  Write-Host "[ledger] phase='$phase' is in-flight/transient — skipping reconciliation"
  exit 0
}

if (-not $runId) {
  # Pre-F37 RUNNER-LIVE rows have no run_id. The first iter post-upgrade
  # will populate it; until then we can't reconcile. This is informational,
  # not a drift signal.
  Write-Host "[ledger] RUNNER-LIVE.json has empty run_id (likely pre-F37 row) — skipping"
  exit 0
}

# --- expected-row class ---------------------------------------------------

$cleanPhases   = @('removed-clean', 'wip-rescued')
$failurePhases = @('preflight-failed', 'llm-timeout', 'consecutive-stall-halt',
                   'wip-commit-failed-snapshotted', 'wip-failed-no-snapshot',
                   'wip-local-only-snapshotted')

$expectedFile = $null
$expectedKind = $null
if ($cleanPhases -contains $phase) {
  $expectedFile = $metricsPath
  $expectedKind = 'METRICS.jsonl'
} elseif ($failurePhases -contains $phase) {
  $expectedFile = $failuresPath
  $expectedKind = 'FAILURES.jsonl'
} else {
  Write-Host "[ledger] phase='$phase' not in known terminal-phase set — skipping (extend `Validate-LedgerConsistency.ps1` if this is a new phase)"
  exit 0
}

$tailRows = Get-JsonlTail -Path $expectedFile -Count $TailLines
$matched = Test-RowsContainRunId -Rows $tailRows -RunId $runId

if ($matched) {
  Write-Host "[ledger] OK — phase='$phase', run_id='$runId' has matching $expectedKind row"
  exit 0
}

# --- drift detected -------------------------------------------------------

$driftRow = [ordered]@{
  ts            = (Get-Date -Format 'o')
  run_id        = $runId
  event         = 'ledger-drift'
  result        = 'expected-row-missing'
  runner_phase  = $phase
  runner_ts     = $ts
  expected_file = $expectedKind
  detail        = "RUNNER-LIVE.json shows phase='$phase' but no matching row with run_id='$runId' was found in the last $TailLines $expectedKind entries. This usually means: (1) the runner / agent crashed before writing the terminal row; (2) the previous iter's state was manually overwritten; (3) two parallel runners are racing on the same .autopilot/. See https://github.com/mizan0515/autopilot-dad-template/blob/main/AUDIT.md row 79 for context."
}

# Convert to hashtable for AppendAllText helper.
$h = @{}
foreach ($k in $driftRow.Keys) { $h[$k] = $driftRow[$k] }
Write-DriftRow -Path $failuresPath -Row $h

Write-Host ""
Write-Host "[ledger] DRIFT DETECTED" -ForegroundColor Red
Write-Host "  RUNNER-LIVE.json: phase='$phase' run_id='$runId' ts='$ts'"
Write-Host "  expected: a row with run_id='$runId' in tail of $expectedKind"
Write-Host "  found:    none in last $TailLines lines"
Write-Host "  drift event appended to FAILURES.jsonl with run_id='$runId'"

if ($Soft) {
  Write-Host ""
  Write-Host "[ledger] Running in -Soft mode: drift logged, returning exit 0 so preflight chain continues. Operator dashboard will surface the ledger-drift event." -ForegroundColor Yellow
  exit 0
}

exit 1
