# Validate-ImmutableBlocks.ps1
#
# Pre-commit guard for the autopilot-dad-template IMMUTABLE contract.
# Blocks staged edits that change the body between a matching pair of
#   <!-- IMMUTABLE:<name>:BEGIN -->
#   <!-- IMMUTABLE:<name>:END -->
# markers in `.autopilot/PROMPT.md` and `.autopilot/PROMPT.lite.md`.
#
# Round-3 F12: this validator existed only in the template's README prose
# and in prompt text — nothing actually enforced it. An agent (or operator)
# could rewrite the budget / blast-radius / halt / core-contract blocks
# and the commit would sail through. That is a core safety guarantee of
# the template and must fail pre-commit.
#
# Usage:
#   pwsh tools/Validate-ImmutableBlocks.ps1             # check staged diff vs HEAD
#   pwsh tools/Validate-ImmutableBlocks.ps1 -Ref HEAD~1 # check diff vs another ref
#   pwsh tools/Validate-ImmutableBlocks.ps1 -AllFiles   # re-check whole tree
#
# Exit codes:
#   0 = OK (no IMMUTABLE block modified, or no protected file touched)
#   1 = IMMUTABLE block body changed

param(
    [string]$Root = ".",
    [string]$Ref = "",  # empty = compare staged index vs HEAD
    [switch]$AllFiles,
    [string[]]$ProtectedFiles = @(
        '.autopilot/PROMPT.md',
        '.autopilot/PROMPT.lite.md'
    )
)

$ErrorActionPreference = 'Stop'

# Force UTF-8 for console IO so `git show` output (UTF-8 bytes) is not
# re-decoded through the OEM/ANSI codepage (cp949 on ko-KR Windows).
# Without this, non-ASCII bytes get mangled to '?' (0x3F) and any
# Korean IMMUTABLE block body falsely appears "modified".
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    $OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}

function Fail { param([string]$Msg) Write-Error $Msg; exit 1 }

Push-Location $Root
try {
    $gitRoot = git rev-parse --show-toplevel 2>$null
    if (-not $gitRoot) {
        Write-Host "Not a git repo — skipping IMMUTABLE validation."
        exit 0
    }

    function Normalize-Lf {
        param([string]$Text)
        if ($null -eq $Text) { return "" }
        # Collapse CRLF and lone CR to LF so working-tree (CRLF on Windows)
        # and `git show` output (LF) compare identically.
        return ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    }

    function Extract-Blocks {
        param([string]$Text)
        $map = @{}
        $Text = Normalize-Lf -Text $Text
        $pattern = '<!--\s*IMMUTABLE:(?<name>[A-Za-z0-9_-]+):BEGIN\s*-->(?<body>.*?)<!--\s*IMMUTABLE:\k<name>:END\s*-->'
        foreach ($m in [regex]::Matches($Text, $pattern, 'Singleline')) {
            $name = $m.Groups['name'].Value
            $body = $m.Groups['body'].Value
            $map[$name] = $body
        }
        return $map
    }

    $violations = New-Object System.Collections.Generic.List[string]

    foreach ($rel in $ProtectedFiles) {
        $full = Join-Path $gitRoot $rel
        if (-not (Test-Path $full)) { continue }  # file not present in this project

        # Current (staged for commit if we're in pre-commit; else working-tree).
        $currentText = [IO.File]::ReadAllText($full)
        $currentBlocks = Extract-Blocks -Text $currentText

        # Baseline: previous commit's version (or -Ref). For a fresh repo with
        # no HEAD, skip validation of this file.
        $baselineText = $null
        try {
            if ($Ref) {
                $baselineText = (git show "${Ref}:${rel}" 2>$null) -join "`n"
            } else {
                $baselineText = (git show "HEAD:${rel}" 2>$null) -join "`n"
            }
        } catch { $baselineText = $null }

        if (-not $baselineText) {
            # File is new to the repo (initial apply). Record baseline but do
            # not flag — nothing to compare against.
            continue
        }

        $baselineBlocks = Extract-Blocks -Text $baselineText

        foreach ($name in $baselineBlocks.Keys) {
            if (-not $currentBlocks.ContainsKey($name)) {
                $violations.Add("${rel}: IMMUTABLE block '$name' is missing or its BEGIN/END marker was altered.")
                continue
            }
            if ($currentBlocks[$name] -ne $baselineBlocks[$name]) {
                $violations.Add("${rel}: IMMUTABLE block '$name' body was modified.")
            }
        }

        # Also catch blocks added in current that weren't in baseline with a
        # different structure — not strictly a violation (new block), so we
        # only warn if a known IMMUTABLE name changed in content.
    }

    if ($violations.Count -gt 0) {
        Write-Host ""
        Write-Host "IMMUTABLE block modification detected:" -ForegroundColor Red
        foreach ($v in $violations) { Write-Host "  - $v" -ForegroundColor Red }
        Write-Host ""
        Write-Host "These blocks carry safety contracts (budget, blast-radius, halt," -ForegroundColor Yellow
        Write-Host "core-contract, exit-contract, product-directive) and must not be" -ForegroundColor Yellow
        Write-Host "edited without operator approval recorded in STATE.md." -ForegroundColor Yellow
        Write-Host "If this is a deliberate evolution, follow the procedure in" -ForegroundColor Yellow
        Write-Host ".autopilot/EVOLUTION.md (explicit operator sign-off required)." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "IMMUTABLE block validation passed."
    exit 0
}
finally {
    Pop-Location
}
