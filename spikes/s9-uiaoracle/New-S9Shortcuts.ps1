#Requires -Version 7
<#
PinnedLauncher spike S-9 (throwaway): generates the oracle test article —
one AUMID-stamped proxy shortcut whose DISPLAY NAME equals the target
window's title (the name collision under test) and the Start-menu entry.
The .lnk targets charmap.exe, never clicked: targeting s9target.exe itself
would trip S-3's flavor-A path-association merge and destroy the
two-button scenario. Idempotent: replaces the shortcut on each call.

Gate G0: AUMID read back by an independent reader + binaries present.
Protocol and result recording: docs/spikes/s9-uiaoracle.md
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S9Common.ps1')

$uiaExe    = Join-Path $s9BinDir 's9uia.exe'
$targetExe = Join-Path $s9BinDir 's9target.exe'
$charmap   = Join-Path $env:windir 'System32\charmap.exe'

if (-not (Test-Path $uiaExe) -or -not (Test-Path $targetExe)) {
    'Binaries missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S9Binaries.ps1')
}

New-Item -ItemType Directory -Force $s9OutDir | Out-Null

$lnk = Join-Path $s9OutDir $s9LnkName
Remove-Item $lnk -Force -ErrorAction SilentlyContinue
[S9Lnk.ShortcutFactory]::Create(
    $lnk, $charmap,
    "PinnedLauncher spike S-9 | AUMID=$s9Aumid", $s9Aumid)
$readBack = Read-S9LnkAumid $lnk

$result = [pscustomobject]@{
    Shortcut      = $s9LnkName
    AumidStamped  = $s9Aumid
    AumidReadBack = $readBack
    G0            = (($readBack -ceq $s9Aumid) -and
                     (Test-Path $uiaExe) -and (Test-Path $targetExe)) ? 'PASS' : 'FAIL'
}
$result | Format-Table -AutoSize -Wrap

if ($result.G0 -ne 'PASS') { throw 'Gate G0 failed.' }
"Gate G0: PASS (AUMID verified by independent reader; binaries present)"

if (-not $NoStartMenu) {
    New-Item -ItemType Directory -Force $s9StartDir | Out-Null
    Remove-Item (Join-Path $s9StartDir '*.lnk') -Force -ErrorAction SilentlyContinue
    Copy-Item $lnk $s9StartDir -Force
    "Start-menu entry installed: $s9StartDir"
}
"Shortcut written to: $s9OutDir"
