#Requires -Version 7
<#
PinnedLauncher spike S-9 (throwaway): guided protocol runner.

Almost everything here is automated (hygiene sweep, builds, article
generation with gate G0, the AppsFolder indexing poll, UIA dumps with
parsed comparisons, target launch/close, programmatic teardown); the human
steps shrink to the pin gesture and two visual confirmations. Before every
observable step it says WHAT TO WATCH, then acts, then collects the answer.
Every measurement and answer lands in results\s9-run-<timestamp>.json for
transcription into docs/spikes/s9-uiaoracle.md.

Press 's' during any [auto] wait if the requested action turns out to be
impossible (recorded as skipped). Ctrl+C aborts; partial results are still
written.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S9Common.ps1')

# ---------- infrastructure ----------------------------------------------------

$uiaExe    = Join-Path $s9BinDir 's9uia.exe'
$targetExe = Join-Path $s9BinDir 's9target.exe'
$startLnk  = Join-Path $s9StartDir $s9LnkName
$s4unpin   = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4unpin.exe'

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

function Wait-PinEvent([string]$Name, [ValidateSet('Appear','Disappear')][string]$Kind, [int]$TimeoutSec = 120) {
    $path = Join-Path $s9PinDir $Name
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

# Runs s9uia with a filter and parses the element lines into hashtables.
function Invoke-S9Uia([string]$Filter) {
    $output = & $uiaExe $Filter 2>&1 | Out-String
    $elements = @()
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -like 'element *') { $elements += , (ConvertFrom-S9UiaLine $line) }
    }
    @{ raw = $output.Trim(); elements = $elements; exitCode = $LASTEXITCODE }
}

# Elements whose Name begins with the display name (pin and running buttons
# both carry localized suffixes - "bloccato" / "finestra in esecuzione") or
# whose AutomationId is the pin's.
function Get-S9Buttons {
    $dump = Invoke-S9Uia $s9Name
    @($dump.elements | Where-Object { $_.name -like "$s9Name*" -or (Test-S9IsPinId $_.automationId) })
}

function Wait-S9ButtonCount([int]$Count, [string]$What, [int]$TimeoutSec = 30) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Info "  [auto] polling UIA up to ${TimeoutSec}s for $What..."
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $btns = @(Get-S9Buttons)   # @() at the call site: a single element unrolls to a bare hashtable whose .Count is its KEY count
        if ($btns.Count -eq $Count) {
            Good ("  [auto] reached {0} matching element(s) after {1:n1}s" -f $Count, $sw.Elapsed.TotalSeconds)
            return @{ detected = $true; afterSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); buttons = $btns }
        }
        Start-Sleep -Milliseconds 500
    }
    $btns = @(Get-S9Buttons)
    Bad "  [auto] TIMEOUT: $($btns.Count) matching element(s) after ${TimeoutSec}s (wanted $Count)"
    @{ detected = $false; buttons = $btns }
}

# The invariant comparison: identity + state properties only. rect is
# excluded on purpose — buttons legitimately shift when the bar re-lays out.
$s9CompareKeys = 'name', 'automationId', 'className', 'controlType', 'state', 'offscreen'
function Compare-S9Element([hashtable]$Baseline, [hashtable]$Current) {
    $changed = @()
    foreach ($k in $s9CompareKeys) {
        if ($Baseline[$k] -cne $Current[$k]) { $changed += "$k : '$($Baseline[$k])' -> '$($Current[$k])'" }
    }
    $changed
}

function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    Info ("  [auto] running: {0} {1}" -f $Exe, (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '))
    $output = & $Exe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host ($output.TrimEnd() -replace '(?m)^', '      ')
    return @{ exitCode = $code; output = $output.Trim() }
}

# ---------- preflight ----------------------------------------------------------

Info '=== S-9 guided protocol runner ==='
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
Info "[auto] environment: $($cv.ProductName) $($cv.DisplayVersion) build $build edition $($cv.EditionID)"

if (-not (Test-Path $uiaExe) -or -not (Test-Path $targetExe)) {
    Info '[auto] binaries missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S9Binaries.ps1')
}

