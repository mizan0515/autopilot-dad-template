# base/tools/Write-Utf8NoBom.ps1
#
# Write text to a path as UTF-8 WITHOUT a BOM. Use for runtime JSON / JSONL,
# qa-evidence files, METRICS lines, RUNNER-LIVE.json — any machine-read
# artifact containing non-ASCII (Korean / Japanese / emoji) content.
#
# Why this exists:
#   Windows PowerShell's default `Out-File`, `>`, `Set-Content` produce UTF-16-LE
#   with a BOM unless you explicitly say otherwise. That has already corrupted
#   multiple projects' qa-evidence JSON, turning Korean copy into mojibake when
#   downstream tools read the file. Agent-facing .md files get a UTF-8 BOM
#   intentionally (validator contract), but runtime JSON must be BOM-free or
#   strict JSON parsers (`json.loads`, `JSON.parse`) reject it.
#
# Usage:
#   & "$PSScriptRoot/../tools/Write-Utf8NoBom.ps1" -Path $p -Text $json
#   & "$PSScriptRoot/../tools/Write-Utf8NoBom.ps1" -Path $p -Text $line -Append

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
  [switch]$Append,
  [switch]$EnsureTrailingNewline
)

$ErrorActionPreference = 'Stop'

$dir = Split-Path $Path -Parent
if ($dir -and -not (Test-Path $dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$enc = New-Object System.Text.UTF8Encoding($false)  # $false = no BOM
$toWrite = if ($EnsureTrailingNewline -and -not $Text.EndsWith("`n")) { $Text + "`n" } else { $Text }

if ($Append) {
  [System.IO.File]::AppendAllText($Path, $toWrite, $enc)
} else {
  [System.IO.File]::WriteAllText($Path, $toWrite, $enc)
}
