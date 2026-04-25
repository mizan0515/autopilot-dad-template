# Validate-StaleStateDetection.ps1
#
# Round-5 F44 — stale-state detection (retained-dirty mismatch + stale
# draft PR alerts).
#
# Operator-reported real failure (round-4/5 audit, P1):
# Unity-card-game's `RUNNER-LIVE.json` claimed phase='retained-dirty'
# pointing at `D:\Unity\card game-autopilot-runner\live`, but the
# worktree at that path was actually clean (`git status --porcelain`
# returned nothing). At the same time, draft PR #292 connected to
# the supposed WIP had been languishing for ~30 days. Two distinct
# stale states, neither auto-detected:
#
#   1. RUNNER-LIVE says retained-dirty (the runner is "preserving
#      WIP"), but the worktree no longer has any uncommitted changes
#      — the WIP was either committed or discarded externally, and
#      RUNNER-LIVE is out of sync.
#
#   2. A draft PR exists, opened ages ago, with no recent updates.
#      The autopilot loop forgot about it; it sits open as zombie
#      WIP. Per PROMPT.md "idle upkeep" (Row 10), agents should sweep
#      stale auto-PRs but nothing measured that they actually did.
#
# This validator surfaces both as soft drift events (run_id-correlated
# FAILURES rows). Operator dashboard can highlight; future hard mode
# can force a recovery iter.
#
# Configuration:
#   `.autopilot/config.json` keys (optional):
#     stale_draft_pr_hours    : default 72 (3 days)
#     skip_draft_pr_check     : bool — set true to skip the gh-based
#                               check (e.g. CI environments where
#                               gh isn't authenticated as @me).
#     draft_pr_branch_prefix  : optional filter (e.g. "dev/autopilot-")
#                               to ignore non-autopilot drafts.
#
# Usage:
#   pwsh tools/Validate-StaleStateDetection.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Validate-StaleStateDetection.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no stale-state drift, OR `-Soft` set, OR not enough info to
#       check (gh missing / RUNNER-LIVE absent / etc.)
#   1 — drift detected (hard mode)

param(
  [string]$AutopilotRoot = '.autopilot',
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$runnerLivePath = Join-Path $AutopilotRoot 'RUNNER-LIVE.json'
$failuresPath   = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$cfgPath        = Join-Path $AutopilotRoot 'config.json'

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config (optional knobs) ---------------------------------------------

$stalePrHours = 72
$skipDraftCheck = $false
$draftBranchPrefix = ''
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'stale_draft_pr_hours') {
      $val = $cfg.stale_draft_pr_hours
      if ($val -is [int] -and $val -gt 0) { $stalePrHours = [int]$val }
    }
    if ($cfg.PSObject.Properties.Name -contains 'skip_draft_pr_check') {
      $skipDraftCheck = [bool]$cfg.skip_draft_pr_check
    }
    if ($cfg.PSObject.Properties.Name -contains 'draft_pr_branch_prefix') {
      $draftBranchPrefix = [string]$cfg.draft_pr_branch_prefix
    }
  } catch { }
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[stale-state] failed to append: $_" }
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }

$drifts = @()

# --- check 1: retained-dirty mismatch -------------------------------------

