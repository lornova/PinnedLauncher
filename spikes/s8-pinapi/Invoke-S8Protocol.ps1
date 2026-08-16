#Requires -Version 7
<#
PinnedLauncher spike S-8 (throwaway): guided protocol runner.

Almost everything here is automated (hygiene sweep, builds, article
generation with gate G0, the AppsFolder indexing poll, the s8pin.exe
probe/pin routes, UIA equivalence checks against the S-9 oracle, the
programmatic teardown); the human steps shrink to answering the consent
dialogs and a few visual confirmations. Before every observable step it
says WHAT TO WATCH, then acts, then collects the answer. Every measurement
and answer lands in results\s8-run-<timestamp>.json for transcription into
docs/spikes/s8-pinapi.md.

Press 's' during any [auto] wait if the requested action turns out to be
impossible (recorded as skipped). Ctrl+C aborts; partial results are still
written.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S8Common.ps1')

# ---------- infrastructure ----------------------------------------------------

$pinExe   = Join-Path $s8BinDir 's8pin.exe'
$uiaExe   = Join-Path $PSScriptRoot '..\s9-uiaoracle\bin\s9uia.exe'
$s4unpin  = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4unpin.exe'
$startLnk = Join-Path $s8StartDir $s8LnkName

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
    $path = Join-Path $s8PinDir $Name
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

# Runs s9uia (the S-9 oracle tool, reused as-is) and parses element lines.
function Invoke-S8Uia([string]$Filter) {
    $output = & $uiaExe $Filter 2>&1 | Out-String
    $elements = @()
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -like 'element *') { $elements += , (ConvertFrom-S8UiaLine $line) }
    }
    @{ raw = $output.Trim(); elements = $elements; exitCode = $LASTEXITCODE }
}

# Elements whose Name begins with the display name or whose AutomationId is
# the pin's (localized suffixes on Name are informative, never load-bearing).
function Get-S8Buttons {
    $dump = Invoke-S8Uia $s8Name
    @($dump.elements | Where-Object { $_.name -like "$s8Name*" -or (Test-S8IsPinId $_.automationId) })
}

function Wait-S8ButtonCount([int]$Count, [string]$What, [int]$TimeoutSec = 30) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Info "  [auto] polling UIA up to ${TimeoutSec}s for $What..."
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $btns = @(Get-S8Buttons)   # @() at the call site: a single element unrolls to a bare hashtable whose .Count is its KEY count
        if ($btns.Count -eq $Count) {
            Good ("  [auto] reached {0} matching element(s) after {1:n1}s" -f $Count, $sw.Elapsed.TotalSeconds)
            return @{ detected = $true; afterSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); buttons = $btns }
        }
        Start-Sleep -Milliseconds 500
    }
    $btns = @(Get-S8Buttons)
    Bad "  [auto] TIMEOUT: $($btns.Count) matching element(s) after ${TimeoutSec}s (wanted $Count)"
    @{ detected = $false; buttons = $btns }
}

