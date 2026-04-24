# .autopilot/runners/stalled-fallback.ps1
#
# Called by runner.ps1 when an iter leaves the worktree dirty (retained-dirty).
# Goal: don't lose the work. First snapshot dirty files into .autopilot/stalled/
# in the MAIN repo, then try to turn the dirty worktree into a branch + draft PR.
#
# Return values (written to stdout, one token per line; last line is the final state):
#   not-dirty                         — nothing to rescue
#   missing-run-root                  — worktree path doesn't exist
#   wip-rescued                       — snapshot + commit + push + draft PR all worked
#   wip-local-only-snapshotted        — snapshot + commit ok, push or PR failed
#   wip-commit-failed-snapshotted     — snapshot ok, commit itself failed
#   wip-failed-no-snapshot            — even the snapshot step failed
#
# Never calls git with --no-verify. If pre-commit is itself the blocker, the
# failure is surfaced loudly (snapshot is still taken so work is not lost).

param(
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$AutopilotRoot,
  [int]$Iter = 0
)

$ErrorActionPreference = 'Continue'
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$metricsPath = Join-Path $AutopilotRoot 'METRICS.jsonl'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'
$snapshotRoot = Join-Path $AutopilotRoot 'stalled'

function Write-MetricsLine {
  param([hashtable]$Row)
  try {
    $Row['ts'] = (Get-Date).ToString('o')
    if ($Iter -gt 0) { $Row['iter'] = $Iter }
    ($Row | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $metricsPath -Encoding utf8
  } catch {
    Write-Host "[stalled-fallback] metrics write failed: $_"
  }
}

function Write-FailureLine {
  param([hashtable]$Row)
  try {
    $Row['ts'] = (Get-Date).ToString('o')
    if ($Iter -gt 0) { $Row['iter'] = $Iter }
    ($Row | ConvertTo-Json -Compress -Depth 8) | Add-Content -Path $failuresPath -Encoding utf8
  } catch {
    Write-Host "[stalled-fallback] failures write failed: $_"
  }
}

if (-not (Test-Path $RunRoot)) {
  Write-Host "[stalled-fallback] missing run-root: $RunRoot"
  Write-MetricsLine @{ event = 'stalled-fallback'; result = 'missing-run-root'; run_root = $RunRoot }
  return 'missing-run-root'
}

$status = (git -C $RunRoot status --porcelain 2>$null)
if (-not $status) {
  return 'not-dirty'
}

# --- Step 1: snapshot dirty files into .autopilot/stalled/<ts>/ ------------
$snapshot = Join-Path $snapshotRoot $ts
try {
  New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
  $manifestPath = Join-Path $snapshot 'MANIFEST.txt'
  Set-Content -Path $manifestPath -Value "stalled iter $ts; source=$RunRoot`n" -Encoding utf8

  $files = @()
  foreach ($line in $status -split "`r?`n") {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    # Porcelain format: "XY <path>" where XY is 2 status chars
    $rel = $line.Substring(3)
    # Handle rename: "XY old -> new" — keep the `new` path
    if ($rel -match ' -> ') { $rel = ($rel -split ' -> ', 2)[1] }
    $rel = $rel.Trim('"')
    $files += $rel
  }

  foreach ($rel in $files) {
    $src = Join-Path $RunRoot $rel
    if (-not (Test-Path $src)) {
      # Deleted file: record in manifest, no copy
      Add-Content -Path $manifestPath -Value "DELETED: $rel" -Encoding utf8
      continue
    }
    $dst = Join-Path $snapshot $rel
    $dstDir = Split-Path $dst -Parent
    if ($dstDir) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
    Add-Content -Path $manifestPath -Value "COPIED: $rel" -Encoding utf8
  }
  Write-Host "[stalled-fallback] snapshot saved to $snapshot ($($files.Count) files)"
} catch {
  Write-Host "[stalled-fallback] snapshot failed: $_"
  Write-FailureLine @{ event = 'stalled-fallback'; step = 'snapshot'; error = "$_"; run_root = $RunRoot }
  return 'wip-failed-no-snapshot'
}

# --- Step 2: try WIP commit (no --no-verify) -------------------------------
$branch = "autopilot/wip-rescue-$ts"
$commitMsg = @"
wip(autopilot): iter stalled — auto WIP rescue at $ts

runner 가 감지한 자동 구조 commit 이다.
AI CLI 가 clean 한 commit 을 만들지 못한 채 워크트리를 dirty 로 남겨서,
변경 내용을 잃지 않도록 runner 가 대신 올린다.

snapshot: .autopilot/stalled/$ts/
run_root: $RunRoot
"@

try {
  git -C $RunRoot add -A 2>&1 | Out-Null
  # Commit respects pre-commit hooks. If they fail, the failure is visible.
  $commitOutput = (git -C $RunRoot commit -m $commitMsg 2>&1)
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[stalled-fallback] commit failed (pre-commit or index):"
    Write-Host $commitOutput
    Write-FailureLine @{
      event = 'stalled-fallback'
      step = 'commit'
      error = ($commitOutput -join "`n")
      run_root = $RunRoot
      snapshot = $snapshot
    }
    Write-MetricsLine @{
      event = 'stalled-fallback'
      result = 'wip-commit-failed-snapshotted'
      snapshot = $snapshot
    }
    return 'wip-commit-failed-snapshotted'
  }
  # Rescue from detached HEAD: create branch at current HEAD.
  git -C $RunRoot switch -c $branch 2>&1 | Out-Null
} catch {
  Write-Host "[stalled-fallback] commit step exception: $_"
  Write-FailureLine @{ event = 'stalled-fallback'; step = 'commit-exception'; error = "$_"; run_root = $RunRoot }
  Write-MetricsLine @{ event = 'stalled-fallback'; result = 'wip-commit-failed-snapshotted'; snapshot = $snapshot }
  return 'wip-commit-failed-snapshotted'
}

