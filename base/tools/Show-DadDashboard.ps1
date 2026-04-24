param(
    [string]$Root = ".",
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path $Root).Path
$dashboardWriter = Join-Path $resolvedRoot "tools\Write-DadDashboard.ps1"
$dashboardHtml = Join-Path $resolvedRoot "Document\dialogue\DASHBOARD-LIVE.ko.html"

if (-not (Test-Path $dashboardWriter)) {
    throw "DAD dashboard writer not found: $dashboardWriter"
}

$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
& $pwshExe -NoProfile -ExecutionPolicy Bypass -File $dashboardWriter -Root $resolvedRoot

if (-not (Test-Path $dashboardHtml)) {
    throw "DAD dashboard HTML not found after generation: $dashboardHtml"
}

Write-Output "DAD dashboard ready: $dashboardHtml"

if (-not $NoOpen) {
    Start-Process -FilePath $dashboardHtml | Out-Null
    Write-Output "Opened DAD dashboard."
}
