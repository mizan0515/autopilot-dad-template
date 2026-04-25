param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$TaskSummary,
    [ValidateSet('small', 'medium', 'large')]
    [string]$Scope = 'medium',
    [ValidateSet('autonomous', 'hybrid', 'supervised')]
    [string]$Mode = 'hybrid',
    [string]$Root = ".",
    [int]$MaxTurns = 0,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($MaxTurns -le 0) {
    switch ($Scope) {
        'small' { $MaxTurns = 2 }
        'medium' { $MaxTurns = 5 }
        'large' { $MaxTurns = 10 }
    }
}

$resolvedRoot = (Resolve-Path $Root).Path
$dialogueRoot = Join-Path $resolvedRoot "Document\dialogue"
$sessionsRoot = Join-Path $dialogueRoot "sessions"
$targetDir = Join-Path $sessionsRoot $SessionId
$statePath = Join-Path $dialogueRoot "state.json"
$sessionStatePath = Join-Path $targetDir "state.json"

if ((Test-Path $targetDir) -and -not $Force) {
    throw "Session directory already exists: $targetDir"
}

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

$state = [ordered]@{
    protocol_version = "dad-v2"
    session_id = $SessionId
    session_status = "active"
    superseded_by = $null
    closed_reason = $null
    relay_mode = "user-bridged"
    mode = $Mode
    scope = $Scope
    current_turn = 0
    max_turns = $MaxTurns
    last_agent = $null
    task_summary = $TaskSummary
    contract_status = "proposed"
    contract_checkpoints = [ordered]@{}
    packets = @()
    decisions = @()
    meta_improvements = @()
}

$json = $state | ConvertTo-Json -Depth 20
# Round-3 F25: state.json is RUNTIME JSON read by jq / Validate-DadPacket /
# operator dashboard — must be UTF-8 NO BOM. Previously this passed `$true`
# to UTF8Encoding which prepends the EF BB BF BOM, breaking jq parsers and
# any regex that expects `{` at byte 0. Convention across the template:
# agent-facing markdown (PROMPT.md, DECISIONS.md) keeps BOM; runtime JSON /
# JSONL / YAML strips BOM. apply.ps1 already uses ($false) for config.json.
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($statePath, $json, $enc)
[System.IO.File]::WriteAllText($sessionStatePath, $json, $enc)

Write-Output "Created DAD session '$SessionId'."
Write-Output "Session dir: $targetDir"
Write-Output "State: $statePath"
