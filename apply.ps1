<#
.SYNOPSIS
  autopilot-dad-template installer (Windows PowerShell).
.DESCRIPTION
  Run from the TARGET project root:
    .\apply.ps1                                      # interactive — prompts language, name, directive, PRD, relay
    .\apply.ps1 -Language en -Name "My Project"      # scripted
    $env:AUTOPILOT_TEMPLATE_URL = '...'; .\apply.ps1 # override template source

  Supported languages: en (default), ko, ja, zh-CN, es, fr, de, or any BCP-47 tag.
  For locales not shipped under locales/<lang>/, the English templates are used but
  operator_language in config.json is set to your chosen tag so the agent still renders
  status and dashboard output in that language.
#>

[CmdletBinding()]
param(
  [Alias('l')][string]$Language = '',
  [Alias('n')][string]$Name = '',
  [string]$Description = '',
  [string]$Directive = '',
  [string]$PrdPath = '',
  [string]$RelayPath = '',
  [Alias('y')][switch]$Yes
)

$ErrorActionPreference = 'Stop'

# Force UTF-8 console I/O so non-ASCII (Korean/Japanese/Chinese) filenames and
# operator-facing prompts render correctly in pwsh on Windows. Without this the
# default OEM/ANSI codepage produces mojibake like '12-�ƶ�-���-��å.md' in the
# install log, which makes Korean operators think the install was corrupted
# (round-3 dogfood F1). Files on disk were always fine — only stdout was wrong.
try {
  [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
  $OutputEncoding = [Text.UTF8Encoding]::new()
} catch {}

$TemplateUrl = if ($env:AUTOPILOT_TEMPLATE_URL) { $env:AUTOPILOT_TEMPLATE_URL } else { 'https://github.com/mizan0515/autopilot-dad-template.git' }
$Target = (Get-Location).Path
$Conflicts = Join-Path $Target '.apply-conflicts'
$TemplateVersion = 'v0'

if (-not (Test-Path (Join-Path $Target '.git'))) {
  Write-Error "[apply] $Target is not a git repo. Run 'git init' first."
  exit 1
}

function Prompt-IfEmpty {
  param([string]$Current, [string]$Question, [string]$Default = '')
  if ($Current) { return $Current }
  if ($Yes) { return $Default }
  $label = if ($Default) { "$Question [$Default]" } else { $Question }
  $ans = Read-Host $label
  if (-not $ans) { return $Default }
  return $ans
}

function Detect-Prd {
  param([string]$Root)
  $candidates = @(
    'PRD.md',
    'docs/PRD.md',
    'Document/PRD.md',
    '게임 규칙 명세서.md',
    'Document/게임 규칙 명세서.md',
    'ROADMAP.md',
    'product.md',
    'README.md',
    'Document/개발 계획서.md'
  )
  foreach ($c in $candidates) {
    $p = Join-Path $Root $c
    if (Test-Path $p) { return $c }
  }
  return ''
}

function Render-TopLevelMd {
  param(
    [string]$File,
    [string]$ProjectName,
    [string]$Directive,
    [string]$PrdPathValue,
    [string]$RelayPathValue,
    [string]$OperatorLang,
    [string]$GuardrailsBlock
  )
  if (-not (Test-Path $File)) { return }
  $t = [IO.File]::ReadAllText($File, [Text.UTF8Encoding]::UTF8)
  $t = $t.Replace('{{PROJECT_NAME}}', $ProjectName)
  $t = $t.Replace('{{PROJECT_DIRECTIVE}}', $Directive)
  $t = $t.Replace('{{PRD_PATH}}', $PrdPathValue)
  $t = $t.Replace('{{RELAY_REPO_PATH}}', $RelayPathValue)
  $t = $t.Replace('{{OPERATOR_LANG}}', $OperatorLang)
  $t = $t.Replace('{{PROJECT_GUARDRAILS_BLOCK}}', $GuardrailsBlock)
  # Agent-facing Markdown must be UTF-8 with BOM (see PROJECT-RULES.md).
  [IO.File]::WriteAllText($File, $t, (New-Object Text.UTF8Encoding $true))
}

Write-Host "[apply] autopilot-dad-template installer"
Write-Host ""
Write-Host "Supported operator languages: en (default), ko, ja, zh-CN, es, fr, de"
Write-Host "(Others work too — apply falls back to English templates but the agent"
Write-Host " will render status lines and dashboard text in your chosen language.)"
Write-Host ""

$Language    = Prompt-IfEmpty $Language    'Operator language (BCP-47, e.g. en, ko, ja)' 'en'
$Name        = Prompt-IfEmpty $Name        'Project name'                                  (Split-Path $Target -Leaf)
$Description = Prompt-IfEmpty $Description 'One-line project description'                  '(to be filled in)'
$Directive   = Prompt-IfEmpty $Directive   'Product directive (one paragraph)'             'Ship a working v1. Focus on user value; avoid premature abstraction.'

# PRD path — auto-detect, let operator override.
$prdDetected = Detect-Prd -Root $Target
$PrdPath     = Prompt-IfEmpty $PrdPath     "PRD / product doc path (auto-detected: '$prdDetected')" $prdDetected

# Relay repo path — optional; empty means relay is not installed on this machine.
$RelayPath   = Prompt-IfEmpty $RelayPath   'Relay repo path (optional; leave empty if none)' ''

if (-not $RelayPath) { $RelayPathDisplay = '(relay not installed on this machine)' } else { $RelayPathDisplay = $RelayPath }
if (-not $PrdPath)   { $PrdPathDisplay   = '(no PRD detected — declare in config.json doc_priority)' } else { $PrdPathDisplay = $PrdPath }

$GuardrailsBlock = "_(Operator: declare project-specific guardrails here. The autopilot loop will fill this in as it learns the project.)_"

$Work = Join-Path ([IO.Path]::GetTempPath()) ("autopilot-template-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $Work | Out-Null
try {
  Write-Host "[apply] fetching template from $TemplateUrl"
  git clone --depth 1 $TemplateUrl (Join-Path $Work 'template') 2>&1 | Out-Null

  $tplRoot = Join-Path $Work 'template'
  $tplBase = Join-Path $tplRoot 'base'
  $tplLoc  = Join-Path $tplRoot "locales/$Language"
  if (-not (Test-Path $tplLoc)) {
    Write-Host "[apply] locale '$Language' not shipped; using locales/en/ as fallback."
    $tplLoc = Join-Path $tplRoot 'locales/en'
  }

  New-Item -ItemType Directory -Path $Conflicts -Force | Out-Null
  $conflictCount = 0

  function Copy-Tree {
    param(
      [string]$Src,
      [string[]]$ExcludeRelative = @()
    )
    if (-not (Test-Path $Src)) { return }
    Get-ChildItem -Path $Src -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($Src.Length + 1)
      # Normalize to forward slashes for cross-platform exclude matching.
      $relNorm = $rel -replace '\\','/'
      if ($ExcludeRelative -contains $relNorm) {
        Write-Host "[apply] skip (locale-root, copied separately): $rel"
        return
      }
      $dst = Join-Path $Target $rel
      $dstDir = Split-Path $dst -Parent
      if (Test-Path $dst) {
        $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dst -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
          $cPath = Join-Path $Conflicts $rel
          New-Item -ItemType Directory -Path (Split-Path $cPath -Parent) -Force | Out-Null
          Copy-Item $_.FullName $cPath -Force
          $script:conflictCount++
          Write-Host "[apply] conflict: $rel (saved to .apply-conflicts/)"
        }
      } else {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        Copy-Item $_.FullName $dst -Force
        Write-Host "[apply] installed: $rel"
      }
    }
  }

  Copy-Tree -Src $tplBase
  # Locale tree: skip the locale-root strings.json — it is copied explicitly to
  # .autopilot/locales/<lang>/strings.json below. Without this exclude it bleeds
  # to the target repo root (round-3 dogfood F2).
  Copy-Tree -Src $tplLoc -ExcludeRelative @('strings.json')

  # --- config.json ---------------------------------------------------------
  $cfgPath = Join-Path $Target '.autopilot/config.json'
  if (Test-Path $cfgPath) {
    Write-Host "[apply] existing config.json preserved at $cfgPath"
  } else {
    New-Item -ItemType Directory -Path (Split-Path $cfgPath -Parent) -Force | Out-Null
    $cfg = [ordered]@{
      project_name        = $Name
      project_description = $Description
      product_directive   = $Directive
      operator_language   = $Language
      prd_path            = $PrdPath
      relay_repo_path     = $RelayPath
      search_roots        = @('src','lib','tests','docs','Document','Assets/Scripts','Assets/Tests','.autopilot','.agents','.prompts','tools')
      template_version    = $TemplateVersion
      autopilot_ai        = 'claude'
      next_delay_default  = 900
    }
    $json = $cfg | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($cfgPath, $json, (New-Object Text.UTF8Encoding $false))
    Write-Host "[apply] wrote $cfgPath"
  }

  # --- render PROMPT.md + PROMPT.lite.md placeholders ---------------------
  # Both prompts share the same {{PROJECT_NAME}} / {{OPERATOR_LANGUAGE}} /
  # {{PRODUCT_DIRECTIVE}} placeholders. Skipping the lite one leaves literal
  # {{...}} in the agent context the moment AUTOPILOT_PROMPT_RELATIVE switches
  # to maintenance mode (round-3 dogfood F5).
  foreach ($pn in @('PROMPT.md', 'PROMPT.lite.md')) {
    $promptPath = Join-Path $Target ".autopilot/$pn"
    if (Test-Path $promptPath) {
      $t = Get-Content $promptPath -Raw -Encoding utf8
      $t = $t.Replace('{{PROJECT_NAME}}', $Name)
      $t = $t.Replace('{{PROJECT_DESCRIPTION}}', $Description)
      $t = $t.Replace('{{PRODUCT_DIRECTIVE}}', $Directive)
      $t = $t.Replace('{{OPERATOR_LANGUAGE}}', $Language)
      [IO.File]::WriteAllText($promptPath, $t, (New-Object Text.UTF8Encoding $false))
      Write-Host "[apply] rendered placeholders in .autopilot/$pn"
    }
  }

  # --- render top-level agent MDs -----------------------------------------
  foreach ($md in @('PROJECT-RULES.md','DIALOGUE-PROTOCOL.md','AGENTS.md','CLAUDE.md','RTK.md')) {
    $mdPath = Join-Path $Target $md
    if (Test-Path $mdPath) {
      Render-TopLevelMd -File $mdPath `
        -ProjectName $Name -Directive $Directive `
        -PrdPathValue $PrdPathDisplay -RelayPathValue $RelayPathDisplay `
        -OperatorLang $Language -GuardrailsBlock $GuardrailsBlock
      Write-Host "[apply] rendered placeholders in $md"
    }
  }

  # --- locales dir (chosen + en fallback) ---------------------------------
  New-Item -ItemType Directory -Path (Join-Path $Target ".autopilot/locales/$Language") -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $Target '.autopilot/locales/en') -Force | Out-Null
  $enStr  = Join-Path $tplRoot 'locales/en/strings.json'
  $locStr = Join-Path $tplRoot "locales/$Language/strings.json"
  if (Test-Path $enStr)  { Copy-Item $enStr  (Join-Path $Target '.autopilot/locales/en/strings.json') -Force }
  if (Test-Path $locStr) { Copy-Item $locStr (Join-Path $Target ".autopilot/locales/$Language/strings.json") -Force }

  # --- Codex skill rebranding --------------------------------------------
  # If the template shipped default "cardgame-*" skills, rename them to the
  # project's slug and rewrite metadata via Set-CodexSkillNamespace.ps1.
  $skillsRoot = Join-Path $Target '.agents/skills'
  $setNsTool  = Join-Path $Target 'tools/Set-CodexSkillNamespace.ps1'
  if ((Test-Path $skillsRoot) -and (Test-Path $setNsTool)) {
    # Derive a safe lowercase slug from the project name.
    $slug = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-')
    if (-not $slug) { $slug = 'myproject' }
    # Only rebrand if shipped defaults are still present.
    $hasDefault = Test-Path (Join-Path $skillsRoot 'cardgame-dialogue-start')
    if ($hasDefault -and $slug -ne 'cardgame') {
      Write-Host "[apply] rebranding Codex skills: cardgame-* -> $slug-*"
      & $setNsTool -Namespace $slug -RepoRoot $Target -ProjectLabel $Name | Out-Null
    }
  }

  # --- hooks --------------------------------------------------------------
  # Prefer top-level .githooks/ (canonical validator chain).
  # Fall back to .autopilot/hooks/ for legacy layouts.
  $topHookDir = Join-Path $Target '.githooks'
  $legacyHookDir = Join-Path $Target '.autopilot/hooks'
  if (Test-Path $topHookDir) {
    git config core.hooksPath .githooks
    Write-Host "[apply] hooks registered (core.hooksPath=.githooks)"
    # Ensure pre-commit is executable on POSIX checkouts.
    $pre = Join-Path $topHookDir 'pre-commit'
    if ((Test-Path $pre) -and $IsLinux) { & chmod +x $pre 2>$null }
  } elseif (Test-Path $legacyHookDir) {
    git config core.hooksPath .autopilot/hooks
    Write-Host "[apply] hooks registered (core.hooksPath=.autopilot/hooks)"
  }

  if ($conflictCount -eq 0) {
    if (Test-Path $Conflicts) { Remove-Item $Conflicts -Recurse -Force -ErrorAction SilentlyContinue }
  }

  Write-Host ""
  if ($conflictCount -gt 0) {
    Write-Host "[apply] done with $conflictCount conflict(s). Review .apply-conflicts/ and merge manually."
    if ($conflictCount -ge 5) {
      Write-Error "[apply] STOP: 5+ conflicts. Operator review required."
      exit 2
    }
  } else {
    Write-Host "[apply] done. No conflicts."
  }

  Write-Host @"

Language: $Language
Project:  $Name
PRD path: $PrdPathDisplay
Relay:    $RelayPathDisplay

Next steps:
  1. Review .autopilot/config.json and .autopilot/BACKLOG.md (replace seed tasks).
  2. Review PROJECT-RULES.md / CLAUDE.md / AGENTS.md at repo root and fill in project-specific guardrails.
  3. git add .autopilot .githooks .github tools .claude .agents .prompts relay PROJECT-RULES.md DIALOGUE-PROTOCOL.md AGENTS.md CLAUDE.md RTK.md Document/ && git commit -m "chore: apply autopilot-dad-template"
  4. Make sure a GitHub remote exists (preflight will fail with 'git-no-origin' otherwise):
       gh repo create <owner>/<name> --source=. --remote=origin --private --push
     or if the repo already exists on GitHub:
       git remote add origin https://github.com/<owner>/<name>.git
       git push -u origin main
  5. First iter: paste .autopilot/RUN.claude-code.md into Claude Code desktop.
  6. (Optional) To enable MCP pass-through + centralized token budget, see relay/SETUP.md.
     Without a relay, DAD still works in user-bridged mode (copy/paste peer prompts).
"@
}
finally {
  if (Test-Path $Work) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }
}
