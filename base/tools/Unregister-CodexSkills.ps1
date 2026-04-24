param(
    [string]$RepoRoot = ".",
    [string]$Namespace,
    [string]$SkillHome
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexSkillSupport.ps1')

$resolvedRepoRoot = Get-CodexSkillRepoRoot -RepoRoot $RepoRoot
$audit = Get-CodexSkillAudit -RepoRoot $resolvedRepoRoot

if (-not $Namespace) {
    $Namespace = $audit.Namespace
}

if ($Namespace) {
    Assert-ValidCodexSkillNamespace -Namespace $Namespace
}

$registrationAudit = Get-CodexRegistrationAudit -RepoRoot $resolvedRepoRoot -Namespace $Namespace -SkillHome $SkillHome

foreach ($entry in $registrationAudit.RepoRegistrations) {
    Remove-Item -LiteralPath $entry.FullName -Force -Recurse
    Write-Output "Removed repo registration: $($entry.Name) -> $($entry.Target)"
}

if ($registrationAudit.RepoRegistrations.Count -eq 0) {
    Write-Output '변경 불필요, PASS'
}

if ($registrationAudit.ExternalCollisions.Count -gt 0) {
    Write-Output 'External collisions remain:'
    foreach ($entry in $registrationAudit.ExternalCollisions) {
        Write-Output "- $($entry.Name) -> $($entry.Target)"
    }
}