# Hygiene sweep (Q3): the failed-run-recovery reference implementation.
# Enumerate the pin folder, read each copy's AUMID, flag PinnedLauncher.Test.*
# leftovers, unpin programmatically - Start source if it exists, else the
# pinned copy itself (a path form S-4 never needed; its outcome is a datum).
Info '[auto] hygiene sweep: reading the AUMID of every pinned copy...'
$sweep = @()
foreach ($lnk in (Get-ChildItem $s9PinDir -Filter *.lnk -ErrorAction SilentlyContinue)) {
    $aumid = Read-S9LnkAumid $lnk.FullName
    if ($aumid -like 'PinnedLauncher.Test.*') {
        Bad "  [auto] leftover found: '$($lnk.Name)' AUMID=$aumid"
        $entry = [ordered]@{ lnk = $lnk.Name; aumid = $aumid; unpinForm = $null; unpin = $null }
        if (Test-Path $s4unpin) {
            $source = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter $lnk.Name -ErrorAction SilentlyContinue |
                      Where-Object { (Read-S9LnkAumid $_.FullName) -ceq $aumid } | Select-Object -First 1
            $entry.unpinForm = $source ? 'start-source' : 'pinned-copy'
            $entry.unpin = Invoke-Tool $s4unpin @($source ? $source.FullName : $lnk.FullName)
            $entry.gone = -not (Test-Path $lnk.FullName)
            if ($entry.gone) { Good "  [auto] leftover unpinned programmatically ($($entry.unpinForm))" }
            else {
                Action "programmatic unpin failed - right-click '$($lnk.BaseName)' on the taskbar and unpin it."
                [void](Wait-PinEvent $lnk.Name Disappear)
            }
        }
        else {
            Action "s4unpin.exe not built - right-click '$($lnk.BaseName)' on the taskbar and unpin it."
            [void](Wait-PinEvent $lnk.Name Disappear)
        }
        $sweep += , $entry
    }
}
if ($sweep.Count -eq 0) { Good '  [auto] no PinnedLauncher.Test.* leftovers - environment clean' }
Record 'sweep' 'Q3: preflight hygiene sweep' @{ leftovers = $sweep; pinCount = @(Get-ChildItem $s9PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Count }

Info '[auto] (re)generating the test article...'
& (Join-Path $PSScriptRoot 'New-S9Shortcuts.ps1')

# Taskbar combine mode changes how running buttons are named/grouped
# (0 = always combine, 1 = when full, 2 = never combine + labels) - an
# environment variable the P2 oracle matrix must track.
$glom = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction SilentlyContinue).TaskbarGlomLevel
Record 'env' 'Environment and baseline' @{
    build = $build; edition = $cv.EditionID; displayVersion = $cv.DisplayVersion
    taskbarGlomLevel = $glom
    baselineFolder = @((Get-ChildItem $s9PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Name)
}

try {

# ---------- Part 0: pin -------------------------------------------------------

Info "`n--- Part 0: pin the S9 entry ---"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$indexed = $false
Info '[auto] waiting up to 120s for the shell to index the new AUMID in shell:AppsFolder... (press ''s'' to skip)'
while ($sw.Elapsed.TotalSeconds -lt 120) {
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.KeyChar -eq 's') { Bad '  [auto] wait skipped by user'; break }
    }
    $apps = (New-Object -ComObject Shell.Application).Namespace('shell:AppsFolder')
    if ($null -ne $apps.ParseName($s9Aumid)) { $indexed = $true; break }
    Start-Sleep -Seconds 1
}
$indexLatency = [math]::Round($sw.Elapsed.TotalSeconds, 1)
if ($indexed) { Good "  [auto] AUMID indexed after ${indexLatency}s" }
else          { Bad  "  [auto] AUMID still not indexed after ${indexLatency}s - falling back to the Start route" }

$s4select = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4select.exe'
if ($indexed -and (Test-Path $s4select)) {
    Info '[auto] opening the Apps view with the S9 entry pre-selected (the S-4-decided deep link)...'
    $tool = Invoke-Tool $s4select @($s9Aumid)
    Action "In the opened view, right-click the highlighted 'S9 pin test' -> Aggiungi alla barra delle applicazioni."
}
else {
    $tool = $null
    Action "Open Start -> Tutto -> right-click 'S9 pin test' (the single-entry spike folder is FLATTENED - the entry sits directly in the list) -> Aggiungi alla barra delle applicazioni."
}
$wait = Wait-PinEvent $s9LnkName Appear
Record 'P0-pin' 'Baseline pin placed' @{
    appsFolderIndexed = $indexed; indexLatencySeconds = $indexLatency
    deepLink = $tool; wait = $wait
}

# ---------- Part 1 (Q1): pin alone --------------------------------------------

