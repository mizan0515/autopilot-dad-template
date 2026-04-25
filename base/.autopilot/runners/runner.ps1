# .autopilot/runners/runner.ps1 — infinite Windows runner.
#
# Loop: create or refresh one reusable detached automation worktree -> submit
# PROMPT.md to the AI CLI -> remove the worktree if clean -> sleep NEXT_DELAY -> repeat.
# The runner is intentionally dumb. All reasoning lives in PROMPT.md.

$ErrorActionPreference = 'Stop'
# Round-3 F35: hardcoded `\` separators ('..\..') break on POSIX pwsh because
# Join-Path emits the literal string verbatim and Resolve-Path then tries to
# locate `..\..` literally instead of the parent-of-parent dir. PowerShell
# accepts `/` on Windows too, so `/` everywhere is the cross-platform choice.
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))

$root = (Get-Location).Path
$ap = Join-Path $root '.autopilot'
$halt = Join-Path $ap 'HALT'
$delay = Join-Path $ap 'NEXT_DELAY'
$runnerStatePath = Join-Path $ap 'RUNNER-LIVE.json'
$projectScript = Join-Path $ap 'project.ps1'
$promptRelative = if ($env:AUTOPILOT_PROMPT_RELATIVE) { $env:AUTOPILOT_PROMPT_RELATIVE } else { '.autopilot/PROMPT.md' }

function Get-WorktreeBase {
  if ($env:AUTOPILOT_WORKTREE_DIR) {
    return $env:AUTOPILOT_WORKTREE_DIR
  }

  $parent = Split-Path $root -Parent
  $leaf = Split-Path $root -Leaf
  return (Join-Path $parent "$leaf-autopilot-runner")
}

function Write-RunnerState {
  param(
    [string]$Phase,
    [string]$RunRoot = '',
    [string]$Note = '',
    [int]$LastExitCode = 0
  )

  $state = [ordered]@{
    ts = (Get-Date).ToString('o')
    ai = $ai
    phase = $Phase
    run_root = $RunRoot
    note = $Note
    last_exit_code = $LastExitCode
    worktree_base = (Get-WorktreeBase)
  }

  # Round-3 F30: `-Encoding utf8` on Windows PowerShell 5.1 writes UTF-8 WITH
  # BOM. Runtime JSON / JSONL across the template is BOM-less per F25
  # convention; PS5.1 BOM here breaks `jq` parsing of RUNNER-LIVE.json
  # downstream. Use [IO.File]::WriteAllText with explicit UTF8Encoding($false)
  # for cross-version safety (works on both Windows PowerShell 5.1 and
  # PowerShell 7+).
  $stateJson = $state | ConvertTo-Json -Depth 4
  [System.IO.File]::WriteAllText($runnerStatePath, $stateJson, (New-Object System.Text.UTF8Encoding $false))
  # Round-3 F23: this used to call `status-kr -RunRoot $RunRoot -Phase $Phase
  # -Note $Note -ExitCode $LastExitCode`, but project.ps1's ValidateSet does
  # NOT include `status-kr` and it has no -RunRoot / -Phase / -Note /
  # -ExitCode params. Result: every call was a silent ValidateSet/parameter-
  # binding failure swallowed by `| Out-Null`, so OPERATOR-LIVE.html was
  # NEVER refreshed in any template-applied repo. The phase/note context the
  # runner just wrote to RUNNER-LIVE.json IS what `status` reads, so the
  # extra args were redundant anyway. Now call just `status` and capture
  # stderr for diagnostics if it fails.
  #
  # Round-3 F36: previously hardcoded `& powershell ...` (Windows PowerShell
  # 5.1 binary), which doesn't exist on macOS/Linux pwsh hosts. The runner
  # itself can be invoked via pwsh on POSIX (e.g. on a developer Mac running
  # the loop), but the dashboard refresh would then throw "powershell:
  # command not found". Mirror runner.sh's pwsh-then-powershell resolver.
  $statusRunner = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' }
                  elseif (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' }
                  else { $null }
  if ($statusRunner) {
    $statusOut = & $statusRunner -NoProfile -ExecutionPolicy Bypass -File $projectScript status 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "[autopilot] dashboard refresh failed (exit=$LASTEXITCODE): $($statusOut -join '; ')"
    }
  } else {
    Write-Warning "[autopilot] dashboard refresh skipped: neither pwsh nor powershell on PATH"
  }
}

