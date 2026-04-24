<#
.SYNOPSIS
  Autopilot project helper — status, dashboard, lifecycle.
.DESCRIPTION
  Usage:
    project.ps1 status                 Generate OPERATOR-LIVE.{json,html} in operator language.
    project.ps1 start                  Start the runner loop.
    project.ps1 stop                   Signal the runner to halt.
    project.ps1 resume                 Remove HALT marker.
    project.ps1 doctor                 Verify tool prerequisites.
    project.ps1 install-hooks          Register .autopilot/hooks with git.

  Loads .autopilot/config.json for project_name, operator_language, and locale strings from .autopilot/locales/<lang>/strings.json.
#>

[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [ValidateSet('status', 'start', 'stop', 'resume', 'doctor', 'install-hooks')]
  [string]$Verb = 'status'
)

$ErrorActionPreference = 'Stop'

$AutopilotRoot = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $AutopilotRoot
$ConfigPath = Join-Path $AutopilotRoot 'config.json'
$HaltPath = Join-Path $AutopilotRoot 'HALT'
$LockPath = Join-Path $AutopilotRoot 'LOCK'
$StatePath = Join-Path $AutopilotRoot 'STATE.md'
$BacklogPath = Join-Path $AutopilotRoot 'BACKLOG.md'
$HistoryPath = Join-Path $AutopilotRoot 'HISTORY.md'
$MetricsPath = Join-Path $AutopilotRoot 'METRICS.jsonl'
$DelayPath = Join-Path $AutopilotRoot 'NEXT_DELAY'
$DashboardJson = Join-Path $AutopilotRoot 'OPERATOR-LIVE.json'
$DashboardHtml = Join-Path $AutopilotRoot 'OPERATOR-LIVE.html'
$TemplateHtml = Join-Path $AutopilotRoot 'OPERATOR-TEMPLATE.html'

