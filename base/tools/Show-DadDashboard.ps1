# Show-DadDashboard.ps1
#
# Round-5 F49 — broken-reference repair.
#
# Original Show-DadDashboard.ps1 delegated to a `Write-DadDashboard.ps1`
# that was never shipped in the template (audit caught this during
# iter-MM post-F48 surface sweep). Calling it threw unconditionally
# with "DAD dashboard writer not found".
#
# Repaired by routing through `.autopilot/project.ps1 status`, which is
# the canonical operator-dashboard generator (writes OPERATOR-LIVE.json
# and OPERATOR-LIVE.html). That dashboard already includes a `🤝 DAD
# sessions` panel (rendered by Get-DadSessions in project.ps1) and the
# round-5 F47 `🛡 Validator signals` panel — so it covers everything
# the legacy DAD-only dashboard would have shown plus the new
# round-4/5 gate signals.
#
# Kept the same parameter shape (-Root, -NoOpen) for backward compat
# with any operator scripts that referenced this entrypoint.

param(
    [string]$Root = ".",
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path $Root).Path
$projectScript = Join-Path $resolvedRoot ".autopilot/project.ps1"
$dashboardHtml = Join-Path $resolvedRoot ".autopilot/OPERATOR-LIVE.html"

if (-not (Test-Path -LiteralPath $projectScript)) {
    throw "operator dashboard generator not found: $projectScript (run apply.ps1 first)"
}

$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
Push-Location $resolvedRoot
try {
    & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $projectScript status | Out-Null
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $dashboardHtml)) {
    throw "operator dashboard HTML not found after generation: $dashboardHtml"
}

Write-Output "operator dashboard ready: $dashboardHtml"

if (-not $NoOpen) {
    Start-Process -FilePath $dashboardHtml | Out-Null
    Write-Output "opened operator dashboard."
}
