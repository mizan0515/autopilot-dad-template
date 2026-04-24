# base/tools/Start-Process-Safe.ps1
#
# Wrapper around Start-Process that (a) forces spaced-path args to be safely
# quoted and (b) polls the process list to verify the target PID materialized.
#
# Motivated by two recurring PITFALLS:
#   1. Start-Process with -ArgumentList "-projectPath","C:\My Path" silently
#      truncates at the space. PowerShell's array form re-splits on whitespace
#      before passing to CreateProcess.
#   2. A successful Start-Process exit does not mean the child process is
#      actually running. Launcher shells can fork and die without the target
#      ever appearing.
#
# Usage:
#   $p = & (Join-Path $PSScriptRoot '../tools/Start-Process-Safe.ps1') `
#          -FilePath 'Unity.exe' `
#          -Args @('-projectPath', 'C:\Path With Spaces\proj') `
#          -WaitForPid 10
#   if (-not $p) { throw 'launch failed' }
#
# Return: System.Diagnostics.Process on success, $null on failure.

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FilePath,
  [string[]]$Args = @(),
  [int]$WaitForPid = 8,  # seconds to poll; 0 = don't wait
  [string]$WorkingDirectory
)

$ErrorActionPreference = 'Stop'

# Quote any argument that contains whitespace but is not already quoted.
$quoted = foreach ($a in $Args) {
  if ($null -eq $a) { continue }
  $s = [string]$a
  if ($s -match '\s' -and $s -notmatch '^".*"$') {
    '"' + $s + '"'
  } else {
    $s
  }
}
$argString = ($quoted -join ' ')

$spArgs = @{
  FilePath     = $FilePath
  PassThru     = $true
  ErrorAction  = 'Stop'
}
if ($argString) { $spArgs['ArgumentList'] = $argString }
if ($WorkingDirectory) { $spArgs['WorkingDirectory'] = $WorkingDirectory }

try {
  $p = Start-Process @spArgs
} catch {
  Write-Warning "[Start-Process-Safe] launch failed: $_"
  return $null
}

if ($WaitForPid -le 0 -or -not $p) { return $p }

# Poll: Start-Process can return a Process object whose Id never becomes real.
$deadline = (Get-Date).AddSeconds($WaitForPid)
while ((Get-Date) -lt $deadline) {
  try {
    $alive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($alive) { return $p }
  } catch { }
  Start-Sleep -Milliseconds 250
}

Write-Warning "[Start-Process-Safe] PID $($p.Id) did not materialize within ${WaitForPid}s"
return $null
