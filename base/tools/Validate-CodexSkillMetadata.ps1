param(
    [string]$RepoRoot = ".",
    [string]$ExpectedNamespace
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexSkillSupport.ps1')

$resolvedRepoRoot = Get-CodexSkillRepoRoot -RepoRoot $RepoRoot
$audit = Get-CodexSkillAudit -RepoRoot $resolvedRepoRoot -ExpectedNamespace $ExpectedNamespace

if ($ExpectedNamespace) {
    Assert-ValidCodexSkillNamespace -Namespace $ExpectedNamespace
}

if ($audit.Issues.Count -gt 0) {
    Write-Output 'Codex skill metadata validation failed:'
    foreach ($issue in $audit.Issues) {
        Write-Output "- $issue"
    }
    exit 1
}

Write-Output "Codex skill metadata validation passed. Namespace: $($audit.Namespace)"
foreach ($item in $audit.Items | Sort-Object Suffix) {
    Write-Output "- $($item.DirectoryName)"
}
