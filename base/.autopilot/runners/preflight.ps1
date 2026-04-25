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
  [string]$AutopilotRoot = '',
  [string]$Ai = ''
)

$ErrorActionPreference = 'Continue'

# Default AutopilotRoot: when an operator runs preflight directly from the
# project root (`pwsh .autopilot/runners/preflight.ps1`) the runner's auto-
# resolve isn't there, and a Mandatory param made it abort with a cryptic
# "missing mandatory parameters: AutopilotRoot" error (round-3 dogfood F3).
# Resolve to <pwd>/.autopilot when omitted; runner.{ps1,sh} still passes
# explicitly.
if (-not $AutopilotRoot) {
  $candidate = Join-Path (Get-Location).Path '.autopilot'
  if (Test-Path $candidate) {
    $AutopilotRoot = $candidate
  } else {
    Write-Error "[preflight] -AutopilotRoot not given and .\.autopilot not found from $(Get-Location)."
    exit 1
  }
}

# Default $Ai: when operator runs preflight standalone (no runner), -Ai is not
# passed. Round-3 F14: previously defaulted to 'codex' regardless of operator
# choice in apply, so a Claude operator would see preflight check codex CLI.
# Resolve in this priority order:
#   1. -Ai param  (runner passes this explicitly)
#   2. $env:AUTOPILOT_AI
#   3. config.json's `autopilot_ai`
#   4. 'codex' (template default)
if (-not $Ai) {
  if ($env:AUTOPILOT_AI) {
    $Ai = $env:AUTOPILOT_AI
  } else {
    $cfgPath = Join-Path $AutopilotRoot 'config.json'
    if (Test-Path $cfgPath) {
      try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($cfg.autopilot_ai) { $Ai = [string]$cfg.autopilot_ai }
      } catch { }
    }
    if (-not $Ai) { $Ai = 'codex' }
  }
}

$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

# Round-3 F31: same BOM-safe pattern as F30 (#49) — `-Encoding utf8` on
# Windows PowerShell 5.1 prepends a UTF-8 BOM to byte 0 of FAILURES.jsonl,
# breaking jq per-line parsing. F30 patched runner.ps1 + stalled-fallback.ps1
# but missed this preflight write. Use [IO.File]::AppendAllText with explicit
# UTF8Encoding($false) for cross-version safety.
$preflightUtf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-FailureLine {
  param([hashtable]$Row)
  try {
    $Row['ts'] = (Get-Date).ToString('o')
    # Round-4 F37: stamp run_id when set by the runner so this preflight
    # failure can be ledger-reconciled with the matching RUNNER-LIVE.json
    # phase entry. Empty string when preflight is invoked standalone.
    if ($env:AUTOPILOT_RUN_ID) { $Row['run_id'] = $env:AUTOPILOT_RUN_ID }
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($failuresPath, $line, $preflightUtf8NoBom)
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
  # Friendly hints for the most common bootstrap-time failures (round-3 F4).
  # Without these, a fresh-project operator sees an opaque token and stalls.
  foreach ($p in $problems) {
    switch -Wildcard ($p) {
      'git-no-origin' {
        Write-Host "  hint: this project has no GitHub remote yet. Create one with:" -ForegroundColor Yellow
        Write-Host "    gh repo create <owner>/<name> --source=. --remote=origin --private --push" -ForegroundColor Yellow
        Write-Host "  or, if the repo already exists on GitHub:" -ForegroundColor Yellow
        Write-Host "    git remote add origin https://github.com/<owner>/<name>.git && git push -u origin main" -ForegroundColor Yellow
      }
      'gh-not-installed' { Write-Host "  hint: install GitHub CLI from https://cli.github.com/ then run 'gh auth login'." -ForegroundColor Yellow }
      'gh-not-authed'    { Write-Host "  hint: run 'gh auth login' and choose GitHub.com + HTTPS + browser." -ForegroundColor Yellow }
      'ai-cli-missing*'  { Write-Host "  hint: see docs/cli-login-guide.md for installing claude/codex CLI." -ForegroundColor Yellow }
      'no-prompt-md'     { Write-Host "  hint: re-run apply.ps1 — .autopilot/PROMPT.md is missing." -ForegroundColor Yellow }
    }
  }
  Write-FailureLine @{ event = 'preflight'; result = 'failed'; reason = $reason; ai = $Ai }
  Write-Output "preflight-failed:$reason"
  exit 1
}

Write-Host "[preflight] OK (ai=$Ai)"
Write-Output 'preflight-ok'
exit 0