function New-IterationWorktree {
  $base = Get-WorktreeBase
  New-Item -ItemType Directory -Path $base -Force | Out-Null

  git fetch origin main --prune | Out-Null
  git worktree prune | Out-Null

  $runRoot = Join-Path $base 'live'
  if (Test-Path $runRoot) {
    try {
      git worktree remove --force $runRoot | Out-Null
    } catch {
      Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  git worktree add --detach $runRoot origin/main | Out-Null
  return $runRoot
}

function Finalize-IterationWorktree {
  param([string]$RunRoot)

  if (-not (Test-Path $RunRoot)) {
    return 'missing'
  }

  $status = (git -C $RunRoot status --porcelain 2>$null)
  if ($LASTEXITCODE -ne 0) {
    return 'status-failed'
  }

  if ($status) {
    return 'retained-dirty'
  }

  git worktree remove --force $RunRoot | Out-Null
  $parent = Split-Path $RunRoot -Parent
  if ($parent -and (Test-Path $parent) -and -not (Get-ChildItem $parent -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
  }
  return 'removed-clean'
}

# Resolve the autopilot AI in this priority order:
#   1. $env:AUTOPILOT_AI  (per-shell override)
#   2. .autopilot/config.json's `autopilot_ai` (operator's apply choice)
#   3. 'codex' (template default)
# Round-3 F14: config.json.autopilot_ai was written by apply.ps1 but never
# consumed — operators who answered "claude" still got codex preflight +
# execution unless they also exported AUTOPILOT_AI. That made the apply
# prompt cosmetic and silently broke the Claude-CLI path.
$ai = $null
if ($env:AUTOPILOT_AI) {
  $ai = $env:AUTOPILOT_AI
} else {
  $cfgPath = Join-Path $PSScriptRoot '../config.json'
  if (Test-Path $cfgPath) {
    try {
      $cfg = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      if ($cfg.autopilot_ai) { $ai = [string]$cfg.autopilot_ai }
    } catch {
      Write-Warning "[runner] failed to parse $cfgPath; falling back to codex. ($_)"
    }
  }
  if (-not $ai) { $ai = 'codex' }
}

# Timeout for a single AI CLI invocation. Default 25 min; clamped to [5, 120].
$llmTimeoutMin = 25
if ($env:AUTOPILOT_LLM_TIMEOUT_MIN -match '^\d+$') {
  $llmTimeoutMin = [int]$env:AUTOPILOT_LLM_TIMEOUT_MIN
  if ($llmTimeoutMin -lt 5) { $llmTimeoutMin = 5 }
  if ($llmTimeoutMin -gt 120) { $llmTimeoutMin = 120 }
}

# Consecutive-stall HALT threshold. After N iters that produced
# wip-commit-failed-snapshotted, wip-failed-no-snapshot, or preflight-failed
# in a row, runner writes HALT and stops. Default 5, clamp >= 2.
$stallHaltThreshold = 5
if ($env:AUTOPILOT_STALL_HALT_THRESHOLD -match '^\d+$') {
  $stallHaltThreshold = [int]$env:AUTOPILOT_STALL_HALT_THRESHOLD
  if ($stallHaltThreshold -lt 2) { $stallHaltThreshold = 2 }
}

$consecutiveStalls = 0

Write-Host "[autopilot] AI = $ai"
Write-Host "[autopilot] worktree base = $(Get-WorktreeBase)"
Write-Host "[autopilot] prompt = $promptRelative"
Write-Host "[autopilot] LLM timeout = ${llmTimeoutMin} min"
Write-Host "[autopilot] consecutive-stall HALT threshold = $stallHaltThreshold"
Write-RunnerState -Phase 'startup' -Note '러너를 시작했습니다.'

while ($true) {
  if (Test-Path $halt) {
    Write-Host "[autopilot] HALT file present. Stopping runner."
    Write-RunnerState -Phase 'halted' -Note 'HALT 파일이 있어 러너를 종료했습니다.'
    break
  }

  $iterStart = Get-Date
  $runRoot = $null
  $aiExitCode = 0
  $llmTimedOut = $false
  $preflightFailed = $false
  Write-Host "[autopilot] iteration start $($iterStart.ToString('o'))"

  # --- Preflight: gh auth + AI CLI + git origin ---------------------------
  $autopilotRoot = Split-Path -Parent $PSScriptRoot
  $preflightScript = Join-Path $PSScriptRoot 'preflight.ps1'
  if (Test-Path $preflightScript) {
    $pfOutput = & $preflightScript -AutopilotRoot $autopilotRoot -Ai $ai 2>&1
    $pfFinal = ($pfOutput | Select-Object -Last 1).ToString().Trim()
    Write-Host "[autopilot] preflight: $pfFinal"
    if ($pfFinal -notmatch '^preflight-ok$') {
      $preflightFailed = $true
      $aiExitCode = 2
      Write-RunnerState -Phase 'preflight-failed' -Note "환경 점검 실패: $pfFinal" -LastExitCode 2
    }
  }

  if (-not $preflightFailed) {
    try {
      $runRoot = New-IterationWorktree
      $prompt = Join-Path $runRoot $promptRelative
      if (-not (Test-Path $prompt)) {
        throw "Missing $prompt"
      }

      Write-RunnerState -Phase 'running' -RunRoot $runRoot -Note '새 자동 전용 작업 폴더에서 한 번 실행 중입니다.'

      # --- AI CLI call with hard timeout ----------------------------------
      $promptText = Get-Content -Raw $prompt
      $deadline = (Get-Date).AddMinutes($llmTimeoutMin)

      $job = Start-Job -ArgumentList $ai, $runRoot, $promptText, $env:AUTOPILOT_CODEX_ARGS, $env:AUTOPILOT_CMD -ScriptBlock {
        param($ai, $runRoot, $promptText, $codexArgsEnv, $customCmd)
        switch ($ai) {
          'codex' {
            $extraArgs = @()
            if ($codexArgsEnv) {
              $parseErrors = $null
              $extraArgs = [System.Management.Automation.PSParser]::Tokenize($codexArgsEnv, [ref]$parseErrors) |
                Where-Object { $_.Type -in 'CommandArgument', 'String' } |
                ForEach-Object { $_.Content }
            }
            $codexArgs = @('exec', '-C', $runRoot, '--dangerously-bypass-approvals-and-sandbox', '-') + $extraArgs
            $promptText | codex @codexArgs
            exit $LASTEXITCODE
          }
          'claude' {
            $promptText | claude --print
            exit $LASTEXITCODE
          }
          'custom' {
            $env:AUTOPILOT_PROMPT_TEXT = $promptText
            Push-Location $runRoot
            try {
              Invoke-Expression $customCmd
              exit $LASTEXITCODE
            } finally { Pop-Location }
          }
          default { exit 2 }
        }
      }

      $finished = Wait-Job -Job $job -Timeout ($llmTimeoutMin * 60)
      if (-not $finished) {
        Write-Warning "[autopilot] AI call exceeded ${llmTimeoutMin} min — killing."
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $llmTimedOut = $true
        $aiExitCode = 124
        try {
          # Round-3 F30: BOM-safe append — see Write-RunnerState comment.
          $failuresPath = Join-Path $autopilotRoot 'FAILURES.jsonl'
          $failureLine = @{ ts=(Get-Date).ToString('o'); event='llm-timeout'; ai=$ai; timeout_min=$llmTimeoutMin } |
            ConvertTo-Json -Compress
          [System.IO.File]::AppendAllText($failuresPath, $failureLine + "`n", (New-Object System.Text.UTF8Encoding $false))
        } catch { }
      } else {
        Receive-Job -Job $job -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        $aiExitCode = if ($job.ChildJobs[0].JobStateInfo.State -eq 'Completed') { 0 } else { 1 }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      }
    } catch {
      $aiExitCode = 1
      Write-Warning "[autopilot] AI call failed: $_"
      Write-RunnerState -Phase 'error' -RunRoot $runRoot -Note "$_" -LastExitCode $aiExitCode
    }
  }

  $finalState = if ($runRoot) { Finalize-IterationWorktree -RunRoot $runRoot } else { 'no-worktree' }

  # Stalled-fallback: iter left worktree dirty. Snapshot files, try WIP commit
  # + push + draft PR so the work is not lost and the operator sees the stall.
  if ($finalState -eq 'retained-dirty' -and $runRoot) {
    $fallbackScript = Join-Path $PSScriptRoot 'stalled-fallback.ps1'
    if (Test-Path $fallbackScript) {
      try {
        Write-RunnerState -Phase 'stalled-fallback' -RunRoot $runRoot -Note '워크트리가 dirty로 남아 자동 WIP 구조를 시도합니다.'
        $fallbackRoot = Split-Path -Parent $PSScriptRoot
        $fallbackResult = & $fallbackScript -RunRoot $runRoot -AutopilotRoot $fallbackRoot -Iter 0 2>&1
        $fallbackFinal = ($fallbackResult | Select-Object -Last 1).ToString().Trim()
        Write-Host "[autopilot] stalled-fallback result: $fallbackFinal"
        switch -Regex ($fallbackFinal) {
          '^wip-rescued$'                     { $finalState = 'wip-rescued' }
          '^wip-local-only-snapshotted$'      { $finalState = 'wip-local-only-snapshotted' }
          '^wip-commit-failed-snapshotted$'   { $finalState = 'wip-commit-failed-snapshotted' }
          '^wip-failed-no-snapshot$'          { $finalState = 'wip-failed-no-snapshot' }
        }
      } catch {
        Write-Warning "[autopilot] stalled-fallback error: $_"
      }
    }
  }

  # DAD dispatch: drain any tasks the autopilot queued during its turn. See
  # .autopilot/dispatch/README.md for the protocol.
  try {
    $autopilotRoot = Split-Path -Parent $PSScriptRoot
    $dispatcher = Join-Path $PSScriptRoot 'dispatch.ps1'
    $unityRoot = Split-Path -Parent $autopilotRoot
    if (Test-Path $dispatcher) {
      & $dispatcher -AutopilotRoot $autopilotRoot -WorkingDir $unityRoot
    }
  } catch {
    Write-Warning "[autopilot] dispatcher error: $_"
  }

  # Phase 6: probation gate — detect regressions from recent self-mods.
  try {
    $probationGate = Join-Path $PSScriptRoot 'probation-gate.ps1'
    if (Test-Path $probationGate) {
      & $probationGate -AutopilotRoot $autopilotRoot
    }
  } catch {
    Write-Warning "[autopilot] probation-gate error: $_"
  }

  $sleepPhase = 'sleeping'
  $sleepNote = ''

  # Consecutive-stall tracking: preflight-failed, llm-timeout, and unrecoverable
  # wip-* outcomes count as stalls. removed-clean or wip-rescued reset the count.
  $isStall = $preflightFailed -or $llmTimedOut -or
             $finalState -in @('wip-commit-failed-snapshotted', 'wip-failed-no-snapshot')
  if ($isStall) {
    $consecutiveStalls++
    Write-Host "[autopilot] consecutive stalls: $consecutiveStalls / $stallHaltThreshold"
    if ($consecutiveStalls -ge $stallHaltThreshold) {
      $haltReason = "연속 $consecutiveStalls 회 stall 로 runner 자동 HALT. 최근: $finalState. 원인 확인 후 .autopilot/HALT 파일을 삭제하고 재시작."
      Set-Content -Path $halt -Value $haltReason -Encoding utf8
      Write-Host "[autopilot] $haltReason"
      try {
        # Round-3 F30: BOM-safe append — see Write-RunnerState comment.
        $failuresPath = Join-Path $autopilotRoot 'FAILURES.jsonl'
        $haltFailureLine = @{ ts=(Get-Date).ToString('o'); event='consecutive-stall-halt'; consecutive=$consecutiveStalls; threshold=$stallHaltThreshold; final_state=$finalState } |
          ConvertTo-Json -Compress
        [System.IO.File]::AppendAllText($failuresPath, $haltFailureLine + "`n", (New-Object System.Text.UTF8Encoding $false))
      } catch { }
      Write-RunnerState -Phase 'halted' -Note $haltReason -LastExitCode $aiExitCode
      break
    }
  } else {
    $consecutiveStalls = 0
  }

  switch ($finalState) {
    'removed-clean' {
      $sleepPhase = 'sleeping'
      $sleepNote = '방금 실행은 깨끗하게 끝났고, 자동 전용 작업 폴더를 정리했습니다.'
    }
    'retained-dirty' {
      $sleepPhase = 'retained-dirty'
      $sleepNote = '마지막 실행 결과가 남아 있어 자동 전용 작업 폴더를 보존했습니다. 사용자 작업 폴더는 건드리지 않습니다.'
    }
    'wip-rescued' {
      $sleepPhase = 'wip-rescued'
      $sleepNote = 'iter가 dirty로 끝나서 runner가 자동 WIP commit + draft PR을 만들어 변경을 구조했습니다.'
    }
    'wip-local-only-snapshotted' {
      $sleepPhase = 'wip-local-only'
      $sleepNote = 'WIP commit은 만들었지만 push 또는 PR 생성이 실패했습니다. .autopilot/stalled/ 스냅샷을 확인하세요.'
    }
    'wip-commit-failed-snapshotted' {
      $sleepPhase = 'wip-commit-failed'
      $sleepNote = '자동 WIP commit이 pre-commit 훅 등에서 실패했지만 스냅샷은 .autopilot/stalled/에 저장됐습니다.'
    }
    'wip-failed-no-snapshot' {
      $sleepPhase = 'wip-failed'
      $sleepNote = '자동 WIP 구조가 전부 실패했습니다. .autopilot/FAILURES.jsonl을 확인하세요.'
    }
    default {
      $sleepPhase = 'sleeping'
      $sleepNote = "작업 폴더 정리 상태: $finalState"
    }
  }

  if ($preflightFailed) {
    $sleepPhase = 'preflight-failed'
    $sleepNote = '환경 점검(preflight) 실패로 이번 iter를 건너뜁니다. gh auth / codex / claude 상태를 확인하세요.'
  } elseif ($llmTimedOut) {
    $sleepPhase = 'llm-timeout'
    $sleepNote = "AI CLI가 ${llmTimeoutMin}분 안에 끝나지 않아 강제 종료했습니다. 다음 iter가 다시 시도합니다."
  }

  $sleepFor = 900
  if (Test-Path $delay) {
    $raw = (Get-Content $delay -Raw).Trim()
    if ($raw -match '^\d+$') {
      $sleepFor = [int]$raw
      if ($sleepFor -lt 60)   { $sleepFor = 60 }
      if ($sleepFor -gt 3600) { $sleepFor = 3600 }
    }
  }

  $dur = [int]((Get-Date) - $iterStart).TotalSeconds
  Write-Host "[autopilot] iter took ${dur}s; sleeping ${sleepFor}s"
  Write-RunnerState -Phase $sleepPhase -RunRoot $runRoot -Note "$sleepNote 최근 실행 시간 ${dur}초, 다음 대기 ${sleepFor}초" -LastExitCode $aiExitCode
  Start-Sleep -Seconds $sleepFor
}