Info "`n--- Part 1 (Q1): UIA view of the pin, nothing running ---"
$found = Wait-S9ButtonCount 1 'the pin button to appear in the UIA tree'
$baseline = $found.buttons | Select-Object -First 1
if ($baseline) {
    Info ("  [auto] pin element: name='{0}' automationId='{1}' className='{2}' controlType={3} state={4} offscreen={5}" -f `
        $baseline.name, $baseline.automationId, $baseline.className, $baseline.controlType, $baseline.state, $baseline.offscreen)
    if (Test-S9IsPinId $baseline.automationId) { Good "  [auto] HYPOTHESIS CONFIRMED: AutomationId carries our AUMID ('$($baseline.automationId)')" }
    else { Bad "  [auto] hypothesis NOT confirmed: AutomationId='$($baseline.automationId)' (oracle must use another discriminator)" }
}
else { Bad '  [auto] pin button NOT found in the UIA tree' }
$visual1 = AskYN "Visual check: exactly ONE 'S9 pin test' button on the taskbar?"
Record 'Q1-pin-alone' 'Q1: pin-alone element' @{
    wait = $found; element = $baseline
    aumidIsAutomationId = ($baseline -and (Test-S9IsPinId $baseline.automationId))
    visualOneButton = $visual1
}

# ---------- Part 2 (Q2): same-named running target ----------------------------

Info "`n--- Part 2 (Q2): the collision - a running window named exactly like the pin ---"
Info 'WHAT TO WATCH: a small window titled ''S9 pin test'' opens; the taskbar should show TWO buttons - the pin AND the running window, never one merged button.'
$targetProc = Start-Process $targetExe -ArgumentList "`"$s9Name`"" -PassThru
$two = Wait-S9ButtonCount 2 'the running-target button to join the pin in the UIA tree'
$pinNow = $null; $running = $null
if ($two.buttons.Count -ge 2 -and $baseline) {
    $pinNow  = $two.buttons | Where-Object { $_.automationId -ceq $baseline.automationId } | Select-Object -First 1
    $running = $two.buttons | Where-Object { $_.automationId -cne $baseline.automationId } | Select-Object -First 1
    $aumidUnique = @($two.buttons | Where-Object { Test-S9IsPinId $_.automationId }).Count
    if ($aumidUnique -eq 1) { Good '  [auto] exactly ONE element carries our AUMID - the discriminator holds under collision' }
    else { Bad "  [auto] $aumidUnique elements carry our AUMID (expected 1)" }
    Info ("  [auto] running element: name='{0}' automationId='{1}' state={2}" -f $running.name, $running.automationId, $running.state)
    $changed = Compare-S9Element $baseline $pinNow
    if ($changed.Count -eq 0) { Good '  [auto] F-2 INVARIANT HOLDS: pin element unchanged while the target runs' }
    else { Bad ("  [auto] pin element CHANGED: " + ($changed -join '; ')) }
}
$visual2 = AskYN 'Visual check: TWO separate buttons on the taskbar?'
$hover = AskYN 'Hover both: does ONLY the running one show a window preview thumbnail?'
Record 'Q2-collision' 'Q2: same-named running target' @{
    wait = $two; pinElement = $pinNow; runningElement = $running
    pinChanged = ($baseline -and $pinNow) ? (Compare-S9Element $baseline $pinNow) : @('n/a')
    visualTwoButtons = $visual2; hoverPreviewOnlyRunning = $hover
}

# ---------- Part 3 (Q2): negative control - target closes ---------------------

Info "`n--- Part 3 (Q2): target closes - back to the pin alone ---"
Info '[auto] closing the target gracefully...'
[void]$targetProc.CloseMainWindow()
$one = Wait-S9ButtonCount 1 'the running-target button to leave the UIA tree'
$survivor = $one.buttons | Select-Object -First 1
if ($survivor -and $baseline) {
    if (Test-S9IsPinId $survivor.automationId) { Good '  [auto] survivor carries our AUMID - the pin remains' }
    $changed = Compare-S9Element $baseline $survivor
    if ($changed.Count -eq 0) { Good '  [auto] pin element back at / still at baseline' }
    else { Bad ("  [auto] pin element differs from baseline: " + ($changed -join '; ')) }
}
Record 'Q2-close' 'Q2: negative control after target close' @{
    wait = $one; survivor = $survivor
    survivorChanged = ($baseline -and $survivor) ? (Compare-S9Element $baseline $survivor) : @('n/a')
}

# ---------- Part 4 (Q3): gesture-free teardown --------------------------------

Info "`n--- Part 4 (Q3): teardown, fully programmatic ---"
$late = Ask 'Before teardown: anything unexpected at ANY point? (Enter for no, else notes)'
Record 'late-observations' 'Late / unexpected observations' @{ notes = $late }

if (Test-Path $s4unpin) {
    $tool = Invoke-Tool $s4unpin @($startLnk)
    $wait = Wait-PinEvent $s9LnkName Disappear -TimeoutSec 10
    if (-not $wait.detected) {
        Action 'Programmatic unpin did not land - right-click the S9 pin -> Rimuovi dalla barra delle applicazioni.'
        $wait = Wait-PinEvent $s9LnkName Disappear
    }
    $uiaGone = Wait-S9ButtonCount 0 'the pin button to leave the UIA tree'
    Record 'cleanup-unpin' 'Q3: teardown (programmatic)' @{ tool = $tool; wait = $wait; uiaGone = $uiaGone.detected }
}
else {
    Action 'Right-click the S9 pin -> Rimuovi dalla barra delle applicazioni.'
    Record 'cleanup-unpin' 'Q3: teardown (gesture fallback)' @{ wait = (Wait-PinEvent $s9LnkName Disappear) }
}
Info "[auto] Start-menu folder and out\ left in place for re-runs; remove per protocol SS5.5 when the spike is closed."

}
finally {
    if ($script:steps.Count -gt 0) {
        $resultsDir = Join-Path $PSScriptRoot 'results'
        New-Item -ItemType Directory -Force $resultsDir | Out-Null
        $resultsPath = Join-Path $resultsDir ("s9-run-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        @{ run = 's9-uiaoracle'; started = $script:steps[0].at; machineBuild = $build; steps = $script:steps } |
            ConvertTo-Json -Depth 8 | Set-Content $resultsPath -Encoding utf8
        Good "`nResults written to: $resultsPath"
        Good 'Tell Claude the run is complete - the JSON will be transcribed into docs/spikes/s9-uiaoracle.md.'
    }
}
