# Rotate-History.ps1
#
# Round-7 F70 — automated HISTORY.md rotation helper (closes the
# dashboard-side gap: PROMPT.md row 15 prescribed rotation when
# HISTORY.md exceeds 60 KB, and F42 detected the size-cap violation,
# but no actual rotation tool shipped — operators had to do the
# move-and-pointer dance by hand).
#
# Universal: pure markdown manipulation, no engine specifics.
#
# Behavior:
#   1. Read .autopilot/HISTORY.md.
#   2. If file size <= threshold (default 61440 bytes ≈ 60 KB),
#      no-op and exit 0.
#   3. Split content into preamble (lines before the first `## iter`
#      header) and entries (each `## iter <N>` block, newest on top).
#   4. Keep the newest `keep_recent_count` entries (default = half,
#      rounded up). Archive the rest.
#   5. Write archived entries to `.autopilot/.archive/HISTORY-<N>.md`
#      where N is the newest archived iter number (stable, unique
#      per rotation event). If the file already exists, append a
#      numeric suffix.
#   6. Rewrite HISTORY.md = preamble + kept entries + pointer line
#      `\n... (archived to .archive/HISTORY-<N>.md)\n`.
#
# Configuration (`.autopilot/config.json`, optional):
#   history_size_threshold_bytes : int — default 61440 (60 KB).
#   history_keep_recent_entries  : int — default = ceil(N/2) where N
#                                  is current entry count.
#
# Usage:
#   pwsh tools/Rotate-History.ps1 -AutopilotRoot .autopilot
#   pwsh tools/Rotate-History.ps1 -AutopilotRoot .autopilot -Force
#       — Force ignores the size threshold (rotates anyway).
#   pwsh tools/Rotate-History.ps1 -AutopilotRoot .autopilot -DryRun
#       — Reports what would be archived but does not write.
#
# Exit codes:
#   0 — no-op (under threshold) or rotation succeeded.
#   1 — error (HISTORY.md missing, malformed, etc.).

[CmdletBinding()]
param(
  [string]$AutopilotRoot = '.autopilot',
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$historyPath = Join-Path $AutopilotRoot 'HISTORY.md'
$archiveDir  = Join-Path $AutopilotRoot '.archive'
$cfgPath     = Join-Path $AutopilotRoot 'config.json'

if (-not (Test-Path -LiteralPath $historyPath)) {
  Write-Error "[rotate-history] HISTORY.md not found at $historyPath"
  exit 1
}

# --- config ---------------------------------------------------------------

$thresholdBytes = 61440
$keepRecentOverride = 0
if (Test-Path -LiteralPath $cfgPath) {
  try {
    $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -ErrorAction Stop
    if ($cfg.PSObject.Properties.Name -contains 'history_size_threshold_bytes') {
      $v = $cfg.history_size_threshold_bytes
      if ($v -is [int] -and $v -gt 0) { $thresholdBytes = [int]$v }
    }
    if ($cfg.PSObject.Properties.Name -contains 'history_keep_recent_entries') {
      $v = $cfg.history_keep_recent_entries
      if ($v -is [int] -and $v -gt 0) { $keepRecentOverride = [int]$v }
    }
  } catch { }
}

# --- size gate ------------------------------------------------------------

$sizeBytes = (Get-Item -LiteralPath $historyPath).Length
if (-not $Force -and $sizeBytes -le $thresholdBytes) {
  Write-Host "[rotate-history] OK — $sizeBytes bytes ≤ $thresholdBytes (no rotation needed)"
  exit 0
}

# --- parse ----------------------------------------------------------------

$rawText = [System.IO.File]::ReadAllText($historyPath)
$lines = $rawText -split "`r?`n"

$entries = @()  # array of {iter, lineno, raw_block_lines}
$current = $null
$preambleLines = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  if ($line -match '^##\s+iter\s+(\d+)\b') {
    if ($current) { $entries += $current }
    $current = [pscustomobject]@{
      iter   = [int]$Matches[1]
      lineno = ($i + 1)
      raw    = @($line)
    }
  } elseif ($current) {
    $current.raw += $line
  } else {
    $preambleLines += $line
  }
}
if ($current) { $entries += $current }

if ($entries.Count -lt 2) {
  Write-Host "[rotate-history] only $($entries.Count) entry(ies) — nothing to rotate"
  exit 0
}

