param(
    [string]$Root = ".",
    [string]$Focus,
    [string]$HumanReview,
    [string]$SessionResume,
    [string]$NextSession,
    [string]$Approval,
    [string]$ApprovalNote
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Get-CurrentGitBranch {
    param(
        [string]$RepositoryRoot
    )

    $branch = git -C $RepositoryRoot branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Git branch detection failed. Run this tool inside the repository."
    }

    return ($branch | Select-Object -First 1).Trim()
}

function Prompt-Choice {
    param(
        [string]$Question,
        [string[]]$Allowed,
        [string]$DefaultValue
    )

    while ($true) {
        $suffix = if ($DefaultValue) { " [$DefaultValue]" } else { "" }
        $inputValue = Read-Host "$Question$suffix"
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            $inputValue = $DefaultValue
        }

        if ($Allowed -contains $inputValue) {
            return $inputValue
        }

        Write-Host "허용 값: $($Allowed -join ', ')" -ForegroundColor Yellow
    }
}

function Prompt-Text {
    param(
        [string]$Question,
        [string]$DefaultValue
    )

    $suffix = if ($DefaultValue) { " [$DefaultValue]" } else { "" }
    $inputValue = Read-Host "$Question$suffix"
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $DefaultValue
    }

    return $inputValue.Trim()
}

function Write-Utf8BomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$resolvedRoot = (Resolve-Path $Root).Path
$decisionsPath = Join-Path $resolvedRoot "Document\dialogue\DECISIONS.md"
$currentBranch = Get-CurrentGitBranch -RepositoryRoot $resolvedRoot

if ($currentBranch -in @("main", "master")) {
    throw "관리자 결정은 $currentBranch 브랜치에서 직접 수정할 수 없습니다. 작업 브랜치에서 실행한 뒤 PR로 병합하세요."
}

if (-not (Test-Path $decisionsPath)) {
    throw "DAD decisions file not found: $decisionsPath"
}

$focusValue = if ($PSBoundParameters.ContainsKey("Focus")) { $Focus } else { "none" }
$humanReviewValue = if ($PSBoundParameters.ContainsKey("HumanReview")) { $HumanReview } else { "default" }
$sessionResumeValue = if ($PSBoundParameters.ContainsKey("SessionResume")) { $SessionResume } else { "auto" }
$nextSessionValue = if ($PSBoundParameters.ContainsKey("NextSession")) { $NextSession } else { "pending" }
$approvalValue = if ($PSBoundParameters.ContainsKey("Approval")) { $Approval } else { "pending" }
$approvalNoteValue = if ($PSBoundParameters.ContainsKey("ApprovalNote")) { $ApprovalNote } else { "" }

if (-not $PSBoundParameters.ContainsKey("Focus")) {
    $focusValue = Prompt-Text -Question "집중할 세션 또는 주제를 적으세요. 없으면 none" -DefaultValue $focusValue
}

if (-not $PSBoundParameters.ContainsKey("HumanReview")) {
    $humanReviewValue = Prompt-Choice -Question "사람 확인 강도" -Allowed @("always", "default", "minimal") -DefaultValue $humanReviewValue
}

if (-not $PSBoundParameters.ContainsKey("SessionResume")) {
    $sessionResumeValue = Prompt-Choice -Question "세션 이어가기 방식" -Allowed @("auto", "hold") -DefaultValue $sessionResumeValue
}

if (-not $PSBoundParameters.ContainsKey("NextSession")) {
    $nextSessionValue = Prompt-Text -Question "다음 세션 메모. 없으면 pending" -DefaultValue $nextSessionValue
}

if (-not $PSBoundParameters.ContainsKey("Approval")) {
    $approvalValue = Prompt-Choice -Question "승인 상태" -Allowed @("pending", "approve", "hold") -DefaultValue $approvalValue
}

if ($approvalValue -in @("approve", "hold") -and -not $PSBoundParameters.ContainsKey("ApprovalNote")) {
    $approvalNoteValue = Prompt-Text -Question "승인 메모를 짧게 적으세요" -DefaultValue $approvalNoteValue
}

$approvalLineValue = if ($approvalValue -eq "pending") {
    "pending"
} else {
    "$approvalValue $approvalNoteValue".Trim()
}

$contentLines = @(
    '# DAD Decisions',
    '',
    '이 파일은 DAD 세션 운영에서 사람이 내려야 하는 방향 결정, 승인, 보류를 남기는 공용 입력면이다.',
    '',
    '기본 원칙:',
    '',
    '- `Document/dialogue/state.json`이나 각 세션 `state.json`을 직접 수정하는 것은 기본 운영 경로가 아니다.',
    '- 세션 원장과 사람 결정 입력을 분리해서, 대시보드와 에이전트가 이 파일만 읽어도 현재 운영 지시를 해석할 수 있게 한다.',
    '- 이 파일은 반드시 작업 브랜치에서 수정하고 PR로 병합한다. `main`/`master`에서 직접 수정하지 않는다.',
    '',
    '현재 결정 상태:',
    '',
    ('- `DECISION: focus {0}`' -f $focusValue),
    ('- `DECISION: human-review {0}`' -f $humanReviewValue),
    ('- `DECISION: session-resume {0}`' -f $sessionResumeValue),
    ('- `DECISION: next-session {0}`' -f $nextSessionValue),
    ('- `DECISION: approval {0}`' -f $approvalLineValue),
    '',
    '작성 규칙:',
    '',
    '- `DECISION: focus <session-id|topic|none>`',
    '- `DECISION: human-review always|default|minimal`',
    '- `DECISION: session-resume auto|hold`',
    '- `DECISION: next-session <topic>|pending`',
    '- `DECISION: approval approve <note>|hold <note>|pending`'
)

$content = ($contentLines -join [Environment]::NewLine) + [Environment]::NewLine

Write-Utf8BomFile -Path $decisionsPath -Content $content
Write-Host "관리자 결정 문서를 저장했습니다: $decisionsPath" -ForegroundColor Green
Write-Host "현재 브랜치: $currentBranch" -ForegroundColor Cyan
Write-Host "중요: 이 변경은 작업 브랜치에서 커밋하고 PR로 병합해야 합니다." -ForegroundColor Yellow
