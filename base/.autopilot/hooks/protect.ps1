# .autopilot/hooks/protect.ps1 — Windows PowerShell port of protect.sh (pre-commit).
# Trailer-dependent checks live in commit-msg-protect.sh — see that file.
# Kept in sync with protect.sh; see that file for the authoritative docstring.

$ErrorActionPreference = 'Stop'

$prompt   = '.autopilot/PROMPT.md'
$mvpgates = '.autopilot/MVP-GATES.md'
$state    = '.autopilot/STATE.md'

# ---- Check 5: hard-cap on bulk deletes ----
# (>5 / sensitive-path trailer gates live in commit-msg-protect.sh because
# `git commit -m` doesn't populate COMMIT_EDITMSG before pre-commit.)
$deleted = @(git diff --cached --name-only --diff-filter=D) | Where-Object { $_ }
$delCount = $deleted.Count

if ($delCount -gt 20) {
    Write-Host "protect.ps1: commit deletes $delCount files; hard cap is 20 per commit."
    exit 1
}

# ---- Checks 3 + 4: sentinel file health ----
if (-not (Test-Path $mvpgates)) {
    Write-Host "protect.ps1: $mvpgates missing (MVP halt trigger source)."
    exit 1
}
if (-not (Select-String -Path $mvpgates -Pattern '^Gate count:\s*\d+' -Quiet)) {
    Write-Host "protect.ps1: $mvpgates missing parseable 'Gate count: <N>' line."
    exit 1
}

if (-not (Test-Path $state)) {
    Write-Host "protect.ps1: $state missing; cannot verify protected_paths."
    exit 1
}
$stateText = Get-Content $state -Raw
$required = @(
    '.autopilot/PROMPT.md',
    '.autopilot/hooks/',
    '.autopilot/project.ps1',
    '.autopilot/project.sh',
    'Packages/manifest.json',
    'ProjectSettings/',
    'PROJECT-RULES.md',
    'CLAUDE.md',
    'AGENTS.md',
    'Document/dialogue/'
)
foreach ($p in $required) {
    $rx = "(?m)^\s*-\s*$([regex]::Escape($p))\s*$"
    if ($stateText -notmatch $rx) {
        Write-Host "protect.ps1: STATE.md protected_paths missing required entry: '$p'"
        exit 1
    }
}

# ---- Checks 1 + 2: PROMPT.md IMMUTABLE integrity ----
$staged = git diff --cached --name-only
if ($staged -notcontains $prompt) { exit 0 }

try { git rev-parse --verify HEAD | Out-Null } catch { exit 0 }

$blocks = 'product-directive','core-contract','boot','budget','blast-radius','halt','cleanup-safety','mvp-gate','exit-contract'

$baseText = git show "HEAD:$prompt" | Out-String
$headText = git show ":$prompt" | Out-String

$markerRx = [regex]'\[IMMUTABLE:BEGIN ([a-z-]+)\]'
$baseMarkers = @($markerRx.Matches($baseText) | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
$headMarkers = @($markerRx.Matches($headText) | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique

$removed = $baseMarkers | Where-Object { $_ -notin $headMarkers }
# New-marker authorization (IMMUTABLE-ADD trailer) is enforced in commit-msg-protect.sh.

if ($removed) {
    Write-Host "protect.ps1: IMMUTABLE block(s) removed from $prompt :"
    $removed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

foreach ($name in $blocks) {
    $beginPattern = [regex]::Escape("[IMMUTABLE:BEGIN $name]")
    $endPattern   = [regex]::Escape("[IMMUTABLE:END $name]")

    if ($headText -notmatch $beginPattern -or $headText -notmatch $endPattern) {
        Write-Host "protect.ps1: IMMUTABLE markers for '$name' are missing from $prompt"
        exit 1
    }

    $rx = "(?s)$beginPattern.*?$endPattern"
    $baseBlock = [regex]::Match($baseText, $rx).Value
    $headBlock = [regex]::Match($headText, $rx).Value

    if ([string]::IsNullOrEmpty($baseBlock)) { continue }

    if ($baseBlock -ne $headBlock) {
        Write-Host "protect.ps1: IMMUTABLE block '$name' was modified in $prompt"
        exit 1
    }
}

exit 0
