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

    # Round-3 F10: allow the initial add on main (bootstrap `chore: apply`
    # always lands on main when the operator hasn't created a work branch
    # yet). Only block when the file is being MODIFIED on main/master, i.e.
    # status code starts with 'M'. Added ('A'), untracked ('??'), and renamed
    # ('R') are all permitted — you cannot bootstrap on a work branch before
    # the repo has any commits.
    $isModification = $false
    foreach ($line in $decisionStatus) {
        # `git status --porcelain` format: XY <path> — X=index, Y=worktree.
        if ($line -match '^[ MT]M|^M[ MT]') { $isModification = $true; break }
    }

    if ($isModification -and $currentBranch -in @("main", "master")) {
        Fail "DECISIONS.md는 main/master에서 직접 수정할 수 없습니다. 작업 브랜치에서 수정한 뒤 PR로 병합하세요. (DECISIONS.md cannot be modified on main/master; use a work branch and merge via PR.)"
    }

    Write-Output "DAD decision workflow validation passed on branch: $currentBranch"
}
finally {
    Pop-Location
}
