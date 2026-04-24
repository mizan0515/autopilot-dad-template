Set-StrictMode -Version Latest

$script:CoreCodexSkillSuffixes = @(
    'dialogue-start',
    'repeat-workflow',
    'repeat-workflow-auto'
)

$script:ReservedCodexNamespaces = @(
    '',
    'default',
    'template',
    'example',
    'sample',
    'project',
    'repo',
    'skill',
    'skills',
    'global'
)

function Get-CodexSkillRepoRoot {
    param(
        [string]$RepoRoot
    )

    if ($RepoRoot) {
        return (Resolve-Path -LiteralPath $RepoRoot).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Get-CodexSkillSourceRoot {
    param(
        [string]$RepoRoot
    )

    return Join-Path (Get-CodexSkillRepoRoot -RepoRoot $RepoRoot) '.agents\skills'
}

function Get-CodexSkillHome {
    param(
        [string]$SkillHome
    )

    if ($SkillHome) {
        return [System.IO.Path]::GetFullPath($SkillHome)
    }

    $codexRoot = if ($env:CODEX_HOME) {
        [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    else {
        [System.IO.Path]::Combine($env:USERPROFILE, '.codex')
    }

    return [System.IO.Path]::Combine($codexRoot, 'skills')
}

function Read-Utf8Text {
    param(
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    return [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)
}

function Test-FileHasUtf8Bom {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

function Write-Utf8BomText {
    param(
        [string]$Path,
        [string]$Text
    )

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8Bom)
}

function Write-Utf8NoBomText {
    param(
        [string]$Path,
        [string]$Text
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-FrontmatterName {
    param(
        [string]$SkillMarkdownPath
    )

    if (-not (Test-Path -LiteralPath $SkillMarkdownPath)) {
        return $null
    }

    $text = Read-Utf8Text -Path $SkillMarkdownPath
    $match = [regex]::Match(
        $text,
        '(?ms)^---\s*\r?\n.*?^name:\s*(?<name>.+?)\s*$'
    )

    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['name'].Value.Trim().Trim('"', "'")
}

function Get-YamlScalar {
    param(
        [string]$YamlPath,
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $YamlPath)) {
        return $null
    }

    $text = Read-Utf8Text -Path $YamlPath
    $match = [regex]::Match(
        $text,
        "(?m)^\s*$([regex]::Escape($Key)):\s*""(?<value>(?:[^""\\]|\\.)*)""\s*$"
    )

    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['value'].Value
}

function Test-OpenAiYamlHasMultipleDocuments {
    param(
        [string]$YamlPath
    )

    if (-not (Test-Path -LiteralPath $YamlPath)) {
        return $false
    }

    $text = Read-Utf8Text -Path $YamlPath
    $documentMarkers = [regex]::Matches($text, '(?m)^---\s*$').Count
    return $documentMarkers -gt 1 -or $text -match '(?m)^\.\.\.\s*$'
}

function Get-CodexSkillName {
    param(
        [string]$Namespace,
        [string]$Suffix
    )

    return "$Namespace-$Suffix"
}

function Test-ReservedCodexSkillNamespace {
    param(
        [string]$Namespace
    )

    if ([string]::IsNullOrWhiteSpace($Namespace)) {
        return $true
    }

    if ($Namespace -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        return $true
    }

    return $script:ReservedCodexNamespaces -contains $Namespace
}

function Assert-ValidCodexSkillNamespace {
    param(
        [string]$Namespace
    )

    if (Test-ReservedCodexSkillNamespace -Namespace $Namespace) {
        throw "Namespace '$Namespace' is reserved or invalid. Choose a lowercase repo-specific prefix such as 'myproject'."
    }
}

function Get-CodexSkillInterestNames {
    param(
        [string]$Namespace
    )

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($suffix in $script:CoreCodexSkillSuffixes) {
        $names.Add($suffix) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($Namespace)) {
            $names.Add((Get-CodexSkillName -Namespace $Namespace -Suffix $suffix)) | Out-Null
        }
    }

    return $names | Sort-Object -Unique
}

function Get-NormalizedPathPrefix {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    $normalizedPath = Get-NormalizedPathPrefix -Path $Path
    $normalizedRoot = Get-NormalizedPathPrefix -Path $Root

    if (-not $normalizedPath -or -not $normalizedRoot) {
        return $false
    }

    return $normalizedPath.StartsWith("$normalizedRoot\", [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CodexSkillMetadata {
    param(
        [string]$RepoRoot
    )

    $sourceRoot = Get-CodexSkillSourceRoot -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $sourceRoot)) {
        return @()
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($directory in Get-ChildItem -LiteralPath $sourceRoot -Directory | Sort-Object Name) {
        foreach ($suffix in $script:CoreCodexSkillSuffixes) {
            $namespace = $null
            if ($directory.Name -eq $suffix) {
                $namespace = ''
            }
            elseif ($directory.Name.EndsWith("-$suffix", [System.StringComparison]::OrdinalIgnoreCase)) {
                $namespace = $directory.Name.Substring(0, $directory.Name.Length - $suffix.Length - 1)
            }
            else {
                continue
            }

            $skillMarkdownPath = Join-Path $directory.FullName 'SKILL.md'
            $yamlPath = Join-Path $directory.FullName 'agents\openai.yaml'
            $items.Add([PSCustomObject]@{
                    Suffix = $suffix
                    DirectoryName = $directory.Name
                    DirectoryPath = $directory.FullName
                    Namespace = $namespace
                    SkillMarkdownPath = $skillMarkdownPath
                    SkillMarkdownHasBom = Test-FileHasUtf8Bom -Path $skillMarkdownPath
                    FrontmatterName = Get-FrontmatterName -SkillMarkdownPath $skillMarkdownPath
                    YamlPath = $yamlPath
                    YamlHasBom = Test-FileHasUtf8Bom -Path $yamlPath
                    OpenAiYamlHasMultipleDocuments = Test-OpenAiYamlHasMultipleDocuments -YamlPath $yamlPath
                    DefaultPrompt = Get-YamlScalar -YamlPath $yamlPath -Key 'default_prompt'
                }) | Out-Null
            break
        }
    }

    return [object[]]$items
}

function Get-CodexSkillAudit {
    param(
        [string]$RepoRoot,
        [string]$ExpectedNamespace
    )

    $items = @(Get-CodexSkillMetadata -RepoRoot $RepoRoot)
    $issues = New-Object System.Collections.Generic.List[string]
    $selected = New-Object System.Collections.Generic.List[object]

    foreach ($suffix in $script:CoreCodexSkillSuffixes) {
        $matches = @($items | Where-Object { $_.Suffix -eq $suffix })
        if ($matches.Count -eq 0) {
            $issues.Add("missing-core-skill:$suffix") | Out-Null
            continue
        }

        if ($matches.Count -gt 1) {
            $issues.Add("duplicate-core-skill:$suffix=>$($matches.DirectoryName -join ',')") | Out-Null
            continue
        }

        $selected.Add($matches[0]) | Out-Null
    }

    foreach ($item in $selected) {
        if ([string]::IsNullOrWhiteSpace($item.Namespace)) {
            $issues.Add("non-namespaced-core-skill:$($item.DirectoryName)") | Out-Null
        }

        if ($item.SkillMarkdownHasBom) {
            $issues.Add("skill-frontmatter-bom:$($item.DirectoryName)") | Out-Null
        }

        if ($item.DirectoryName -ne $item.FrontmatterName) {
            $issues.Add("folder-frontmatter-mismatch:$($item.DirectoryName)!=$($item.FrontmatterName)") | Out-Null
        }

        if ($item.OpenAiYamlHasMultipleDocuments) {
            $issues.Add("invalid-openai-yaml-documents:$($item.DirectoryName)") | Out-Null
        }

        if ($item.YamlHasBom) {
            $issues.Add("openai-yaml-bom:$($item.DirectoryName)") | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace($item.DefaultPrompt)) {
            $issues.Add("missing-default-prompt:$($item.DirectoryName)") | Out-Null
        }
        elseif ($item.DefaultPrompt -notmatch [regex]::Escape("`$$($item.DirectoryName)")) {
            $issues.Add("default-prompt-mismatch:$($item.DirectoryName)") | Out-Null
        }
    }

    $namespaces = @(
        $selected |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Namespace) } |
            Select-Object -ExpandProperty Namespace -Unique
    )

    if ($namespaces.Count -gt 1) {
        $issues.Add("mixed-namespaces:$($namespaces -join ',')") | Out-Null
    }

    if ($ExpectedNamespace) {
        foreach ($item in $selected) {
            if ($item.Namespace -ne $ExpectedNamespace) {
                $issues.Add("unexpected-namespace:$($item.DirectoryName)=>$($item.Namespace)") | Out-Null
            }
        }
    }

    $namespace = if ($namespaces.Count -eq 1) { $namespaces[0] } else { $null }

    return [PSCustomObject]@{
        SourceRoot = Get-CodexSkillSourceRoot -RepoRoot $RepoRoot
        Items = [object[]]$selected
        Issues = [string[]]$issues
        Namespace = $namespace
    }
}

function Get-CodexGlobalSkillEntries {
    param(
        [string]$SkillHome
    )

    $resolvedSkillHome = Get-CodexSkillHome -SkillHome $SkillHome
    if (-not (Test-Path -LiteralPath $resolvedSkillHome)) {
        return @()
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($entry in Get-ChildItem -LiteralPath $resolvedSkillHome -Directory -Force | Sort-Object Name) {
        try {
            $item = Get-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
            $target = $null
            if ($item.PSObject.Properties.Name -contains 'Target' -and $item.Target) {
                $target = ($item.Target -join '; ')
            }

            $entries.Add([PSCustomObject]@{
                    Name = $item.Name
                    FullName = $item.FullName
                    LinkType = $item.LinkType
                    Target = $target
                    Broken = $false
                    Error = $null
                }) | Out-Null
            continue
        }
        catch {
            $target = $null
            if ($entry.PSObject.Properties.Name -contains 'Target' -and $entry.Target) {
                $target = ($entry.Target -join '; ')
            }

            $entries.Add([PSCustomObject]@{
                    Name = $entry.Name
                    FullName = $entry.FullName
                    LinkType = $entry.LinkType
                    Target = $target
                    Broken = $true
                    Error = $_.Exception.Message
                }) | Out-Null
        }
    }

    return [object[]]$entries
}

function Get-CodexRegistrationAudit {
    param(
        [string]$RepoRoot,
        [string]$Namespace,
        [string]$SkillHome
    )

    $repoResolvedRoot = Get-CodexSkillRepoRoot -RepoRoot $RepoRoot
    $sourceRoot = Get-CodexSkillSourceRoot -RepoRoot $repoResolvedRoot
    $namesOfInterest = @(Get-CodexSkillInterestNames -Namespace $Namespace)
    $repoRegistrations = New-Object System.Collections.Generic.List[object]
    $externalCollisions = New-Object System.Collections.Generic.List[object]
    $brokenEntries = New-Object System.Collections.Generic.List[object]

    foreach ($entry in Get-CodexGlobalSkillEntries -SkillHome $SkillHome) {
        $interestingName = $namesOfInterest -contains $entry.Name
        $namespacePrefix = if ([string]::IsNullOrWhiteSpace($Namespace)) { $null } else { "$Namespace-" }
        $repoNamedEntry = -not [string]::IsNullOrWhiteSpace($namespacePrefix) -and
            $entry.Name.StartsWith($namespacePrefix, [System.StringComparison]::OrdinalIgnoreCase)

        if ($entry.Broken) {
            $brokenEntries.Add($entry) | Out-Null

            if ($repoNamedEntry) {
                $repoRegistrations.Add($entry) | Out-Null
                continue
            }

            if ($interestingName) {
                $externalCollisions.Add($entry) | Out-Null
            }

            continue
        }

        $repoOwned = Test-PathUnderRoot -Path $entry.Target -Root $sourceRoot

        if ($repoOwned) {
            $repoRegistrations.Add($entry) | Out-Null
            continue
        }

        if ($interestingName) {
            $externalCollisions.Add($entry) | Out-Null
        }
    }

    return [PSCustomObject]@{
        RepoRegistrations = [object[]]$repoRegistrations
        ExternalCollisions = [object[]]$externalCollisions
        BrokenEntries = [object[]]$brokenEntries
        SkillHome = Get-CodexSkillHome -SkillHome $SkillHome
        NamesOfInterest = $namesOfInterest
    }
}
