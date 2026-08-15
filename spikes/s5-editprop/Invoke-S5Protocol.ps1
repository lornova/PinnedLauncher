#Requires -Version 7
<#
PinnedLauncher spike S-5 (throwaway): guided protocol runner.

Automates everything automatable (icon rewrites, SHChangeNotify rungs, shortcut
edits, pin-folder waits, AUMID re-verification) and pauses with ONE clear
instruction whenever a human gesture or observation is needed. Before every
observable step it says WHAT TO WATCH, then acts, then collects the answer.
Every measurement and answer lands in results\s5-run-<timestamp>.json for
transcription into docs/spikes/s5-editprop.md.

Type 'skip' at any prompt to skip that step (recorded as skipped).
Ctrl+C aborts; partial results are still written.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S5Common.ps1')

# ---------- infrastructure ----------------------------------------------------

$startLnk        = Join-Path $s5StartDir $s5LnkName
$startLnkRenamed = Join-Path $s5StartDir $s5LnkRenamedName
$pinnedCopy      = Join-Path $s5PinDir $s5LnkName
$notify          = Join-Path $s5BinDir 's5notify.exe'

$script:steps = [System.Collections.Generic.List[object]]::new()

function Info([string]$m)  { Write-Host $m -ForegroundColor Cyan }
function Good([string]$m)  { Write-Host $m -ForegroundColor Green }
function Bad([string]$m)   { Write-Host $m -ForegroundColor Red }

function Action([string]$m) {
    Write-Host ''
    Write-Host ('  ACTION REQUIRED: ' + $m) -ForegroundColor Black -BackgroundColor Yellow
}

function Ask([string]$q) {
    $answer = Read-Host ("  ? " + $q)
    return $answer
}

function AskYN([string]$q) {
    while ($true) {
        $answer = Read-Host ("  ? " + $q + " [y/n/skip]")
        if ($answer -match '^(y|s|n)') { return $answer.Substring(0, 1) }
        Write-Host '    please answer y, n, or skip'
    }
}

function Record([string]$Id, [string]$Title, [hashtable]$Data) {
    $script:steps.Add([ordered]@{
        id    = $Id
        title = $Title
        at    = (Get-Date).ToString('o')
        data  = $Data
    })
}

# Waits for a pin-folder file to appear/disappear. Returns latency info.
function Wait-PinEvent([string]$Name, [ValidateSet('Appear','Disappear')][string]$Kind, [int]$TimeoutSec = 120) {
    $path = Join-Path $s5PinDir $Name
    $want = ($Kind -eq 'Appear')
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Info "  [auto] waiting up to ${TimeoutSec}s for '$Name' to $($Kind.ToLower()) in the pin folder... (press 's' if the action is impossible - skips this wait)"
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ([console]::KeyAvailable) {
            $key = [console]::ReadKey($true)
            if ($key.KeyChar -eq 's') {
                Bad "  [auto] wait skipped by user"
                return @{ detected = $false; skipped = $true; afterSeconds = $null }
            }
        }
        if ((Test-Path $path) -eq $want) {
            $sw.Stop()
            Good ("  [auto] detected: $Name $($Kind.ToLower())ed at {0:HH:mm:ss.fff} ({1:n1}s after watch start)" -f (Get-Date), $sw.Elapsed.TotalSeconds)
            return @{ detected = $true; afterSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2) }
        }
        Start-Sleep -Milliseconds 100
    }
    Bad "  [auto] TIMEOUT: no $Kind of '$Name' within ${TimeoutSec}s"
    return @{ detected = $false; afterSeconds = $null }
}

function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    Info ("  [auto] running: {0} {1}" -f $Exe, (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '))
    $output = & $Exe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host ($output.TrimEnd() -replace '(?m)^', '      ')
    return @{ exitCode = $code; output = $output.Trim() }
}

# ---------- preflight (all automatic) ----------------------------------------

Info '=== S-5 guided protocol runner ==='
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
Info "[auto] environment: $($cv.ProductName) $($cv.DisplayVersion) build $build edition $($cv.EditionID)"

if (-not (Test-Path $notify)) {
    Info '[auto] s5notify.exe missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S5Binaries.ps1')
}