# --- Step 3: push + draft PR ----------------------------------------------
$pushOk = $false
$prUrl = ''
try {
  $pushOutput = (git -C $RunRoot push -u origin $branch 2>&1)
  if ($LASTEXITCODE -eq 0) {
    $pushOk = $true
  } else {
    Write-Host "[stalled-fallback] push failed:"
    Write-Host $pushOutput
    Write-FailureLine @{ event = 'stalled-fallback'; step = 'push'; error = ($pushOutput -join "`n"); branch = $branch }
  }
} catch {
  Write-FailureLine @{ event = 'stalled-fallback'; step = 'push-exception'; error = "$_"; branch = $branch }
}

if ($pushOk) {
  try {
    $prBody = @"
Runner 자동 구조 commit입니다. iter가 clean한 commit을 만들지 못하고 워크트리를 retained-dirty로 남겨서 runner가 대신 올렸습니다.

변경 내용 검토 후 필요하면 정리/리베이스하여 본격 PR로 만드세요. 필요 없으면 branch와 함께 닫아 주세요.

- snapshot: .autopilot/stalled/$ts/
- run_root: $RunRoot
- iter: $Iter
"@
    $prOutput = (gh pr create --draft --base main --head $branch `
      --title "wip(autopilot): stalled-iter 자동 WIP 구조 ($ts)" `
      --body $prBody 2>&1)
    if ($LASTEXITCODE -eq 0) {
      # gh prints PR URL on success
      $prUrl = ($prOutput | Select-String -Pattern 'https?://\S+' | ForEach-Object { $_.Matches[0].Value } | Select-Object -First 1)
    } else {
      Write-Host "[stalled-fallback] PR create failed:"
      Write-Host $prOutput
      Write-FailureLine @{ event = 'stalled-fallback'; step = 'pr-create'; error = ($prOutput -join "`n"); branch = $branch }
    }
  } catch {
    Write-FailureLine @{ event = 'stalled-fallback'; step = 'pr-exception'; error = "$_"; branch = $branch }
  }
}

# --- Step 4: clean worktree so next iter starts fresh ----------------------
# Only clean if commit succeeded. If it failed we leave the worktree for
# forensics; next iter's New-IterationWorktree will force-remove it but the
# snapshot under .autopilot/stalled/ preserves the files.
try {
  git worktree remove --force $RunRoot 2>&1 | Out-Null
} catch {
  Write-Host "[stalled-fallback] worktree cleanup warning: $_"
}

# --- Step 5: final metrics row --------------------------------------------
$finalState = if ($prUrl) { 'wip-rescued' } elseif ($pushOk) { 'wip-local-only-snapshotted' } else { 'wip-local-only-snapshotted' }
Write-MetricsLine @{
  event = 'stalled-fallback'
  result = $finalState
  branch = $branch
  pr_url = $prUrl
  snapshot = $snapshot
  push_ok = $pushOk
}
return $finalState