if (Test-Path -LiteralPath $runnerLivePath) {
  try {
    $runner = [System.IO.File]::ReadAllText($runnerLivePath) | ConvertFrom-Json -ErrorAction Stop
  } catch { $runner = $null }

  if ($runner -and $runner.phase -eq 'retained-dirty') {
    $rr = [string]$runner.run_root
    if ($rr -and (Test-Path -LiteralPath $rr)) {
      try {
        $porcelain = & git -C $rr status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and -not $porcelain) {
          # RUNNER-LIVE says retained-dirty, but worktree is clean.
          # Mismatch.
          $drifts += [ordered]@{
            type   = 'retained-dirty-but-worktree-clean'
            detail = "RUNNER-LIVE.json claims phase='retained-dirty' with run_root='$rr', but `git status --porcelain` on that worktree returns no changes. The WIP was either committed elsewhere or discarded; RUNNER-LIVE is stale. Recovery: write a runner state update with phase='removed-clean' and prune the stale worktree, OR re-run the iter."
          }
        }
      } catch { }
    } elseif ($rr -and -not (Test-Path -LiteralPath $rr)) {
      # The worktree path doesn't even exist — also a mismatch.
      $drifts += [ordered]@{
        type   = 'retained-dirty-but-worktree-missing'
        detail = "RUNNER-LIVE.json claims phase='retained-dirty' with run_root='$rr', but that path doesn't exist on disk. The worktree was removed externally; RUNNER-LIVE is stale."
      }
    }
  }
}

# --- check 2: stale draft PRs --------------------------------------------

if (-not $skipDraftCheck) {
  $ghOk = $false
  try {
    $null = & gh --version 2>$null
    if ($LASTEXITCODE -eq 0) { $ghOk = $true }
  } catch { }

  if ($ghOk) {
    try {
      $rawJson = & gh pr list --state open --draft --author '@me' --json number,title,headRefName,updatedAt,url --limit 50 2>$null
      if ($LASTEXITCODE -eq 0 -and $rawJson) {
        $prs = @($rawJson | ConvertFrom-Json -ErrorAction Stop)
        $cutoff = (Get-Date).ToUniversalTime().AddHours(-$stalePrHours)
        foreach ($pr in $prs) {
          if ($draftBranchPrefix -and -not ([string]$pr.headRefName).StartsWith($draftBranchPrefix)) { continue }
          $u = [DateTime]::Parse([string]$pr.updatedAt).ToUniversalTime()
          if ($u -lt $cutoff) {
            $ageHours = [int][math]::Round(((Get-Date).ToUniversalTime() - $u).TotalHours)
            $drifts += [ordered]@{
              type   = 'stale-draft-pr'
              detail = "Open draft PR #$($pr.number) ('$($pr.title)') on branch '$($pr.headRefName)' has not been updated in $ageHours hours (cap=$stalePrHours h). Per PROMPT.md idle-upkeep policy (Row 10), the autopilot should sweep stale auto-PRs and either rebase, escalate, or close. URL: $($pr.url)"
              pr_number = $pr.number
              pr_url    = [string]$pr.url
              age_hours = $ageHours
            }
          }
        }
      }
    } catch {
      Write-Warning "[stale-state] gh pr list failed: $_"
    }
  } else {
    Write-Host "[stale-state] gh CLI not available — skipping draft PR check"
  }
} else {
  Write-Host "[stale-state] skip_draft_pr_check=true in config — skipping draft PR check"
}

# --- result ---------------------------------------------------------------

if ($drifts.Count -eq 0) {
  Write-Host "[stale-state] OK — no retained-dirty mismatch, no stale draft PRs (cap=${stalePrHours}h)"
  exit 0
}

foreach ($d in $drifts) {
  $row = [ordered]@{
    ts     = (Get-Date -Format 'o')
    run_id = $runId
    event  = 'stale-state-detected'
    result = $d.type
    detail = $d.detail
  }
  if ($d.PSObject.Properties.Name -contains 'pr_number') {
    $row['pr_number'] = $d.pr_number
    $row['pr_url']    = $d.pr_url
    $row['age_hours'] = $d.age_hours
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
}

Write-Host ""
Write-Host "[stale-state] STALE STATE DETECTED ($($drifts.Count))" -ForegroundColor Red
foreach ($d in $drifts) {
  Write-Host ("  [{0}] {1}" -f $d.type, $d.detail)
}
Write-Host "  $($drifts.Count) drift event(s) appended to FAILURES.jsonl"

if ($Soft) {
  Write-Host ""
  Write-Host "[stale-state] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
