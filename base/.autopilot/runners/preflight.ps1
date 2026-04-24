# .autopilot/runners/preflight.ps1
#
# Called once per iter BEFORE New-IterationWorktree. Verifies the environment
# can actually produce a PR. If any critical check fails, returns a non-zero
# exit code and the runner skips this iter (sleep + retry). Consecutive
# failures are tracked by runner.ps1 which may then set HALT.
#
# Checks:
#   - gh CLI installed + authenticated (needed for PR create)
#   - AI CLI available for AUTOPILOT_AI (codex or claude)
#   - git command works + origin remote set
#   - .autopilot/PROMPT.md exists (Row 12: empty-prompt infinite error loop)
#   - Optional project-specific verify hook at .autopilot/hooks/preflight-verify.ps1
#     (Row 8 slot — runtime checks like Unity MCP availability)
#
# Output: final line is one of:
#   preflight-ok
#   preflight-failed:<reason>

param(
  [Parameter(Mandatory)][string]$AutopilotRoot,
  [string]$Ai = 'codex'
)

$ErrorActionPreference = 'Continue'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

function Write-FailureLine {
  param([hashtable]$Row)
  try {
    $Row['ts'] = (Get-Date).ToString('o')
    ($Row | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $failuresPath -Encoding utf8
  } catch { }
}

$problems = New-Object System.Collections.Generic.List[string]

# 1. git available + origin remote
try {
  $gitVersion = (& git --version 2>&1)
  if ($LASTEXITCODE -ne 0) { $problems.Add('git-missing') }
  $origin = (& git remote get-url origin 2>&1)
  if ($LASTEXITCODE -ne 0) { $problems.Add('git-no-origin') }
} catch {
  $problems.Add("git-exception:$_")
}

# 2. gh CLI + auth
try {
  $ghVersion = (& gh --version 2>&1)
  if ($LASTEXITCODE -ne 0) {
    $problems.Add('gh-missing')
  } else {
    $ghAuth = (& gh auth status 2>&1)
    if ($LASTEXITCODE -ne 0) {
      $problems.Add('gh-auth-failed')
    }
  }
} catch {
  $problems.Add("gh-exception:$_")
}

# 3. AI CLI present
switch ($Ai) {
  'codex' {
    try {
      $codexVersion = (& codex --version 2>&1)
      if ($LASTEXITCODE -ne 0) { $problems.Add('codex-missing') }
    } catch {
      $problems.Add("codex-exception:$_")
    }
  }
  'claude' {
    try {
      $claudeVersion = (& claude --version 2>&1)
      if ($LASTEXITCODE -ne 0) { $problems.Add('claude-missing') }
    } catch {
      $problems.Add("claude-exception:$_")
    }
  }
  'custom' {
    # custom uses AUTOPILOT_CMD; can't preflight generically
  }
  default {
    $problems.Add("unknown-ai:$Ai")
  }
}

# 4. PROMPT.md exists (Row 12: empty-prompt infinite loop)
$promptPath = Join-Path $AutopilotRoot 'PROMPT.md'
if (-not (Test-Path $promptPath)) {
  $problems.Add('prompt-missing')
}

# 5. Optional project-specific verify hook (Row 8 slot — static config checks)
$verifyHook = Join-Path $AutopilotRoot 'hooks/preflight-verify.ps1'
if (Test-Path $verifyHook) {
  try {
    & $verifyHook -AutopilotRoot $AutopilotRoot 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
      $problems.Add("verify-hook-failed:$LASTEXITCODE")
    }
  } catch {
    $problems.Add("verify-hook-exception:$_")
  }
}

# 6. Optional runtime-bridge hook (distinct from verify-hook).
#    verify-hook asserts static config; runtime-bridge asserts the external
#    tool actually responds to a 1-call health ping (Unity MCP, Claude Preview,
#    DB, etc.). "doctor green" is not enough — reachable != responsive.
#    Failures here are treated as soft: runtime-evidence claims this iter
#    are not trustworthy, but the iter can still do doc-only work.
$bridgeHook = Join-Path $AutopilotRoot 'hooks/preflight-runtime-bridge.ps1'
if (Test-Path $bridgeHook) {
  try {
    & $bridgeHook -AutopilotRoot $AutopilotRoot 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
      # Soft warning, not a hard fail — emit a marker the prompt can read.
      Write-FailureLine @{ event = 'preflight-runtime-bridge'; result = 'unresponsive'; exit = $LASTEXITCODE; ai = $Ai }
      Write-Host "[preflight] runtime-bridge unresponsive (exit=$LASTEXITCODE) — doc-only iter recommended"
    }
  } catch {
    Write-FailureLine @{ event = 'preflight-runtime-bridge'; result = 'exception'; err = ("$_"); ai = $Ai }
  }
}

if ($problems.Count -gt 0) {
  $reason = ($problems -join ',')
  Write-Host "[preflight] FAILED: $reason"
  Write-FailureLine @{ event = 'preflight'; result = 'failed'; reason = $reason; ai = $Ai }
  Write-Output "preflight-failed:$reason"
  exit 1
}

Write-Host "[preflight] OK (ai=$Ai)"
Write-Output 'preflight-ok'
exit 0