foreach ($leftover in $s5LnkName, $s5LnkRenamedName) {
    if (Test-Path (Join-Path $s5PinDir $leftover)) {
        Action "leftover pin '$leftover' from an earlier run - right-click it on the taskbar and unpin it."
        [void](Wait-PinEvent $leftover Disappear)
    }
}

Info '[auto] (re)generating the test article - resets the icon to variant A...'
& (Join-Path $PSScriptRoot 'New-S5Shortcuts.ps1')
$script:iconVariant = 'A'

Record 'env' 'Environment and baseline' @{
    build = $build; edition = $cv.EditionID; displayVersion = $cv.DisplayVersion
    baselineFolder = @((Get-ChildItem $s5PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Name)
}

# Q1 escalation ladder. Order: silent control first, then targeted documented
# notifies, then the undocumented-location notify (policy caveat), then the
# global hammers, then the shipped cache utility, then the diagnostic-only
# Explorer restart.
$rungs = @(
    @{ id = 'N0'; what = 'control - no nudge, just observe';                          act = $null; obsSec = 30 }
    @{ id = 'N1'; what = 'SHCNE_UPDATEITEM on the Start-menu source .lnk';            act = { Invoke-Tool $notify @('updateitem', $startLnk) }; obsSec = 15 }
    @{ id = 'N2'; what = 'SHCNE_UPDATEITEM on the .ico file itself';                  act = { Invoke-Tool $notify @('updateitem', $s5IconPath) }; obsSec = 15 }
    @{ id = 'N3'; what = 'SHCNE_UPDATEDIR on the Start-menu spike folder';            act = { Invoke-Tool $notify @('updatedir', $s5StartDir) }; obsSec = 15 }
    @{ id = 'N4'; what = 'SHCNE_UPDATEITEM on the User Pinned\TaskBar copy';          act = { Invoke-Tool $notify @('updateitem', $pinnedCopy) }; obsSec = 15
       caveat = 'read-only knowledge of undocumented pin storage - if this is the ONLY working rung, the policy trade-off must be recorded before layering (report SS2)' }
    @{ id = 'N5'; what = 'SHCNE_UPDATEIMAGE index -1 (global icon-cache imagelist)';  act = { Invoke-Tool $notify @('updateimage') }; obsSec = 15
       caveat = 'GLOBAL: also watch other taskbar/desktop icons for flicker or rebuild - side effects decide whether this rung is acceptable' }
    @{ id = 'N6'; what = 'SHCNE_ASSOCCHANGED (global association/icon rebuild)';      act = { Invoke-Tool $notify @('assocchanged') }; obsSec = 15
       caveat = 'GLOBAL and heavier than N5 - same side-effect watch' }
    @{ id = 'N7'; what = 'ie4uinit.exe -show (shipped icon-cache refresh utility)';   act = $null; obsSec = 15 }
    @{ id = 'N8'; what = 'Explorer restart (diagnostic upper bound - NEVER a product mechanism)'; act = $null; obsSec = 20 }
)

try {

# ---------- Part 0: baseline pin ----------------------------------------------

Info "`n--- Part 0: pin the S5 entry (baseline) ---"
Info '[auto] the S5 icon is variant A: ORANGE SQUARE with a green corner badge.'
Action "Open Start -> Tutto -> 'PinnedLauncher S5 Spike' -> right-click 'S5 edit test' -> Aggiungi alla barra delle applicazioni."
$wait = Wait-PinEvent $s5LnkName Appear
$btnA = AskYN 'Does the new taskbar button show the ORANGE SQUARE with green corner badge?'
$startA = AskYN 'And the Start entry itself (in the Tutto list) - same orange square?'
Record 'P0-pin' 'Baseline pin placed' @{ wait = $wait; buttonVariantA = $btnA; startVariantA = $startA }

# ---------- Part 1 (Q1): in-place rewrite + escalation ladder -----------------

Info "`n--- Part 1 (Q1): in-place icon rewrite + escalation ladder ---"
Info 'WHAT TO WATCH from now to the end of Part 1: the S5 taskbar button.'
Info 'The moment it turns into a BLUE CIRCLE with a red corner badge, that rung wins.'

Write-S5Icon $s5IconPath 'B'; $script:iconVariant = 'B'
Info "[auto] icon file rewritten IN PLACE to variant B (blue circle, red badge): $s5IconPath"

$flippedAt = $null
foreach ($rung in $rungs) {
    Info ("`n[rung {0}] {1}" -f $rung.id, $rung.what)
    if ($rung.caveat) { Info ('  note: ' + $rung.caveat) }
    $tool = $null
    if ($rung.id -eq 'N7') {
        if (-not (Get-Command ie4uinit.exe -ErrorAction SilentlyContinue)) {
            Bad '  [auto] ie4uinit.exe not found - rung skipped'
            Record 'Q1-N7' $rung.what @{ skipped = $true }
            continue
        }
        $tool = Invoke-Tool 'ie4uinit.exe' @('-show')
    }
    elseif ($rung.id -eq 'N8') {
        $ok = AskYN 'Diagnostic upper bound: OK to restart Explorer now? (open Explorer windows will close)'
        if ($ok -ne 'y') {
            Record 'Q1-N8' $rung.what @{ skipped = $true }
            continue
        }
        Info '  [auto] restarting Explorer...'
        taskkill /f /im explorer.exe | Out-Null
        Start-Process explorer.exe
        Start-Sleep -Seconds 6
    }
    elseif ($rung.act) { $tool = & $rung.act }
    Action ("WATCH the S5 taskbar button for ~{0}s (hover it too - the flyout icon counts). Come back when it changes or the time is up." -f $rung.obsSec)
    $flip = AskYN 'Did the button turn into the BLUE CIRCLE with red badge?'
    $notes = Ask 'Latency / partial effects (e.g. only the hover flyout) / side effects? (Enter for none)'
    Record ('Q1-' + $rung.id) $rung.what @{ tool = $tool; flipped = $flip; notes = $notes }
    if ($flip -eq 'y') { $flippedAt = $rung.id; Good ("  rung {0} propagated the icon." -f $rung.id); break }
}
if (-not $flippedAt) {
    Bad '[auto] no rung propagated the icon - strong evidence the pin renders from its own stored copy/cache and no channel exists.'
}

$startB = AskYN 'Localization check - Start -> Tutto: does the S5 entry show the blue circle now?'
Record 'Q1-start-entry' 'Start entry state after the ladder' @{ startShowsB = $startB; flippedAt = $flippedAt }

if ($flippedAt -and $flippedAt -ne 'N8') {
    Info "`n[auto] stability repeat: icon back to variant A, re-running only rung $flippedAt."
    Write-S5Icon $s5IconPath 'A'; $script:iconVariant = 'A'
    $rung = $rungs | Where-Object id -eq $flippedAt
    $tool = if ($rung.id -eq 'N7') { Invoke-Tool 'ie4uinit.exe' @('-show') }
            elseif ($rung.act)     { & $rung.act }
    Action 'WATCH the button again (~20s): it should flip BACK to the orange square + green badge.'
    $flip = AskYN 'Flipped back to the orange square?'
    Record 'Q1-repeat' "Stability repeat via $flippedAt" @{ tool = $tool; flippedBack = $flip }
}

# ---------- Part 2 (Q2): name propagation -------------------------------------

Info "`n--- Part 2 (Q2): name propagation ---"
Info 'WHAT TO WATCH: the tooltip when hovering the S5 button, and the launcher entry name in its right-click (jump list) menu.'
$before = Ask "Hover the S5 taskbar button now - what does the tooltip say, exactly?"
Info '[auto] renaming the Start-menu source .lnk and sending SHCNE_RENAMEITEM...'
Rename-Item $startLnk $s5LnkRenamedName
$tool = Invoke-Tool $notify @('renameitem', $startLnk, $startLnkRenamed)
Action "Wait ~15s, then hover the S5 button again AND right-click it (read the launcher's own entry name in the jump list)."
$after = Ask 'Tooltip and jump-list name now? (unchanged / new name + notes)'
$startName = AskYN "Start -> Tutto: is the entry itself now listed as 'S5 renamed test'?"
Record 'Q2-name' 'Source rename propagation' @{ tooltipBefore = $before; tool = $tool; after = $after; startEntryRenamed = $startName }
Info '[auto] renaming back...'
Rename-Item $startLnkRenamed $s5LnkName
[void](Invoke-Tool $notify @('renameitem', $startLnkRenamed, $startLnk))

# ---------- Part 3 (Q3): versioned icon path (mechanism check) ----------------

Info "`n--- Part 3 (Q3): versioned icon path - does the pin re-read the source .lnk at all? ---"
$v2Variant = ($script:iconVariant -eq 'A') ? 'B' : 'A'
$v2Desc = ($v2Variant -eq 'B') ? 'BLUE CIRCLE + red badge' : 'ORANGE SQUARE + green badge'
$state = Ask 'First, a snapshot: what do (1) the Start entry and (2) the taskbar button show RIGHT NOW? (e.g. "both orange")'
Write-S5Icon $s5IconV2Path $v2Variant
Info "[auto] wrote a SECOND icon file (variant $v2Variant): $s5IconV2Path"
Set-S5LnkIcon $startLnk $s5IconV2Path
$tool = Invoke-Tool $notify @('updateitem', $startLnk)
$aumidAfter = Read-S5LnkAumid $startLnk
$aumidPreserved = ($aumidAfter -ceq $s5Aumid)
if ($aumidPreserved) { Good "  [auto] G0 re-check PASS: AUMID survived the IShellLink icon edit ($aumidAfter)" }
else                 { Bad "  [auto] G0 re-check FAIL: AUMID after the edit is '$aumidAfter'" }
Action "Wait ~15s, then check BOTH: (1) the Start -> Tutto entry icon; (2) the taskbar button. Mechanism-model expectation: Start flips to $v2Desc, the button does NOT change."
$startFlip = AskYN "Did the START entry change to the $v2Desc?"
$pinFlip = AskYN 'Did the TASKBAR button change from the snapshot you just reported?'
Record 'Q3-versioned-path' 'Versioned icon path on the source' @{
    snapshotBefore = $state; tool = $tool; aumidPreserved = $aumidPreserved
    startChanged = $startFlip; pinChanged = $pinFlip
}
Info '[auto] restoring the source to the stable icon path...'
Set-S5LnkIcon $startLnk $s5IconPath
[void](Invoke-Tool $notify @('updateitem', $startLnk))

# ---------- wrap-up ------------------------------------------------------------

Info "`n--- Cleanup ---"
$late = Ask 'Before cleanup: did any icon/name change show up LATER than the step where it was recorded? (Enter for no, else notes)'
Record 'late-observations' 'Delayed propagation observations' @{ notes = $late }

$s4unpin = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4unpin.exe'
if (Test-Path $s4unpin) {
    Info '[auto] unpinning via the S-4-validated RemoveFromList (bonus data point on a second AUMID)...'
    $tool = Invoke-Tool $s4unpin @($startLnk)
    $wait = Wait-PinEvent $s5LnkName Disappear -TimeoutSec 10
    if (-not $wait.detected) {
        Action 'Programmatic unpin did not land - right-click the S5 pin -> Rimuovi dalla barra delle applicazioni.'
        $wait = Wait-PinEvent $s5LnkName Disappear
    }
    Record 'cleanup-unpin' 'Unpin (programmatic, S-4 mechanism)' @{ tool = $tool; wait = $wait }
}
else {
    Action 'Right-click the S5 pin -> Rimuovi dalla barra delle applicazioni.'
    Record 'cleanup-unpin' 'Unpin (gesture)' @{ wait = (Wait-PinEvent $s5LnkName Disappear) }
}
Info "[auto] Start-menu folder and out\ left in place for re-runs; remove per protocol SS5.4 when the spike is closed."

}
finally {
    if ($script:steps.Count -gt 0) {
        $resultsDir = Join-Path $PSScriptRoot 'results'
        New-Item -ItemType Directory -Force $resultsDir | Out-Null
        $resultsPath = Join-Path $resultsDir ("s5-run-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        @{ run = 's5-editprop'; started = $script:steps[0].at; machineBuild = $build; steps = $script:steps } |
            ConvertTo-Json -Depth 8 | Set-Content $resultsPath -Encoding utf8
        Good "`nResults written to: $resultsPath"
        Good 'Tell Claude the run is complete - the JSON will be transcribed into docs/spikes/s5-editprop.md.'
    }
}
