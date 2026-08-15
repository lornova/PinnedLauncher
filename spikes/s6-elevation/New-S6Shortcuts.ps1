#Requires -Version 7
<#
PinnedLauncher spike S-6 (throwaway): generates the elevation test article —
the config file pointing at the self-reporting target, one AUMID-stamped
proxy shortcut targeting bin\s6proxy.exe, and the Start-menu entry.
Idempotent: always resets the config to the s6target path and replaces the
shortcut, so the runner can call it to reset state.

Gate G0: AUMID read back by an independent reader + binaries present +
config sanity. Protocol and result recording: docs/spikes/s6-elevation.md
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S6Common.ps1')

$proxyExe  = Join-Path $s6BinDir 's6proxy.exe'
$targetExe = Join-Path $s6BinDir 's6target.exe'

if (-not (Test-Path $proxyExe) -or -not (Test-Path $targetExe)) {
    'Binaries missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S6Binaries.ps1')
}

New-Item -ItemType Directory -Force $s6OutDir | Out-Null
Set-S6ConfigTarget $targetExe
$configBack = (Get-Content $s6ConfigPath -TotalCount 1).Trim()

$lnk = Join-Path $s6OutDir $s6LnkName
Remove-Item $lnk -Force -ErrorAction SilentlyContinue
[S6Lnk.ShortcutFactory]::Create(
    $lnk, $proxyExe,
    "PinnedLauncher spike S-6 | AUMID=$s6Aumid", $s6Aumid)
$readBack = Read-S6LnkAumid $lnk

$result = [pscustomobject]@{
    Shortcut      = $s6LnkName
    AumidStamped  = $s6Aumid
    AumidReadBack = $readBack
    ConfigTarget  = $configBack
    G0            = (($readBack -ceq $s6Aumid) -and
                     ($configBack -ceq $targetExe) -and
                     (Test-Path $proxyExe) -and (Test-Path $targetExe)) ? 'PASS' : 'FAIL'
}
$result | Format-Table -AutoSize -Wrap

if ($result.G0 -ne 'PASS') { throw 'Gate G0 failed.' }
"Gate G0: PASS (AUMID verified by independent reader; config points at s6target; binaries present)"

if (-not $NoStartMenu) {
    New-Item -ItemType Directory -Force $s6StartDir | Out-Null
    Remove-Item (Join-Path $s6StartDir '*.lnk') -Force -ErrorAction SilentlyContinue
    Copy-Item $lnk $s6StartDir -Force
    "Start-menu entry installed: $s6StartDir"
}
"Config and shortcut written to: $s6OutDir"
