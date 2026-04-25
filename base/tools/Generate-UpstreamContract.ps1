# Generate-UpstreamContract.ps1
#
# Round-7 F65 — maintainer-side helper: regenerate
# `.autopilot/upstream-contract.json`, the SHA256 + line-count
# manifest of the validators that ship in the template. The
# operator's `Validate-UpstreamContract.ps1` reads this manifest to
# detect truncated forks (the R6 case: operator copies the
# 780-line `Validate-DadPacket.ps1` into their project but only
# brings half of it across, silently dropping invariants).
#
# Run this whenever a `tools/Validate-*.ps1` file is added,
# removed, or modified. The generated JSON is committed alongside
# the validator change in the same PR. apply.ps1 ships the file
# to operator projects automatically (it lives under base/ in the
# template tree).
#
# Usage (from repo root):
#   pwsh base/tools/Generate-UpstreamContract.ps1
#
# Output:
#   base/.autopilot/upstream-contract.json (rewritten in place)
#
# Manifest schema:
#   {
#     "schema_version": 1,
#     "generated_at":   "<ISO8601 UTC>",
#     "template_repo":  "mizan0515/autopilot-dad-template",
#     "validators": {
#       "Validate-Foo.ps1": {
#         "sha256":      "<hex>",
#         "line_count":  N,
#         "byte_size":   N
#       },
#       ...
#     }
#   }

[CmdletBinding()]
param(
  [string]$BaseRoot = (Join-Path $PSScriptRoot '..'),
  [string]$OutPath  = ''
)

$ErrorActionPreference = 'Stop'

$baseRootResolved = (Resolve-Path -LiteralPath $BaseRoot).Path
$toolsDir = Join-Path $baseRootResolved 'tools'
if (-not (Test-Path -LiteralPath $toolsDir)) {
  Write-Error "[upstream-contract] tools/ not found at $toolsDir"
  exit 1
}

if (-not $OutPath) {
  $OutPath = Join-Path $baseRootResolved '.autopilot/upstream-contract.json'
}

$validators = @{}
$files = Get-ChildItem -LiteralPath $toolsDir -Filter 'Validate-*.ps1' -File | Sort-Object Name
foreach ($f in $files) {
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
  # Line count: count "\n" occurrences plus 1 if file does not end with newline.
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $newlineCount = ([regex]::Matches($text, "`n")).Count
  $endsWithLf = $text.EndsWith("`n")
  $lineCount = if ($endsWithLf) { $newlineCount } else { $newlineCount + 1 }
  $validators[$f.Name] = [ordered]@{
    sha256     = $sha
    line_count = $lineCount
    byte_size  = $bytes.Length
  }
}

$manifest = [ordered]@{
  schema_version = 1
  generated_at   = (Get-Date).ToUniversalTime().ToString('o')
  template_repo  = 'mizan0515/autopilot-dad-template'
  validators     = $validators
}

$json = ($manifest | ConvertTo-Json -Depth 6) + "`n"

$outDir = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($OutPath, $json, $utf8NoBom)

Write-Host "[upstream-contract] wrote $OutPath ($($validators.Keys.Count) validator(s))"
