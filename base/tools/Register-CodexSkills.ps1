param(
    [string]$RepoRoot = ".",
    [string]$Namespace,
    [string]$SkillHome,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexSkillSupport.ps1')

$resolvedRepoRoot = Get-CodexSkillRepoRoot -RepoRoot $RepoRoot
$skillAudit = Get-CodexSkillAudit -RepoRoot $resolvedRepoRoot

if (-not $Namespace) {
    $Namespace = $skillAudit.Namespace
}

Assert-ValidCodexSkillNamespace -Namespace $Namespace

if ($skillAudit.Issues.Count -gt 0) {
    Write-Output 'Registration blocked because local skill metadata is invalid:'
    foreach ($issue in $skillAudit.Issues) {
        Write-Output "- $issue"
    }
    exit 1
}

if ($skillAudit.Namespace -ne $Namespace) {
    Write-Output "Registration blocked. Local source-of-truth namespace is '$($skillAudit.Namespace)', requested namespace is '$Namespace'."
    exit 1
}

$skillHomePath = Get-CodexSkillHome -SkillHome $SkillHome
if (-not $ValidateOnly -and -not (Test-Path -LiteralPath $skillHomePath)) {
    New-Item -ItemType Directory -Path $skillHomePath -Force | Out-Null
}

if (-not $ValidateOnly) {
    & (Join-Path $PSScriptRoot 'Unregister-CodexSkills.ps1') -RepoRoot $resolvedRepoRoot -Namespace $Namespace -SkillHome $skillHomePath | Out-Null
}

$registrationAudit = Get-CodexRegistrationAudit -RepoRoot $resolvedRepoRoot -Namespace $Namespace -SkillHome $skillHomePath
if ($registrationAudit.ExternalCollisions.Count -gt 0) {
    Write-Output 'Registration blocked by external collisions:'
    foreach ($entry in $registrationAudit.ExternalCollisions) {
        Write-Output "- $($entry.Name) -> $($entry.Target)"
    }
    exit 1
}

foreach ($item in $skillAudit.Items | Sort-Object Suffix) {
    $target = $item.DirectoryPath
    $destination = Join-Path $skillHomePath $item.DirectoryName
    if (Test-Path -LiteralPath $destination) {
        Write-Output "Registration blocked because destination already exists: $destination"
        exit 1
    }

    if (-not $ValidateOnly) {
        New-Item -ItemType Junction -Path $destination -Target $target | Out-Null
        Write-Output "Registered: $($item.DirectoryName) -> $target"
    }
    else {
        Write-Output "Validated registration: $($item.DirectoryName) -> $target"
    }
}

if (-not $ValidateOnly) {
    $postAudit = Get-CodexRegistrationAudit -RepoRoot $resolvedRepoRoot -Namespace $Namespace -SkillHome $skillHomePath
    if ($postAudit.ExternalCollisions.Count -gt 0) {
        Write-Output 'Registration succeeded, but external collisions remain:'
        foreach ($entry in $postAudit.ExternalCollisions) {
            Write-Output "- $($entry.Name) -> $($entry.Target)"
        }
    }
}

if ($ValidateOnly) {
    Write-Output "Codex skill registration validation passed. Namespace: $Namespace"
}