function Load-Config {
  if (-not (Test-Path $ConfigPath)) {
    throw "missing config: $ConfigPath — run apply.ps1 first"
  }
  return Get-Content $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Load-Strings([string]$Lang) {
  $stringsPath = Join-Path $AutopilotRoot "locales/$Lang/strings.json"
  if (-not (Test-Path $stringsPath)) {
    Write-Warning "locale $Lang not found, falling back to en"
    $stringsPath = Join-Path $AutopilotRoot 'locales/en/strings.json'
  }
  return Get-Content $stringsPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Get-Iteration {
  if (-not (Test-Path $MetricsPath)) { return 0 }
  $lines = @(Get-Content $MetricsPath -Encoding utf8 | Where-Object { $_.Trim() })
  return $lines.Count
}

function Get-RecentHistory([int]$Count = 5) {
  if (-not (Test-Path $HistoryPath)) { return @() }
  $lines = Get-Content $HistoryPath -Encoding utf8
  $entries = @()
  $buf = @()
  $header = $null
  foreach ($line in $lines) {
    if ($line -match '^##\s+iter\s+(\d+)') {
      if ($header) {
        $entries += [pscustomobject]@{ header = $header; body = ($buf -join ' ') }
      }
      $header = $line.TrimStart('#').Trim()
      $buf = @()
    } elseif ($header -and $line.Trim()) {
      $buf += $line.Trim()
    }
  }
  if ($header) {
    $entries += [pscustomobject]@{ header = $header; body = ($buf -join ' ') }
  }
  return $entries | Select-Object -First $Count
}

function Get-DadSessions([int]$Count = 5) {
  $sessions = @()
  $dir = Join-Path $RepoRoot 'Document/dialogue/sessions'
  if (-not (Test-Path $dir)) { return $sessions }
  $dirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First $Count
  foreach ($d in $dirs) {
    $stateFile = Join-Path $d.FullName 'state.json'
    if (-not (Test-Path $stateFile)) { continue }
    try {
      $s = Get-Content $stateFile -Raw -Encoding utf8 | ConvertFrom-Json
    } catch { continue }
    $passCount = 0; $totalCount = 0
    if ($s.contract_checkpoints) {
      foreach ($p in $s.contract_checkpoints.PSObject.Properties) {
        $totalCount++
        if ([string]$p.Value -eq 'PASS') { $passCount++ }
      }
    }
    $sessions += [pscustomobject]@{
      session_id = [string]$s.session_id
      status = [string]$s.session_status
      turn = [int]$s.current_turn
      pass = $passCount
      total = $totalCount
      task = [string]$s.task_summary
    }
  }
  return $sessions
}

function Get-OpenPrs {
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) { return @() }
  try {
    $json = gh pr list --state open --json number,title,url,headRefName,updatedAt,isDraft 2>$null
    if (-not $json) { return @() }
    return ($json | ConvertFrom-Json)
  } catch { return @() }
}

function Test-PrTitleLangMismatch {
  param([string]$Title, [string]$OperatorLang)
  if (-not $Title -or -not $OperatorLang) { return $false }
  $primary = ($OperatorLang -split '[-_]')[0].ToLowerInvariant()
  # CJK operators: warn when title has zero CJK characters (conventional-commit
  # prefix alone is allowed — we look at the body after the first colon).
  if ($primary -in 'ko','ja','zh') {
    $body = $Title
    if ($Title -match '^[a-z]+(\([^)]+\))?:\s*(.+)$') { $body = $Matches[2] }
    $hasCjk = ($body -match '[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7AF]')
    return -not $hasCjk
  }
  return $false
}

function ConvertTo-JsonCompact($obj) {
  return ($obj | ConvertTo-Json -Depth 12 -Compress)
}

function Invoke-Status {
  $cfg = Load-Config
  $lang = $cfg.operator_language
  if (-not $lang) { $lang = 'en' }
  $s = Load-Strings -Lang $lang

  $iter = Get-Iteration
  $history = @(Get-RecentHistory -Count 5)
  $dad = @(Get-DadSessions -Count 5)
  $prs = @(Get-OpenPrs)
  $delay = if (Test-Path $DelayPath) { (Get-Content $DelayPath -Raw).Trim() } else { '900' }
  $halt = Test-Path $HaltPath
  $locked = Test-Path $LockPath

  # Map DAD status → localized label
  $dadOut = @()
  foreach ($sess in $dad) {
    $key = $sess.status
    if (-not $s.status_labels.PSObject.Properties[$key]) { $key = 'unknown' }
    $label = $s.status_labels.$key
    $checkText = if ($sess.total -gt 0) { "$($sess.pass)/$($sess.total)" } else { '' }
    $taskText = $sess.task
    if ($taskText.Length -gt 180) { $taskText = $taskText.Substring(0, 177) + '...' }
    $dadOut += [ordered]@{
      session_id = $sess.session_id
      status_label = $label
      turn = $sess.turn
      checkpoints = $checkText
      task = $taskText
    }
  }

  $timeline = @()
  foreach ($h in $history) {
    $title = $h.header
    $summary = $h.body
    if ($summary.Length -gt 180) { $summary = $summary.Substring(0, 177) + '...' }
    $timeline += [ordered]@{ title = $title; summary = $summary }
  }

  $prOut = @()
  foreach ($p in $prs) {
    $prOut += [ordered]@{
      number = $p.number
      title = $p.title
      url = $p.url
      branch = $p.headRefName
      draft = $p.isDraft
      lang_mismatch = (Test-PrTitleLangMismatch -Title $p.title -OperatorLang $lang)
    }
  }

  $data = [ordered]@{
    meta = [ordered]@{
      generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
      project_name = $cfg.project_name
      locale = $lang
      template_version = $cfg.template_version
    }
    strings = $s
    summary = [ordered]@{
      iteration = $iter
      next_delay = $delay
      halted = $halt
      locked = $locked
      open_pr_count = $prOut.Count
    }
    timeline = $timeline
    dad_sessions = $dadOut
    prs = $prOut
  }

  $json = ConvertTo-JsonCompact $data
  [IO.File]::WriteAllText($DashboardJson, $json, (New-Object Text.UTF8Encoding $false))
  Write-Host "wrote $DashboardJson"

  if (Test-Path $TemplateHtml) {
    $tpl = Get-Content $TemplateHtml -Raw -Encoding utf8
    $html = $tpl.Replace('__OPERATOR_DASHBOARD_JSON__', $json)
    [IO.File]::WriteAllText($DashboardHtml, $html, (New-Object Text.UTF8Encoding $false))
    Write-Host "wrote $DashboardHtml"
  }
}

function Invoke-InstallHooks {
  git config core.hooksPath .autopilot/hooks
  Write-Host "hooks registered (core.hooksPath=.autopilot/hooks)"
}

function Invoke-Doctor {
  $missing = @()
  foreach ($cmd in 'git', 'gh', 'powershell') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { $missing += $cmd }
  }
  if ($missing.Count -gt 0) {
    Write-Error "missing: $($missing -join ', ')"
    exit 1
  }
  if (-not (Test-Path $ConfigPath)) { Write-Error "missing .autopilot/config.json"; exit 1 }
  Write-Host "doctor: OK"
}

function Invoke-Start {
  $runner = Join-Path $AutopilotRoot 'runners/runner.ps1'
  if (-not (Test-Path $runner)) { throw "runner missing: $runner" }
  & $runner
}

function Invoke-Stop {
  [IO.File]::WriteAllText($HaltPath, (Get-Date -Format 'o'))
  Write-Host "HALT marker written"
}

function Invoke-Resume {
  if (Test-Path $HaltPath) { Remove-Item $HaltPath -Force }
  Write-Host "HALT cleared"
}

switch ($Verb) {
  'status'        { Invoke-Status }
  'start'         { Invoke-Start }
  'stop'          { Invoke-Stop }
  'resume'        { Invoke-Resume }
  'doctor'        { Invoke-Doctor }
  'install-hooks' { Invoke-InstallHooks }
}
