#Requires -Version 7
<#
PinnedLauncher spike S-5 (throwaway): generates the edit-propagation test
article — the variant-A badged icon at its STABLE path, one AUMID-stamped
proxy shortcut pointing at it, and the Start-menu entry. Idempotent: always
resets the icon to variant A and clears leftovers from earlier runs (renamed
.lnk, v2 icon), so the runner can call it to reset state.

The target is never clicked in this spike — icon/name lifecycle only — so a
direct charmap target is fine despite the S-3 flavor-A finding.

Gate G0: AUMID read back by an independent reader + ICO header sanity.
Protocol and result recording: docs/spikes/s5-editprop.md
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S5Common.ps1')

$charmap = Join-Path $env:windir 'System32\charmap.exe'

New-Item -ItemType Directory -Force $s5OutDir | Out-Null
Remove-Item $s5IconV2Path -Force -ErrorAction SilentlyContinue

Write-S5Icon $s5IconPath 'A'
$icoBytes = [System.IO.File]::ReadAllBytes($s5IconPath)
$icoOk = $icoBytes.Length -gt 22 -and
         $icoBytes[0] -eq 0 -and $icoBytes[1] -eq 0 -and   # reserved
         $icoBytes[2] -eq 1 -and $icoBytes[3] -eq 0        # type 1 = icon

$lnk = Join-Path $s5OutDir $s5LnkName
Remove-Item $lnk -Force -ErrorAction SilentlyContinue
[S5Lnk.ShortcutFactory]::Create(
    $lnk, $charmap, $s5IconPath,
    "PinnedLauncher spike S-5 | AUMID=$s5Aumid", $s5Aumid)
$readBack = Read-S5LnkAumid $lnk

$result = [pscustomobject]@{
    Shortcut      = $s5LnkName
    AumidStamped  = $s5Aumid
    AumidReadBack = $readBack
    IcoHeader     = $icoOk ? 'OK' : 'BAD'
    G0            = (($readBack -ceq $s5Aumid) -and $icoOk) ? 'PASS' : 'FAIL'
}
$result | Format-Table -AutoSize -Wrap

if ($result.G0 -ne 'PASS') { throw 'Gate G0 failed.' }
"Gate G0: PASS (AUMID verified by independent reader; ICO header sane)"

if (-not $NoStartMenu) {
    New-Item -ItemType Directory -Force $s5StartDir | Out-Null
    Remove-Item (Join-Path $s5StartDir '*.lnk') -Force -ErrorAction SilentlyContinue
    Copy-Item $lnk $s5StartDir -Force
    "Start-menu entry installed: $s5StartDir"
}
"Icon (variant A) and shortcut written to: $s5OutDir"
