# Validate-PrLanguage.ps1
#
# Round-7 F72 — PR-title language enforcement (closes the
# scenario-7 gap: CLAUDE.md row 67-71 declared the PR-language
# convention but nothing enforced it; the OPERATOR-LIVE.html PR
# panel surfaced `lang_mismatch` only after the PR existed).
#
# Bidirectional check (round-7 F73 expansion of F72):
#   - CJK operator (ko / ja / zh) + autopilot-authored PR title
#     with zero CJK glyphs (after stripping a leading
#     conventional-commit prefix like `fix:` / `feat:` / `chore:`)
#     → flag as `pr-language-mismatch-cjk-body-missing`. The
#     operator's dashboard expects their language; English-only
#     titles create friction.
#   - non-CJK operator (en, default) + PR title that DOES contain
#     CJK glyphs in the body → flag as
#     `pr-language-mismatch-unexpected-cjk`. An English-locale
#     operator reading their dashboard wouldn't expect ko/ja/zh
#     body text mixed in.
#
# Universal: works for any operator language. The CJK-glyph
# detection covers Hiragana / Katakana / CJK Unified / Hangul.
# Future extensions (Cyrillic / Arabic / Greek / Devanagari) can
# add their respective Unicode-range checks behind a similar
# bidirectional gate.
#
# This validator runs at pre-commit time AND can be invoked
# standalone. It calls `gh pr list --author @me` so it only flags
# PRs the autopilot loop itself opened — operator-authored PRs
# (different author) are not flagged.
#
# Configuration (`.autopilot/config.json`, optional):
#   skip_pr_language_check  : bool — true to skip entirely.
#   pr_language_skip_branch_prefix : string — only flag PRs whose
#                            head branch starts with this prefix
#                            (default empty = all PRs by @me).
#
# Drift kinds:
#   `cjk-body-missing`     — CJK operator, PR body has zero CJK
#                            glyphs (the F72 case).
#   `unexpected-cjk`       — non-CJK operator, PR body has CJK
#                            glyphs (round-7 F73 expansion).
#
# Both are emitted under the parent event `pr-language-mismatch`.
#
# Soft-deployed (run with `-Soft`): drift is logged with run_id
# correlation but does not block the commit.
#
# Usage:
#   pwsh tools/Validate-PrLanguage.ps1 -AutopilotRoot .autopilot -Soft
#
# Exit codes:
#   0 — no drift, OR -Soft, OR no config, OR gh missing,
#       OR skip_pr_language_check, OR non-CJK operator.
#   1 — drift detected (hard mode only).

param(
  [string]$AutopilotRoot = '.autopilot',
  [switch]$Soft
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AutopilotRoot)) { exit 0 }

$cfgPath      = Join-Path $AutopilotRoot 'config.json'
$failuresPath = Join-Path $AutopilotRoot 'FAILURES.jsonl'

