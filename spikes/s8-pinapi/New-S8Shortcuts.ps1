#Requires -Version 7
<#
PinnedLauncher spike S-8 (throwaway): generates the test article — one
AUMID-stamped proxy shortcut (the generated Start entry the pin request
must target) in the Start-menu spike folder. The .lnk targets charmap.exe
(a real, harmless target: the click-equivalence step launches it once);
per S-3, the explicit AUMID keeps the launched target on its own button.
Idempotent: replaces the shortcut on each call.

Gate G0: AUMID read back by an independent reader + binaries present
(s8pin.exe here, s9uia.exe reused from spike S-9 for the UIA oracle).
Protocol and result recording: docs/spikes/s8-pinapi.md
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S8Common.ps1')

$pinExe  = Join-Path $s8BinDir 's8pin.exe'
$uiaExe  = Join-Path $PSScriptRoot '..\s9-uiaoracle\bin\s9uia.exe'
$charmap = Join-Path $env:windir 'System32\charmap.exe'

if (-not (Test-Path $pinExe)) {
    's8pin.exe missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S8Binaries.ps1')
}
if (-not (Test-Path $uiaExe)) {
    's9uia.exe missing - building via the S-9 build script...'
    & (Join-Path $PSScriptRoot '..\s9-uiaoracle\Build-S9Binaries.ps1')
}

New-Item -ItemType Directory -Force $s8OutDir | Out-Null

$lnk = Join-Path $s8OutDir $s8LnkName
Remove-Item $lnk -Force -ErrorAction SilentlyContinue
[S8Lnk.ShortcutFactory]::Create(
    $lnk, $charmap,
    "PinnedLauncher spike S-8 | AUMID=$s8Aumid", $s8Aumid)
$readBack = Read-S8LnkAumid $lnk

$result = [pscustomobject]@{
    Shortcut      = $s8LnkName
    AumidStamped  = $s8Aumid
    AumidReadBack = $readBack
    G0            = (($readBack -ceq $s8Aumid) -and
                     (Test-Path $pinExe) -and (Test-Path $uiaExe)) ? 'PASS' : 'FAIL'
}
$result | Format-Table -AutoSize -Wrap

if ($result.G0 -ne 'PASS') { throw 'Gate G0 failed.' }
"Gate G0: PASS (AUMID verified by independent reader; binaries present)"

if (-not $NoStartMenu) {
    New-Item -ItemType Directory -Force $s8StartDir | Out-Null
    Remove-Item (Join-Path $s8StartDir '*.lnk') -Force -ErrorAction SilentlyContinue
    Copy-Item $lnk $s8StartDir -Force
    "Start-menu entry installed: $s8StartDir"
}
"Shortcut written to: $s8OutDir"
