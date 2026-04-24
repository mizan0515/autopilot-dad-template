param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Fail {
    param([string]$Message)

    Write-Error $Message
    exit 1
}

$resolvedRoot = if ($Root) {
    (Resolve-Path -LiteralPath $Root).Path
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Push-Location $resolvedRoot
try {
    $gitRoot = git rev-parse --show-toplevel 2>$null
    if (-not $gitRoot) {
        Write-Output "Git repo not detected. Skip DAD decision workflow validation."
        exit 0
    }

    $currentBranch = (git branch --show-current).Trim()
    $decisionStatus = @(git status --porcelain --untracked-files=all -- "Document/dialogue/DECISIONS.md")
    $decisionTouched = $decisionStatus.Count -gt 0

    if ($decisionTouched -and $currentBranch -in @("main", "master")) {
        Fail "DECISIONS.md는 main/master에서 직접 수정할 수 없습니다. 작업 브랜치에서 수정한 뒤 PR로 병합하세요."
    }

    Write-Output "DAD decision workflow validation passed on branch: $currentBranch"
}
finally {
    Pop-Location
}
