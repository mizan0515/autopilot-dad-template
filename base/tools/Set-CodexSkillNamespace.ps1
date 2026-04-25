param(
    [Parameter(Mandatory = $true)]
    [string]$Namespace,
    [string]$RepoRoot = ".",
    [string]$ProjectLabel = "CardGame"
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexSkillSupport.ps1')

$resolvedRepoRoot = Get-CodexSkillRepoRoot -RepoRoot $RepoRoot
Assert-ValidCodexSkillNamespace -Namespace $Namespace

$inventory = @(Get-CodexSkillMetadata -RepoRoot $resolvedRepoRoot)
if ($inventory.Count -eq 0) {
    throw "No core Codex skills found under $(Get-CodexSkillSourceRoot -RepoRoot $resolvedRepoRoot)."
}

$missing = @($script:CoreCodexSkillSuffixes | Where-Object { @($inventory | Where-Object Suffix -eq $_).Count -eq 0 })
if ($missing.Count -gt 0) {
    throw "Cannot set namespace while core skills are missing: $($missing -join ', ')"
}

foreach ($suffix in $script:CoreCodexSkillSuffixes) {
    $matches = @($inventory | Where-Object Suffix -eq $suffix)
    if ($matches.Count -ne 1) {
        throw "Cannot set namespace while '$suffix' has $($matches.Count) matching folders."
    }
}

$spec = @{
    'dialogue-start' = @{
        Description = "$ProjectLabel repository-only explicit skill for starting a DAD v2 dialogue session with Claude Code. Invoke it directly as __SKILL_NAME__. Use it when medium or large work benefits from external review. Do not use it for small work that a single agent can finish."
        DisplayName = "$ProjectLabel DAD v2 Dialogue Start"
        ShortDescription = "Start a $ProjectLabel Claude Code session with Codex as turn 1"
        DefaultPrompt = "Use __SKILL_NAME__ to start a $ProjectLabel DAD v2 session and produce Turn 1 plus the Claude Code handoff prompt."
    }
    'repeat-workflow' = @{
        Description = "$ProjectLabel repository-only explicit skill for continuing an active DAD v2 session. Invoke it directly as __SKILL_NAME__. It executes the next turn of the current dialogue session and should not be used when no session exists."
        DisplayName = "$ProjectLabel DAD v2 Repeat Workflow"
        ShortDescription = "Run the next turn of the active $ProjectLabel DAD v2 session"
        DefaultPrompt = "Use __SKILL_NAME__ to execute the next turn of the active $ProjectLabel DAD v2 session and emit the next handoff prompt."
    }
    'repeat-workflow-auto' = @{
        Description = "$ProjectLabel repository-only explicit skill for continuing an active DAD v2 session in auto mode. Invoke it directly as __SKILL_NAME__. It automates decision making and only escalates when safety rails require it. User relay is still required."
        DisplayName = "$ProjectLabel DAD v2 Repeat Workflow (Auto)"
        ShortDescription = "Auto mode for $ProjectLabel DAD v2 with relay still required"
        DefaultPrompt = "Use __SKILL_NAME__ to continue the active $ProjectLabel DAD v2 session in auto mode and escalate only when the safety rails require it."
    }
}

$renamePlan = @{}
$nameMap = @{}
foreach ($item in $inventory) {
    $newName = Get-CodexSkillName -Namespace $Namespace -Suffix $item.Suffix
    $renamePlan[$item.DirectoryPath] = Join-Path (Split-Path -Path $item.DirectoryPath -Parent) $newName
    $nameMap[$item.DirectoryName] = $newName
}

foreach ($item in $inventory) {
    $newName = $nameMap[$item.DirectoryName]
    $skillText = Read-Utf8Text -Path $item.SkillMarkdownPath
    $skillText = [regex]::Replace($skillText, '(?m)^name:\s*.+$', "name: $newName", 1)
    # Round-3 F27: previous regex `^description:\s*".+"$` required the closing
    # `"` to sit immediately at end-of-line, but the shipped Korean SKILL.md
    # has a trailing space (or other whitespace) after the closing quote.
    # Result: regex never matched, description was left as the source-project
    # `CardGame 저장소 전용...` text even after a successful folder rename
    # and `$skill-name` substitution. Codex's skill matching reads the
    # description prose, so a "CardGame repository-only" description on a
    # `dogfood-sample-dialogue-start` skill confuses routing. Use the same
    # `.+$` shape the openai.yaml replacements use (which works) — match
    # any content on the description line, regardless of trailing whitespace
    # or escaped-quote placement.
    $skillText = [regex]::Replace($skillText, '(?m)^description:\s*.+$', ('description: "' + $spec[$item.Suffix].Description.Replace('__SKILL_NAME__', "`$$newName").Replace('"', '\"') + '"'), 1)
    foreach ($oldName in $nameMap.Keys) {
        $skillText = $skillText.Replace("`$$oldName", "`$$($nameMap[$oldName])")
    }
    Write-Utf8NoBomText -Path $item.SkillMarkdownPath -Text $skillText

    $yamlText = Read-Utf8Text -Path $item.YamlPath
    $yamlText = [regex]::Replace($yamlText, '(?m)^---\s*\r?\n?', '')
    $yamlText = [regex]::Replace($yamlText, '(?m)^\.\.\.\s*\r?\n?', '')
    $yamlText = [regex]::Replace($yamlText, '(?m)^(\s*display_name:\s*).+$', ('$1"' + $spec[$item.Suffix].DisplayName + '"'), 1)
    $yamlText = [regex]::Replace($yamlText, '(?m)^(\s*short_description:\s*).+$', ('$1"' + $spec[$item.Suffix].ShortDescription + '"'), 1)
    $yamlText = [regex]::Replace($yamlText, '(?m)^(\s*default_prompt:\s*).+$', ('$1"' + $spec[$item.Suffix].DefaultPrompt.Replace('__SKILL_NAME__', "`$$newName") + '"'), 1)
    Write-Utf8NoBomText -Path $item.YamlPath -Text $yamlText
}

foreach ($item in $inventory | Sort-Object { $_.DirectoryPath.Length } -Descending) {
    $destination = $renamePlan[$item.DirectoryPath]
    if ($item.DirectoryPath -eq $destination) {
        continue
    }

    if (Test-Path -LiteralPath $destination) {
        throw "Target skill folder already exists: $destination"
    }

    Move-Item -LiteralPath $item.DirectoryPath -Destination $destination
    Write-Output "Renamed skill folder: $($item.DirectoryName) -> $(Split-Path -Path $destination -Leaf)"
}
