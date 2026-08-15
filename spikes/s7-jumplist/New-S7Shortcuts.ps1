#Requires -Version 7
<#
PinnedLauncher spike S-7 (throwaway): generates the jump-list test article —
one AUMID-stamped proxy shortcut targeting bin\s7taskecho.exe and the
Start-menu entry. Idempotent: replaces the shortcut on each call. The pin is
never clicked in this spike (jump-list lifecycle only), so the echo target
doubles harmlessly as the shortcut target.

Gate G0: AUMID read back by an independent reader + binaries present.
Protocol and result recording: docs/spikes/s7-jumplist.md
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S7Common.ps1')

$jumplistExe = Join-Path $s7BinDir 's7jumplist.exe'
$taskEchoExe = Join-Path $s7BinDir 's7taskecho.exe'

if (-not (Test-Path $jumplistExe) -or -not (Test-Path $taskEchoExe)) {
    'Binaries missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S7Binaries.ps1')
}

New-Item -ItemType Directory -Force $s7OutDir | Out-Null

$lnk = Join-Path $s7OutDir $s7LnkName
Remove-Item $lnk -Force -ErrorAction SilentlyContinue
[S7Lnk.ShortcutFactory]::Create(
    $lnk, $taskEchoExe,
    "PinnedLauncher spike S-7 | AUMID=$s7Aumid", $s7Aumid)
$readBack = Read-S7LnkAumid $lnk

$result = [pscustomobject]@{
    Shortcut      = $s7LnkName
    AumidStamped  = $s7Aumid
    AumidReadBack = $readBack
    G0            = (($readBack -ceq $s7Aumid) -and
                     (Test-Path $jumplistExe) -and (Test-Path $taskEchoExe)) ? 'PASS' : 'FAIL'
}
$result | Format-Table -AutoSize -Wrap

if ($result.G0 -ne 'PASS') { throw 'Gate G0 failed.' }
"Gate G0: PASS (AUMID verified by independent reader; binaries present)"

if (-not $NoStartMenu) {
    New-Item -ItemType Directory -Force $s7StartDir | Out-Null
    Remove-Item (Join-Path $s7StartDir '*.lnk') -Force -ErrorAction SilentlyContinue
    Copy-Item $lnk $s7StartDir -Force
    "Start-menu entry installed: $s7StartDir"
}
"Shortcut written to: $s7OutDir"
