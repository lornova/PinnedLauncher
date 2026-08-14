#Requires -Version 7
<#
PinnedLauncher spike S-3 (throwaway): teardown. Unpin the six S3-* pins manually
first (right-click each pin -> Unpin from taskbar); this script refuses to run
while S3-* pin copies are still present unless -Force is given.
#>
[CmdletBinding()]
param(
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$leftover = @(Get-ChildItem $pinDir -Filter 'S3-*.lnk' -ErrorAction SilentlyContinue)
if ($leftover.Count -gt 0 -and -not $Force) {
    Write-Warning "Still pinned (unpin via right-click first): $($leftover.Name -join ', ')"
    Write-Warning 'Re-run with -Force to remove the other artifacts anyway.'
    return
}

Get-Process s3selfaumid -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S3 Spike') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $PSScriptRoot 'out') -Recurse -Force -ErrorAction SilentlyContinue
'S-3 shortcut artifacts removed (bin\ and src\ kept; delete the spike folder once the report is final).'
