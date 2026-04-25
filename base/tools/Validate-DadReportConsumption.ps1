# Validate-DadReportConsumption.ps1
#
# Round-4 F41 — DAD report consumption gate.
#
# Closes the cross-repo loop the operator-reported failure exposed:
# the relay's generated dashboard / runbook / direct-prompt artifacts
# already flagged `unity_mcp_observed` missing on Unity-card-game,
# but Unity-side autopilot never consumed those reports — the blocked
# state went uncorrected for 15+ hours despite the relay knowing the
# answer.
#
# This validator scans `.autopilot/reports/*.json` and `.autopilot/
# generated/*.json` (both relay-drop conventions are seen in the
# wild) for entries whose status fields signal "needs attention",
# then checks whether the iter has already consumed them — defined
# as: the report's `session_id` / file basename appears in the recent
# tail of `STATE.md`, `HISTORY.md`, or the file has been moved into
# `.autopilot/consumed/`.
#
# When an unconsumed needs-attention report is detected, the validator
# appends a structured `dad-report-unconsumed` event to FAILURES.jsonl
# (using F37's `run_id` correlation when available) and exits non-zero
# unless `-Soft` is passed.
#
# Recognized "needs attention" signals:
#   overall_status ∈ {blocked, governance_blocked, stalled,
#                     missing-evidence, action-required, unconsumed}
#   next_action    ∈ {blocked, fix_blocker, escalate, recovery,
#                     escalate-to-operator}
#   status         ∈ same set as overall_status (fallback for
#                     simpler schemas)
#
# Initial deployment: soft mode (logged, exit clean) so operators
# can see false-positive rate before the gate becomes blocking.
#
# Usage:
#   pwsh tools/Validate-DadReportConsumption.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Validate-DadReportConsumption.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no unconsumed needs-attention reports found
#   1 — at least one unconsumed report (hard mode)
#   0 — same drift but `-Soft` set

param(
  [string]$AutopilotRoot = '.autopilot',
  [int]$RecentLines = 200,
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$reportDirs = @(
  (Join-Path $AutopilotRoot 'reports'),
  (Join-Path $AutopilotRoot 'generated')
)
$consumedDir = Join-Path $AutopilotRoot 'consumed'
$statePath   = Join-Path $AutopilotRoot 'STATE.md'
$historyPath = Join-Path $AutopilotRoot 'HISTORY.md'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Status / action vocabularies. Operators can extend by editing this
# validator (or by writing a project-specific shadow validator that
# wraps it). Conservative defaults — only signals that clearly
# indicate "needs attention" trigger drift.
$attentionStatuses = @(
  'blocked', 'governance_blocked', 'stalled',
  'missing-evidence', 'action-required', 'unconsumed',
  'fail', 'failed', 'fail_closed'
)
$attentionActions = @(
  'blocked', 'fix_blocker', 'escalate', 'recovery',
  'escalate-to-operator', 'unblock-required'
)

function Get-RecentTextTail {
  param([string]$Path, [int]$Lines)
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  try {
    # Force array context per F39 lesson, then re-join.
    $arr = @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction Stop)
    return ($arr -join "`n")
  } catch { return '' }
}

function Get-AttentionReason {
  param($Doc)
  # Inspect a parsed JSON doc for any signal in the recognized status
  # / action vocabularies. Returns the first matching signal as a
  # string ("status: blocked" / "next_action: fix_blocker") or $null.
  if (-not $Doc) { return $null }
  $candidates = @(
    @{ Field = 'overall_status'; Vocab = $attentionStatuses },
    @{ Field = 'status';         Vocab = $attentionStatuses },
    @{ Field = 'next_action';    Vocab = $attentionActions  }
  )
  foreach ($c in $candidates) {
    if ($Doc.PSObject.Properties.Name -notcontains $c.Field) { continue }
    $val = [string]$Doc.($c.Field)
    if (-not $val) { continue }
    $valLc = $val.ToLowerInvariant()
    if ($c.Vocab -contains $valLc) {
      return ('{0}={1}' -f $c.Field, $val)
    }
  }
  return $null
}