# Strip a trailing pointer line ("... (archived to ...)") from the
# preamble or from the last entry's raw lines if it leaks through.
function Remove-TrailingArchivePointer($arr) {
  $out = @($arr)
  while ($out.Count -gt 0 -and ([string]$out[-1]).TrimStart() -match '^\.\.\.\s*\(archived to ') {
    if ($out.Count -le 1) { $out = @() ; break }
    $out = $out[0..($out.Count - 2)]
  }
  return $out
}

# --- decide split --------------------------------------------------------

$totalEntries = $entries.Count
$keepCount = if ($keepRecentOverride -gt 0) { $keepRecentOverride } else { [int][math]::Ceiling($totalEntries / 2.0) }
if ($keepCount -ge $totalEntries) {
  Write-Host "[rotate-history] keep_recent_count ($keepCount) >= entry count ($totalEntries) — nothing to archive"
  exit 0
}

$kept = @($entries[0..($keepCount - 1)])
$archived = @($entries[$keepCount..($entries.Count - 1)])

# Newest archived iter = first one in $archived (since file is newest-on-top).
$newestArchivedIter = $archived[0].iter
$archiveName = "HISTORY-$newestArchivedIter.md"
$archivePath = Join-Path $archiveDir $archiveName
if (Test-Path -LiteralPath $archivePath) {
  $suffix = 2
  while (Test-Path -LiteralPath (Join-Path $archiveDir "HISTORY-$newestArchivedIter-$suffix.md")) { $suffix++ }
  $archiveName = "HISTORY-$newestArchivedIter-$suffix.md"
  $archivePath = Join-Path $archiveDir $archiveName
}

# --- materialize ---------------------------------------------------------

# Preamble: trim any prior archive pointer lines.
$cleanedPreamble = Remove-TrailingArchivePointer $preambleLines
# Strip trailing blank lines so we don't accumulate gaps.
while ($cleanedPreamble.Count -gt 0 -and [string]::IsNullOrWhiteSpace($cleanedPreamble[-1])) {
  if ($cleanedPreamble.Count -le 1) { $cleanedPreamble = @() ; break }
  $cleanedPreamble = $cleanedPreamble[0..($cleanedPreamble.Count - 2)]
}

$archiveLines = @()
foreach ($e in $archived) {
  if ($archiveLines.Count -gt 0 -and $archiveLines[-1] -ne '') { $archiveLines += '' }
  $archiveLines += $e.raw
}
# Strip a trailing pointer line that might have been part of the last archived entry's raw block.
$archiveLines = Remove-TrailingArchivePointer $archiveLines
# Add archive-file header preamble for clarity.
$archiveHeader = @(
  '# HISTORY (archive)',
  '',
  "Archived from .autopilot/HISTORY.md at iter range [$($archived[-1].iter)..$($archived[0].iter)] inclusive (newest on top, same as live file).",
  ''
)
$finalArchive = ($archiveHeader + $archiveLines) -join "`n"
if (-not $finalArchive.EndsWith("`n")) { $finalArchive += "`n" }

# Live: preamble + kept entries + pointer
$liveLines = @()
$liveLines += $cleanedPreamble
if ($liveLines.Count -gt 0 -and $liveLines[-1] -ne '') { $liveLines += '' }
foreach ($e in $kept) {
  if ($liveLines.Count -gt 0 -and $liveLines[-1] -ne '') { $liveLines += '' }
  $liveLines += $e.raw
}
$liveLines = Remove-TrailingArchivePointer $liveLines
while ($liveLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($liveLines[-1])) {
  if ($liveLines.Count -le 1) { $liveLines = @() ; break }
  $liveLines = $liveLines[0..($liveLines.Count - 2)]
}
$liveLines += ''
$liveLines += "... (archived to .archive/$archiveName)"
$finalLive = ($liveLines -join "`n") + "`n"

# --- write ----------------------------------------------------------------

if ($DryRun) {
  Write-Host "[rotate-history] DRY-RUN: would write $($archived.Count) entry(ies) to $archivePath"
  Write-Host "[rotate-history] DRY-RUN: would keep $($kept.Count) entry(ies) in HISTORY.md"
  exit 0
}

if (-not (Test-Path -LiteralPath $archiveDir)) {
  New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($archivePath, $finalArchive, $utf8NoBom)
[System.IO.File]::WriteAllText($historyPath, $finalLive, $utf8NoBom)

$newSize = (Get-Item -LiteralPath $historyPath).Length
Write-Host "[rotate-history] archived $($archived.Count) entry(ies) → $archivePath"
Write-Host "[rotate-history] HISTORY.md: $sizeBytes → $newSize bytes ($($kept.Count) entry(ies) kept)"
exit 0
