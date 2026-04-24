<#
.SYNOPSIS
  autopilot-dad-template installer (Windows PowerShell).
.DESCRIPTION
  Run from the TARGET project root:
    iwr -useb https://raw.githubusercontent.com/mizan0515/autopilot-dad-template/main/apply.ps1 | iex
  or clone this repo and run .\apply.ps1 from target root.
#>

$ErrorActionPreference = 'Stop'

$TemplateUrl = if ($env:AUTOPILOT_TEMPLATE_URL) { $env:AUTOPILOT_TEMPLATE_URL } else { 'https://github.com/mizan0515/autopilot-dad-template.git' }
$Target = (Get-Location).Path
$Conflicts = Join-Path $Target '.apply-conflicts'

if (-not (Test-Path (Join-Path $Target '.git'))) {
  Write-Error "[apply] $Target is not a git repo. Run 'git init' first."
  exit 1
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ("autopilot-template-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $Work | Out-Null
try {
  Write-Host "[apply] fetching template from $TemplateUrl"
  git clone --depth 1 $TemplateUrl (Join-Path $Work 'template') 2>&1 | Out-Null

  New-Item -ItemType Directory -Path $Conflicts -Force | Out-Null
  $conflictCount = 0

  $tplRoot = Join-Path $Work 'template'
  Get-ChildItem -Path $tplRoot -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($tplRoot.Length + 1)
    if ($rel -like '.git\*' -or $rel -eq 'apply.sh' -or $rel -eq 'apply.ps1' -or $rel -eq 'README.md' -or $rel -eq 'LICENSE') {
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
        $conflictCount++
        Write-Host "[apply] conflict: $rel (saved to .apply-conflicts/)"
      }
    } else {
      New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
      Copy-Item $_.FullName $dst -Force
      Write-Host "[apply] installed: $rel"
    }
  }

  if ($conflictCount -eq 0) {
    if (Test-Path $Conflicts) { Remove-Item $Conflicts -Recurse -Force -ErrorAction SilentlyContinue }
  }

  if (Test-Path (Join-Path $Target '.autopilot/hooks')) {
    git config core.hooksPath .autopilot/hooks
    Write-Host "[apply] hooks registered (core.hooksPath=.autopilot/hooks)"
  }

  Write-Host ""
  if ($conflictCount -gt 0) {
    Write-Host "[apply] done with $conflictCount conflict(s). Review .apply-conflicts/ and merge manually."
    if ($conflictCount -ge 5) {
      Write-Error "[apply] WARNING: 5+ conflicts — stopping automatic apply. Report to operator."
      exit 2
    }
  } else {
    Write-Host "[apply] done. No conflicts."
  }

  Write-Host @"

Next steps:
  1. Edit .autopilot/PROMPT.md — replace <<PROJECT_NAME>>, <<PROJECT_DESCRIPTION>>, <<PRODUCT_DIRECTIVE>>
  2. Edit .autopilot/BACKLOG.md — replace seed tasks with real first items
  3. Commit: git add .autopilot && git commit -m "chore: apply autopilot-dad-template"
  4. Run first iter: paste .autopilot/RUN.claude-code.md into Claude Code desktop
"@
}
finally {
  if (Test-Path $Work) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }
}