if (-not (Test-Path -LiteralPath $cfgPath)) {
  Write-Host "[pr-language] no config.json (skip)"
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# --- config + operator_language detection --------------------------------

$skip = $false
$branchPrefix = ''
$operatorLang = ''
try {
  $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
  if ($cfg.PSObject.Properties.Name -contains 'skip_pr_language_check') {
    $skip = [bool]$cfg.skip_pr_language_check
  }
  if ($cfg.PSObject.Properties.Name -contains 'pr_language_skip_branch_prefix') {
    $branchPrefix = [string]$cfg.pr_language_skip_branch_prefix
  }
  if ($cfg.PSObject.Properties.Name -contains 'operator_language') {
    $operatorLang = [string]$cfg.operator_language
  }
} catch { }

if ($skip) { Write-Host "[pr-language] skip_pr_language_check=true — skipping"; exit 0 }
if (-not $operatorLang) { Write-Host "[pr-language] operator_language not set — skipping"; exit 0 }

$primaryLang = ($operatorLang -split '[-_]')[0].ToLowerInvariant()
$operatorIsCjk = $primaryLang -in @('ko','ja','zh')

# --- gh availability ------------------------------------------------------

$ghOk = $false
try {
  $null = & gh --version 2>$null
  if ($LASTEXITCODE -eq 0) { $ghOk = $true }
} catch { }
if (-not $ghOk) {
  Write-Host "[pr-language] gh CLI not available — skipping"
  exit 0
}

# --- collect own open PRs -------------------------------------------------

$rawJson = ''
try {
  $rawJson = & gh pr list --state open --author '@me' --json number,title,headRefName,url --limit 50 2>$null
} catch { }
if ($LASTEXITCODE -ne 0 -or -not $rawJson) {
  Write-Host "[pr-language] gh pr list returned no data — skipping"
  exit 0
}

$prs = @()
try { $prs = @($rawJson | ConvertFrom-Json -ErrorAction Stop) } catch { exit 0 }
if ($prs.Count -eq 0) {
  Write-Host "[pr-language] no open PRs by @me"
  exit 0
}

# --- mismatch heuristic (bidirectional, round-7 F73) --------------------

function Get-TitleBody([string]$Title) {
  if (-not $Title) { return '' }
  if ($Title -match '^[a-z]+(\([^)]+\))?:\s*(.+)$') { return $Matches[2] }
  return $Title
}

function Test-HasCjk([string]$Body) {
  if (-not $Body) { return $false }
  return ($Body -match '[぀-ヿ㐀-䶿一-鿿가-힯]')
}

$drifts = @()
foreach ($pr in $prs) {
  $branch = [string]$pr.headRefName
  if ($branchPrefix -and -not $branch.StartsWith($branchPrefix)) { continue }
  $title = [string]$pr.title
  $body = Get-TitleBody $title
  $hasCjk = Test-HasCjk $body

  $driftType = ''
  $detail = ''
  if ($operatorIsCjk -and -not $hasCjk) {
    $driftType = 'cjk-body-missing'
    $detail = "Open PR #$($pr.number) ('$title') has no $primaryLang glyphs in the title body. CLAUDE.md PR-language convention requires titles in operator_language='$operatorLang'. Rename the PR (gh pr edit $($pr.number) --title '...') or add operator-language body text after the conventional-commit prefix."
  }
  elseif (-not $operatorIsCjk -and $hasCjk) {
    $driftType = 'unexpected-cjk'
    $detail = "Open PR #$($pr.number) ('$title') contains CJK glyphs in the title body, but operator_language='$operatorLang' (non-CJK). The operator's dashboard expects their language; mixed-script PR titles create friction. Rename the PR (gh pr edit $($pr.number) --title '...') in the operator's language."
  }

  if ($driftType) {
    $drifts += [pscustomobject]@{
      type      = $driftType
      pr_number = [int]$pr.number
      pr_title  = $title
      pr_url    = [string]$pr.url
      branch    = $branch
      detail    = $detail
    }
  }
}

# --- de-dup --------------------------------------------------------------

$existingTail = @()
if (Test-Path -LiteralPath $failuresPath) {
  try { $existingTail = @(Get-Content -LiteralPath $failuresPath -Tail 30 -Encoding utf8) } catch { }
}

function Test-RecentDriftEcho($prNumber, $type) {
  # Dedup on (pr_number, result-type). Different mismatch kinds on
  # the same PR (e.g., title was renamed and now triggers a
  # different drift class) emit independently so the operator sees
  # the new state.
  for ($i = $existingTail.Count - 1; $i -ge 0; $i--) {
    $ln = $existingTail[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $r = $ln | ConvertFrom-Json -ErrorAction Stop
      if (-not ($r.PSObject.Properties.Name -contains 'event' -and [string]$r.event -eq 'pr-language-mismatch')) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'pr_number' -and [int]$r.pr_number -eq $prNumber)) { continue }
      if (-not ($r.PSObject.Properties.Name -contains 'result' -and [string]$r.result -eq $type)) { continue }
      return $true
    } catch { }
  }
  return $false
}

# --- emit ----------------------------------------------------------------

if ($drifts.Count -eq 0) {
  Write-Host "[pr-language] OK — no language mismatch on $($prs.Count) open PR(s)"
  exit 0
}

function Write-DriftRow {
  param([string]$Path, [hashtable]$Row)
  try {
    $line = ($Row | ConvertTo-Json -Compress -Depth 6) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
  } catch { Write-Warning "[pr-language] failed to append: $_" }
}

$runId = if ($env:AUTOPILOT_RUN_ID) { $env:AUTOPILOT_RUN_ID } else { '' }
$emitted = 0

foreach ($d in $drifts) {
  if (Test-RecentDriftEcho -prNumber $d.pr_number -type $d.type) {
    Write-Host ("  [{0}] PR #{1}: same drift already in FAILURES tail — skipping" -f $d.type, $d.pr_number)
    continue
  }
  $row = [ordered]@{
    ts        = (Get-Date -Format 'o')
    run_id    = $runId
    event     = 'pr-language-mismatch'
    result    = $d.type
    pr_number = $d.pr_number
    pr_title  = $d.pr_title
    pr_url    = $d.pr_url
    branch    = $d.branch
    detail    = $d.detail
  }
  $h = @{}
  foreach ($k in $row.Keys) { $h[$k] = $row[$k] }
  Write-DriftRow -Path $failuresPath -Row $h
  $emitted++
}

Write-Host ""
Write-Host "[pr-language] DRIFT DETECTED ($($drifts.Count) total, $emitted emitted)" -ForegroundColor Red
foreach ($d in $drifts) {
  Write-Host ("  [{0}] PR #{1}: '{2}'" -f $d.type, $d.pr_number, $d.pr_title)
}

if ($Soft) {
  Write-Host ""
  Write-Host "[pr-language] -Soft mode: drift logged, returning exit 0." -ForegroundColor Yellow
  exit 0
}

exit 1
