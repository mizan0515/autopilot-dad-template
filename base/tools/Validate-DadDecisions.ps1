param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Fail {
    param([string]$Message)

    Write-Error $Message
    exit 1
}

$resolvedRoot = if ($Root) {
    (Resolve-Path -LiteralPath $Root).Path
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$decisionsPath = Join-Path $resolvedRoot "Document\dialogue\DECISIONS.md"
if (-not (Test-Path $decisionsPath)) {
    Fail "DAD decisions file not found: $decisionsPath"
}

$lines = @(Get-Content -Path $decisionsPath -Encoding UTF8)
$decisionLines = @()
foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed.Contains("DECISION:")) {
        $normalized = $trimmed.Replace([string][char]96, "")
        if ($normalized.StartsWith("- ")) {
            $normalized = $normalized.Substring(2).Trim()
        }

        if ($normalized.StartsWith("DECISION: ") -and -not $normalized.Contains("<") -and -not $normalized.Contains("|")) {
            $decisionLines += $normalized
        }
        continue
    }
}

$requiredKeys = @("focus", "human-review", "session-resume", "next-session", "approval")
$seen = @{}

foreach ($entry in $decisionLines) {
    if ($entry -notmatch '^DECISION:\s+([a-z-]+)\s+(.+)$') {
        Fail "Invalid DECISION line format in $decisionsPath : $entry"
    }

    $key = $Matches[1]
    $value = $Matches[2].Trim()

    if ($seen.ContainsKey($key)) {
        Fail "Duplicate DECISION key '$key' in $decisionsPath"
    }

    switch ($key) {
        "focus" {
            if ($value -notmatch '^(none|[A-Za-z0-9._-]+)$') {
                Fail "Invalid focus decision value '$value'. Use 'none' or a single session/topic token."
            }
        }
        "human-review" {
            if ($value -notin @("always", "default", "minimal")) {
                Fail "Invalid human-review decision value '$value'. Allowed: always, default, minimal."
            }
        }
        "session-resume" {
            if ($value -notin @("auto", "hold")) {
                Fail "Invalid session-resume decision value '$value'. Allowed: auto, hold."
            }
        }
        "next-session" {
            if ([string]::IsNullOrWhiteSpace($value)) {
                Fail "next-session decision must not be empty."
            }
        }
        "approval" {
            if ($value -eq "pending") {
                # allowed
            } elseif ($value -notmatch '^(approve|hold)\s+\S+') {
                Fail "Invalid approval decision value '$value'. Use 'pending', 'approve <note>', or 'hold <note>'."
            }
        }
        default {
            Fail "Unknown DECISION key '$key' in $decisionsPath"
        }
    }

    $seen[$key] = $true
}

foreach ($requiredKey in $requiredKeys) {
    if (-not $seen.ContainsKey($requiredKey)) {
        Fail "Missing required DECISION key '$requiredKey' in $decisionsPath"
    }
}

Write-Output "DAD decisions validation passed: $decisionsPath"