function Test-IsConsumed {
  param([string]$ReportPath, [string]$SessionId, [string]$StateText, [string]$HistoryText)
  $basename = [IO.Path]::GetFileNameWithoutExtension($ReportPath)
  # Either: the report file already lives under .autopilot/consumed/...
  $rel = $ReportPath.Replace('\','/')
  if ($rel -match '/consumed/') { return $true }
  # Or: STATE.md / HISTORY.md tail mentions the session_id or basename
  foreach ($needle in @($SessionId, $basename)) {
    if (-not $needle) { continue }
    if ($StateText -and $StateText.Contains($needle)) { return $true }
    if ($HistoryText -and $HistoryText.Contains($needle)) { return $true }
  }
  return $false
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[dad-report-consumption] failed to append: $_" }
}

# --- collect candidate reports --------------------------------------------

$reports = @()
foreach ($dir in $reportDirs) {
  if (-not (Test-Path -LiteralPath $dir)) { continue }
  try {
    Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction Stop | ForEach-Object {
      $reports += $_.FullName
    }
  } catch { }
}

if ($reports.Count -eq 0) {
  Write-Host "[dad-report-consumption] no reports under .autopilot/reports/ or .autopilot/generated/ — skipping"
  exit 0
}

# --- read context ---------------------------------------------------------

$stateText   = Get-RecentTextTail -Path $statePath   -Lines 200
$historyText = Get-RecentTextTail -Path $historyPath -Lines $RecentLines

# --- scan --------------------------------------------------------------------

$unconsumed = @()
foreach ($r in $reports) {
  $doc = $null
  try {
    $raw = [System.IO.File]::ReadAllText($r)
    $doc = $raw | ConvertFrom-Json -ErrorAction Stop
  } catch { continue }
  $reason = Get-AttentionReason -Doc $doc
  if (-not $reason) { continue }
  $sessionId = if ($doc.PSObject.Properties.Name -contains 'session_id') { [string]$doc.session_id } else { '' }
  $consumed = Test-IsConsumed -ReportPath $r -SessionId $sessionId -StateText $stateText -HistoryText $historyText
  if (-not $consumed) {
    $unconsumed += [ordered]@{
      path       = $r
      basename   = (Split-Path $r -Leaf)
      session_id = $sessionId
      reason     = $reason
    }
  }
}

if ($unconsumed.Count -eq 0) {
  Write-Host "[dad-report-consumption] OK — all needs-attention reports already consumed (state/history mention or under consumed/)"
  exit 0
}

# --- drift ----------------------------------------------------------------

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }

foreach ($u in $unconsumed) {
  $row = [ordered]@{
    ts         = (Get-Date -Format 'o')
    run_id     = $runId
    event      = 'dad-report-unconsumed'
    result     = 'needs-attention-without-consumption'
    report     = $u.basename
    session_id = $u.session_id
    reason     = $u.reason
    detail     = "A relay-dropped report at $($u.path) signals $($u.reason) but no recent STATE.md / HISTORY.md mention of session_id='$($u.session_id)' or basename='$($u.basename)' was found, and the file is not under .autopilot/consumed/. Per round-4 F41, the agent must consume relay reports (read + record in BACKLOG/HISTORY/METRICS, or move to .autopilot/consumed/) before starting product work. Operator's real Unity-card-game incident: relay dashboards already flagged unity_mcp_observed missing for 15+ hours, but Unity-side autopilot never consumed the signal. Run a recovery iter to triage this report."
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
}

Write-Host ""
Write-Host "[dad-report-consumption] UNCONSUMED REPORTS DETECTED" -ForegroundColor Red
foreach ($u in $unconsumed) {
  Write-Host ("  - {0}  ({1}; session={2})" -f $u.basename, $u.reason, $u.session_id)
}
Write-Host "  $($unconsumed.Count) drift event(s) appended to FAILURES.jsonl"

if ($Soft) {
  Write-Host ""
  Write-Host "[dad-report-consumption] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