# The equivalence comparison: identity + state properties only. rect is
# excluded on purpose — buttons legitimately shift when the bar re-lays out.
$s8CompareKeys = 'name', 'automationId', 'className', 'controlType', 'state', 'offscreen'
function Compare-S8Element([hashtable]$Baseline, [hashtable]$Current) {
    $changed = @()
    foreach ($k in $s8CompareKeys) {
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

# Runs one s8pin.exe route; the exe writes its facts to an outfile (UTF-8,
# authoritative — GUI-subsystem console capture can mojibake non-ASCII).
function Invoke-S8Pin([string]$Aumid, [string]$Command) {
    New-Item -ItemType Directory -Force $s8OutDir | Out-Null
    $outFile = Join-Path $s8OutDir ("s8pin-{0}-{1:yyyyMMdd-HHmmssfff}.txt" -f $Command, (Get-Date))
    Info ("  [auto] running: s8pin.exe `"{0}`" {1}" -f $Aumid, $Command)
    $stdout = & $pinExe $Aumid $Command $outFile 2>&1 | Out-String
    $code = $LASTEXITCODE
    $lines = (Test-Path $outFile) ? @(Get-Content $outFile) : @($stdout -split "`r?`n")
    $facts = ConvertFrom-S8PinOutput $lines
    foreach ($k in @($facts.Keys)) { Write-Host ("      {0} = {1}" -f $k, $facts[$k]) }
    if ($facts.Count -eq 0) { Bad '  [auto] no facts parsed from s8pin output' }
    @{ exitCode = $code; facts = $facts; outFile = (Split-Path $outFile -Leaf) }
}

# ---------- preflight ----------------------------------------------------------

Info '=== S-8 guided protocol runner ==='
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
$postKb = ([int]$cv.CurrentBuildNumber -gt 26200) -or
          (([int]$cv.CurrentBuildNumber -in 26100, 26200) -and ([int]$cv.UBR -ge 7705))
Info "[auto] environment: $($cv.ProductName) $($cv.DisplayVersion) build $build edition $($cv.EditionID)"
Info "[auto] servicing: KB5074105 LAF-removal $(($postKb) ? 'EXPECTED PRESENT (UBR >= 7705)' : 'expected ABSENT - LAF token path applies')"

if (-not (Test-Path $pinExe)) {
    Info '[auto] s8pin.exe missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S8Binaries.ps1')
}
if (-not (Test-Path $uiaExe)) {
    Info '[auto] s9uia.exe missing - building via the S-9 build script...'
    & (Join-Path $PSScriptRoot '..\s9-uiaoracle\Build-S9Binaries.ps1')
}

# Hygiene sweep (S-9's failed-run-recovery reference implementation):
# enumerate the pin folder, read each copy's AUMID, flag PinnedLauncher.Test.*
# leftovers, unpin programmatically - Start source if it exists, else the
# pinned copy itself.
Info '[auto] hygiene sweep: reading the AUMID of every pinned copy...'
$sweep = @()
foreach ($lnk in (Get-ChildItem $s8PinDir -Filter *.lnk -ErrorAction SilentlyContinue)) {
    $aumid = Read-S8LnkAumid $lnk.FullName
    if ($aumid -like 'PinnedLauncher.Test.*') {
        Bad "  [auto] leftover found: '$($lnk.Name)' AUMID=$aumid"
        $entry = [ordered]@{ lnk = $lnk.Name; aumid = $aumid; unpinForm = $null; unpin = $null }
        if (Test-Path $s4unpin) {
            $source = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter $lnk.Name -ErrorAction SilentlyContinue |
                      Where-Object { (Read-S8LnkAumid $_.FullName) -ceq $aumid } | Select-Object -First 1
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
Record 'sweep' 'Preflight hygiene sweep' @{ leftovers = $sweep; pinCount = @(Get-ChildItem $s8PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Count }

Info '[auto] (re)generating the test article...'
& (Join-Path $PSScriptRoot 'New-S8Shortcuts.ps1')

Record 'env' 'Environment and baseline' @{
    build = $build; edition = $cv.EditionID; displayVersion = $cv.DisplayVersion
    postKb5074105Expected = $postKb
    baselineFolder = @((Get-ChildItem $s8PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Name)
}

try {

# ---------- Part 0 (Q2): windowless probes ------------------------------------

Info "`n--- Part 0 (Q2): support + LAF/servicing probes (windowless, no pin request) ---"
$probe = Invoke-S8Pin $s8Aumid 'probe'
$pf = $probe.facts
if ($pf.desktopSupport -eq 'true') { Good '  [auto] ITaskbarManagerDesktopAppSupportStatics marker PRESENT - desktop-app support available' }
else { Bad '  [auto] desktop-app support marker ABSENT - the API is unusable from our unpackaged exe' }
if ($pf.isPinningAllowed) { Info "  [auto] IsSupported=$($pf.isSupported) IsPinningAllowed=$($pf.isPinningAllowed)" }
$lafConsistent = ($pf.lafTokenRequired -eq ($postKb ? 'false' : 'true'))
if ($lafConsistent) { Good "  [auto] LAF registry probe AGREES with the servicing level (tokenRequired=$($pf.lafTokenRequired))" }
else { Bad "  [auto] LAF registry probe DISAGREES with the servicing level (tokenRequired=$($pf.lafTokenRequired), postKb=$postKb)" }
Record 'Q2-probe' 'Q2: support + LAF/servicing probes' @{
    run = $probe; lafProbeConsistentWithServicing = $lafConsistent
}

# ---------- Part 1 (Q1 route A): RequestPinCurrentAppAsync --------------------

Info "`n--- Part 1 (Q1 route A): current-app request under the article's AUMID ---"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$indexed = $false
Info '[auto] waiting up to 120s for the shell to index the new AUMID in shell:AppsFolder... (press ''s'' to skip)'
while ($sw.Elapsed.TotalSeconds -lt 120) {
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.KeyChar -eq 's') { Bad '  [auto] wait skipped by user'; break }
    }
    $apps = (New-Object -ComObject Shell.Application).Namespace('shell:AppsFolder')
    if ($null -ne $apps.ParseName($s8Aumid)) { $indexed = $true; break }
    Start-Sleep -Seconds 1
}
$indexLatency = [math]::Round($sw.Elapsed.TotalSeconds, 1)
if ($indexed) { Good "  [auto] AUMID indexed after ${indexLatency}s" }
else          { Bad  "  [auto] AUMID still not indexed after ${indexLatency}s - the request may be denied for lack of a Start entry" }

Info 'WHAT TO WATCH: a small ''S8 pin host'' window opens; then a CONSENT DIALOG should appear asking to pin the app. Note the NAME and ICON the dialog shows.'
Action "When the dialog appears, answer YES (Sì). If the host window does not come to the foreground by itself, click it once."
$pinRun = Invoke-S8Pin $s8Aumid 'pin-current'
$dialogAppeared = AskYN 'Did a consent dialog appear?'
$dialogName = Ask "What NAME did the dialog show? (expected '$s8Name'; Enter to skip)"
$dialogIcon = AskYN "Did the dialog show the TARGET'S icon (charmap's)?"
Record 'Q1A-pin-current' 'Q1 route A: RequestPinCurrentAppAsync' @{
    appsFolderIndexed = $indexed; indexLatencySeconds = $indexLatency
    run = $pinRun
    dialogAppeared = $dialogAppeared; dialogName = $dialogName; dialogShowedTargetIcon = $dialogIcon
}

# ---------- Part 2 (Q3): equivalence with a gesture pin -----------------------

$pinLanded = ($pinRun.facts.requestPinCurrentApp -eq 'true') -or (Test-Path (Join-Path $s8PinDir $s8LnkName))
$baseline = $null
if ($pinLanded) {
    Info "`n--- Part 2 (Q3): is the API pin equivalent to a gesture pin? ---"
    # Signal 1 (S-4): the pinned copy in User Pinned\TaskBar, with the AUMID retained.
    $wait = Wait-PinEvent $s8LnkName Appear -TimeoutSec 15
    $copyPath = Join-Path $s8PinDir $s8LnkName
    $copyAumid = (Test-Path $copyPath) ? (Read-S8LnkAumid $copyPath) : $null
    if ($copyAumid -ceq $s8Aumid) { Good "  [auto] S-4 SIGNAL HOLDS: pinned copy exists and retains AUMID '$copyAumid'" }
    else { Bad "  [auto] S-4 signal differs: pinned copy AUMID='$copyAumid' (wanted '$s8Aumid')" }
    Record 'Q3-pinfolder' 'Q3: S-4 pin-folder signal' @{ wait = $wait; copyAumid = $copyAumid; aumidMatches = ($copyAumid -ceq $s8Aumid) }

    # Signal 2 (S-9): the UIA oracle - AutomationId "Appid: <AUMID>", same element shape.
    $found = Wait-S8ButtonCount 1 'the pin button to appear in the UIA tree'
    $baseline = $found.buttons | Select-Object -First 1
    if ($baseline) {
        Info ("  [auto] pin element: name='{0}' automationId='{1}' className='{2}' controlType={3} state={4} offscreen={5}" -f `
            $baseline.name, $baseline.automationId, $baseline.className, $baseline.controlType, $baseline.state, $baseline.offscreen)
        $idOk = Test-S8IsPinId $baseline.automationId
        $shapeOk = ($baseline.className -ceq 'Taskbar.TaskListButtonAutomationPeer') -and ($baseline.controlType -eq '50000')
        if ($idOk)    { Good "  [auto] S-9 ORACLE HOLDS: AutomationId carries our AUMID ('$($baseline.automationId)')" }
        else          { Bad  "  [auto] S-9 oracle differs: AutomationId='$($baseline.automationId)'" }
        if ($shapeOk) { Good '  [auto] element shape matches the S-9 gesture-pin baseline (class + control type)' }
        else          { Bad  '  [auto] element shape DIFFERS from the S-9 gesture-pin baseline' }
    }
    else { Bad '  [auto] pin button NOT found in the UIA tree' }
    $visual1 = AskYN "Visual check: exactly ONE '$s8Name' button on the taskbar?"
    Record 'Q3-uia' 'Q3: S-9 UIA oracle on the API pin' @{
        wait = $found; element = $baseline
        aumidIsAutomationId = ($baseline -and (Test-S8IsPinId $baseline.automationId))
        visualOneButton = $visual1
    }

    # Click equivalence: launching from the API pin behaves like S-3's gesture pin.
    Info 'WHAT TO WATCH: after you click the pin, Character Map must open as its OWN separate button - the pin must NOT expand in place.'
    Action "Click the '$s8Name' pin ONCE."
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    $charmapProc = $null
    while ($sw2.Elapsed.TotalSeconds -lt 30 -and -not $charmapProc) {
        $charmapProc = Get-Process -Name charmap -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $charmapProc) { Start-Sleep -Milliseconds 250 }
    }
    $launched = [bool]$charmapProc
    if ($launched) { Good ("  [auto] charmap launched ({0:n1}s after watch start)" -f $sw2.Elapsed.TotalSeconds) }
    else { Bad '  [auto] charmap not seen within 30s' }
    $pinDuring = $null; $changedDuring = @('n/a')
    if ($baseline) {
        $pinDuring = @(Get-S8Buttons) | Where-Object { Test-S8IsPinId $_.automationId } | Select-Object -First 1
        if ($pinDuring) {
            $changedDuring = @(Compare-S8Element $baseline $pinDuring)
            if ($changedDuring.Count -eq 0) { Good '  [auto] pin element unchanged while the target runs (F-2 invariant on the API pin)' }
            else { Bad ("  [auto] pin element CHANGED: " + ($changedDuring -join '; ')) }
        }
    }
    $visual2 = AskYN 'Visual check: did Character Map open as its OWN button, pin unchanged?'
    if ($charmapProc) {
        Info '[auto] closing Character Map gracefully...'
        [void]$charmapProc.CloseMainWindow()
    }
    Record 'Q3-click' 'Q3: click equivalence (launch from the API pin)' @{
        charmapLaunched = $launched; pinElementDuring = $pinDuring
        pinChangedDuringRun = $changedDuring; visualSeparateButton = $visual2
    }

    # Repeat request: documented behavior is immediate true, no dialog.
    Info "`n[auto] repeat request - documented behavior: returns true immediately, no dialog."
    Info 'WHAT TO WATCH: whether ANY dialog appears this time (none is expected).'
    $repeatRun = Invoke-S8Pin $s8Aumid 'pin-current'
    $repeatDialog = AskYN 'Did a dialog appear on the repeat request?'
    Record 'Q1A-repeat' 'Q1 route A: repeat request on an existing pin' @{
        run = $repeatRun; dialogAppeared = $repeatDialog
    }

    # Teardown: S-4's programmatic unpin works on the API-created pin too?
    Info "`n[auto] teardown: programmatic unpin of the API-created pin (S-4 RemoveFromList)..."
    if (Test-Path $s4unpin) {
        $tool = Invoke-Tool $s4unpin @($startLnk)
        $wait = Wait-PinEvent $s8LnkName Disappear -TimeoutSec 10
        if (-not $wait.detected) {
            Action "Programmatic unpin did not land - right-click the '$s8Name' pin -> Rimuovi dalla barra delle applicazioni."
            $wait = Wait-PinEvent $s8LnkName Disappear
        }
        $uiaGone = Wait-S8ButtonCount 0 'the pin button to leave the UIA tree'
        Record 'Q3-teardown' 'Q3: programmatic unpin of the API pin' @{ tool = $tool; wait = $wait; uiaGone = $uiaGone.detected }
    }
    else {
        Action "s4unpin.exe not built - right-click the '$s8Name' pin and unpin it."
        Record 'Q3-teardown' 'Q3: teardown (gesture fallback)' @{ wait = (Wait-PinEvent $s8LnkName Disappear) }
    }
}
else {
    Bad "`n[auto] no pin landed from route A - skipping the Q3 equivalence part (that outcome is itself the datum)"
    Record 'Q3-skipped' 'Q3: skipped - no pin landed' @{ }
}

# ---------- Part 3 (Q1 route B): RequestPinAppListEntryAsync ------------------

Info "`n--- Part 3 (Q1 route B): AppListEntry acquisition + request ---"
Info '[auto] B1: our own unpackaged AUMID (expected: no documented AppListEntry acquisition path)...'
$ownEntry = Invoke-S8Pin $s8Aumid 'pin-entry'
Record 'Q1B-own-entry' 'Q1 route B: AppListEntry for our unpackaged AUMID' @{ run = $ownEntry }

$apps = (New-Object -ComObject Shell.Application).Namespace('shell:AppsFolder')
$ctrlAumid = $s8ControlCandidates | Where-Object { $null -ne $apps.ParseName($_) } | Select-Object -First 1
if ($ctrlAumid) {
    Info "[auto] B2: packaged CONTROL entry '$ctrlAumid' - proves whether the route works at all from our unpackaged caller."
    Info 'WHAT TO WATCH: a consent dialog for the control app may appear.'
    Action "If a dialog appears, answer NO (we only need to see it reach the consent stage - answering No leaves no pin to clean up)."
    $ctrlEntry = Invoke-S8Pin $ctrlAumid 'pin-entry'
    $ctrlDialog = AskYN 'Did a consent dialog appear for the control app?'
    $ctrlCleanup = $null
    if ($ctrlEntry.facts.requestPinAppListEntry -eq 'true') {
        Action "The control app got pinned (Yes was answered) - right-click its taskbar button and unpin it."
        $ctrlCleanup = AskYN 'Control app unpinned again?'
    }
    Record 'Q1B-control-entry' 'Q1 route B: AppListEntry for a packaged control AUMID' @{
        controlAumid = $ctrlAumid; run = $ctrlEntry
        dialogAppeared = $ctrlDialog; cleanupConfirmed = $ctrlCleanup
    }
}
else {
    Bad '  [auto] no control candidate indexed in shell:AppsFolder - route B control skipped'
    Record 'Q1B-control-entry' 'Q1 route B: control skipped - no candidate' @{ candidates = $s8ControlCandidates }
}

# ---------- Part 4 (Q1 route C): secondary tiles ------------------------------

Info "`n--- Part 4 (Q1 route C): secondary-tile pin/status/unpin from an unpackaged caller ---"
Info 'WHAT TO WATCH: probably nothing visible (expected to fail without package identity). If a dialog appears, answer NO.'
$tileRun = Invoke-S8Pin $s8Aumid 'pin-tile'
Record 'Q1C-tile' 'Q1 route C: SecondaryTile attempts' @{ run = $tileRun }

# ---------- close-out ---------------------------------------------------------

$late = Ask 'Anything unexpected at ANY point? (Enter for no, else notes)'
Record 'late-observations' 'Late / unexpected observations' @{ notes = $late }
Info "[auto] Start-menu folder and out\ left in place for re-runs; remove per protocol SS5.6 when the spike is closed."

}
finally {
    if ($script:steps.Count -gt 0) {
        $resultsDir = Join-Path $PSScriptRoot 'results'
        New-Item -ItemType Directory -Force $resultsDir | Out-Null
        $resultsPath = Join-Path $resultsDir ("s8-run-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        @{ run = 's8-pinapi'; started = $script:steps[0].at; machineBuild = $build; steps = $script:steps } |
            ConvertTo-Json -Depth 8 | Set-Content $resultsPath -Encoding utf8
        Good "`nResults written to: $resultsPath"
        Good 'Tell Claude the run is complete - the JSON will be transcribed into docs/spikes/s8-pinapi.md.'
    }
}
