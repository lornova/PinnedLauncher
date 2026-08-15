#Requires -Version 7
<#
PinnedLauncher spike S-4 (throwaway): guided protocol runner.

Automates everything automatable (pin-folder watching with timestamps, Taskband
blob checks, probe tools, branching) and pauses with ONE clear action whenever a
human gesture is required. Every automated measurement and every answer is
recorded to results\s4-run-<timestamp>.json for transcription into
docs/spikes/s4-pinflow.md.

Type 'skip' at any prompt to skip that step (recorded as skipped).
Ctrl+C aborts; partial results are still written.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# ---------- infrastructure ----------------------------------------------------

$pinDir   = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$startDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S4 Spike'
$outDir   = Join-Path $PSScriptRoot 'out'
$binDir   = Join-Path $PSScriptRoot 'bin'
$lnk1     = 'S4-1 pin test.lnk'
$lnk2     = 'S4-2 pin test.lnk'

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
    $path = Join-Path $pinDir $Name
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

# Extracts .lnk names from the Taskband Favorites registry blob.
function Get-BlobLnkNames {
    $tb = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -ErrorAction SilentlyContinue
    if (-not $tb -or -not $tb.Favorites) { return @() }
    $bytes = $tb.Favorites
    $found = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($offset in 0, 1) {
        $text = [System.Text.Encoding]::Unicode.GetString($bytes[$offset..($bytes.Length - 1)])
        foreach ($m in [regex]::Matches($text, '[\w \-\.\(\)]{3,}\.lnk')) { [void]$found.Add($m.Value) }
    }
    return @($found)
}

function Get-Signals([string]$Name) {
    $inFolder = Test-Path (Join-Path $pinDir $Name)
    $inBlob = (Get-BlobLnkNames) -contains $Name
    Info ("  [auto] signals for '{0}': pin-folder={1}  taskband-blob={2}" -f $Name, $inFolder, $inBlob)
    return @{ pinFolder = $inFolder; taskbandBlob = $inBlob }
}

function Invoke-Tool([string]$Exe, [string]$Argument) {
    Info "  [auto] running: $Exe `"$Argument`""
    $output = & $Exe $Argument 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host ($output.TrimEnd() -replace '(?m)^', '      ')
    return @{ exitCode = $code; output = $output.Trim() }
}

# ---------- preflight (all automatic) ----------------------------------------

Info '=== S-4 guided protocol runner ==='
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
Info "[auto] environment: $($cv.ProductName) $($cv.DisplayVersion) build $build edition $($cv.EditionID)"

foreach ($exe in 's4unpin.exe', 's4select.exe') {
    if (-not (Test-Path (Join-Path $binDir $exe))) { Info '[auto] binaries missing - building...'; & (Join-Path $PSScriptRoot 'Build-S4Binaries.ps1'); break }
}
if (-not (Test-Path (Join-Path $outDir $lnk1)) -or -not (Test-Path (Join-Path $startDir $lnk1))) {
    Info '[auto] shortcuts missing - generating...'
    & (Join-Path $PSScriptRoot 'New-S4Shortcuts.ps1')
}

foreach ($leftover in $lnk1, $lnk2) {
    if (Test-Path (Join-Path $pinDir $leftover)) {
        Action "leftover pin '$leftover' from an earlier run - right-click it on the taskbar and unpin it."
        [void](Wait-PinEvent $leftover Disappear)
    }
}

Record 'env' 'Environment and baseline' @{
    build = $build; edition = $cv.EditionID; displayVersion = $cv.DisplayVersion
    baselineFolder = @((Get-ChildItem $pinDir -Filter *.lnk -ErrorAction SilentlyContinue).Name)
    baselineBlob = @(Get-BlobLnkNames)
}

# ---------- Part 1: Route A (Start menu) -------------------------------------

Info "`n--- Part 1: Route A - pin from Start ---"
Action "Open Start -> Tutto -> 'PinnedLauncher S4 Spike' -> right-click 'S4-1 pin test' -> Aggiungi alla barra delle applicazioni. WHILE DOING IT: count the clicks/keystrokes from opening Start to pinned. (I'm watching - no need to hurry back.)"
$wait = Wait-PinEvent $lnk1 Appear
$signals = Get-Signals $lnk1
$clicks = Ask 'You were counting - how many clicks/keystrokes? (number or notes)'
$visible = AskYN 'Is the S4-1 pin (charmap icon) visible on the taskbar?'
Record 'RA-pin' 'Route A pin (Start)' @{ wait = $wait; signals = $signals; clicks = $clicks; pinVisible = $visible }

Action "Right-click the S4-1 pin -> Rimuovi dalla barra delle applicazioni."
$wait = Wait-PinEvent $lnk1 Disappear
$signals = Get-Signals $lnk1
Record 'RA-unpin' 'Route A unpin' @{ wait = $wait; signals = $signals }

# ---------- Part 2: Route B (Explorer context menu) --------------------------

Info "`n--- Part 2: Route B - pin from Explorer ---"
Info '[auto] opening Explorer with the shortcut selected...'
Start-Process explorer.exe "/select,`"$(Join-Path $outDir $lnk1)`""
Action "In the Explorer window that just opened: right-click 'S4-1 pin test.lnk' -> Aggiungi alla barra delle applicazioni. WHILE DOING IT: note whether the option is in the first menu you see, only under 'Mostra altre opzioni', or missing."
$wait = Wait-PinEvent $lnk1 Appear
$signals = Get-Signals $lnk1
$menu = Ask "Where was the pin option? (modern/legacy/missing + notes)"
Record 'RB-pin' 'Route B pin (Explorer)' @{ wait = $wait; signals = $signals; menuLocation = $menu }

Action "Right-click the S4-1 pin -> Rimuovi dalla barra delle applicazioni."
$wait = Wait-PinEvent $lnk1 Disappear
Record 'RB-unpin' 'Route B unpin' @{ wait = $wait; signals = (Get-Signals $lnk1) }

# ---------- Part 3: Route C (deep-link probe) --------------------------------

Info "`n--- Part 3: Route C - deep-link probe (s4select) ---"
$tool = Invoke-Tool (Join-Path $binDir 's4select.exe') 'PinnedLauncher.S4.PinTest1'
$opened = Ask "What opened? (a=Apps view with 'S4-1 pin test' SELECTED, b=a view but NOT selected, c=nothing/error + notes)"
$answer = @{ tool = $tool; opened = $opened }
if ($opened -match '^[ab]') {
    $pinOption = AskYN "Right-click the 'S4-1 pin test' entry in that view: does the menu offer 'Aggiungi alla barra delle applicazioni'?"
    $answer.pinOptionOffered = $pinOption
    if ($pinOption -eq 'y') {
        Action 'Pin it from that menu now.'
        $answer.wait = Wait-PinEvent $lnk1 Appear
        $answer.signals = Get-Signals $lnk1
        Action "Right-click the S4-1 pin -> Rimuovi dalla barra delle applicazioni."
        [void](Wait-PinEvent $lnk1 Disappear)
    }
}
Record 'RC-deeplink' 'Route C deep-link (AppsFolder)' $answer

$tool = Invoke-Tool (Join-Path $binDir 's4select.exe') (Join-Path $outDir $lnk1)
$openedFs = Ask 'Filesystem variant: what opened, and is the .lnk file selected? (notes)'
Record 'RC-fs' 'Route C deep-link (filesystem)' @{ tool = $tool; opened = $openedFs }

# ---------- Part 4: Route D (drag to taskbar) --------------------------------

Info "`n--- Part 4: Route D - drag to taskbar ---"
Action "From the Explorer window, slowly drag 'S4-1 pin test.lnk' onto an EMPTY area of the taskbar. Note what the cursor/tooltip shows; drop if it lets you. Press Enter here afterwards."
[void](Read-Host '  (Enter when done)')
Start-Sleep -Seconds 2
$pinned = Test-Path (Join-Path $pinDir $lnk1)
Info "  [auto] pin-folder now contains S4-1: $pinned"
$dragNotes = Ask 'What happened? (affordance shown / blocked cursor / pinned / notes)'
if ($pinned) {
    Action "It pinned - right-click the S4-1 pin -> Rimuovi dalla barra delle applicazioni."
    [void](Wait-PinEvent $lnk1 Disappear)
}
Record 'RD-drag' 'Route D drag to taskbar' @{ resultedInPin = $pinned; notes = $dragNotes }

# ---------- Part 5: programmatic unpin (Q3) ----------------------------------

Info "`n--- Part 5: programmatic unpin (RemoveFromList) ---"
Action "Pin BOTH entries via Start: Start -> Tutto -> 'PinnedLauncher S4 Spike' -> pin 'S4-1 pin test', then 'S4-2 pin test'."
$w1 = Wait-PinEvent $lnk1 Appear
$w2 = Wait-PinEvent $lnk2 Appear
Record 'Q3-setup' 'Both S4 pins placed' @{ wait1 = $w1; wait2 = $w2 }

$pathForms = [ordered]@{
    'start-menu source' = Join-Path $startDir $lnk1
    'user-pinned copy'  = Join-Path $pinDir $lnk1
    'out original'      = Join-Path $outDir $lnk1
}
$successfulForm = $null
foreach ($form in $pathForms.Keys) {
    Info "`n[auto] RemoveFromList attempt - path form: $form"
    $tool = Invoke-Tool (Join-Path $binDir 's4unpin.exe') $pathForms[$form]
    $wait = Wait-PinEvent $lnk1 Disappear -TimeoutSec 10
    $signals1 = Get-Signals $lnk1
    $signals2 = Get-Signals $lnk2
    $gone = AskYN 'Is the S4-1 button GONE from the taskbar?'
    $iso = AskYN 'Are S4-2 and all your own pins (Claude, Chrome, Explorer, RDC) untouched?'
    Record "Q3-$($form -replace ' ','-')" "RemoveFromList via $form" @{
        tool = $tool; wait = $wait; s41 = $signals1; s42 = $signals2; buttonGone = $gone; isolationHeld = $iso
    }
    if ($gone -eq 'y') { $successfulForm = $form; break }
    Info '[auto] not unpinned - trying next path form...'
}

if ($successfulForm) {
    Info "`n[auto] stability repeat with the successful form: $successfulForm"
    Action "Re-pin 'S4-1 pin test' via Start once more."
    [void](Wait-PinEvent $lnk1 Appear)
    $tool = Invoke-Tool (Join-Path $binDir 's4unpin.exe') $pathForms[$successfulForm]
    $wait = Wait-PinEvent $lnk1 Disappear -TimeoutSec 10
    $gone = AskYN 'Gone from the taskbar again?'
    Record 'Q3-repeat' 'RemoveFromList stability repeat' @{ form = $successfulForm; tool = $tool; wait = $wait; buttonGone = $gone }

    $restart = AskYN 'Explorer-restart check: OK to restart Explorer now? (open Explorer windows will close)'
    if ($restart -eq 'y') {
        Info '[auto] restarting Explorer...'
        taskkill /f /im explorer.exe | Out-Null
        Start-Process explorer.exe
        Start-Sleep -Seconds 6
        $signals1 = Get-Signals $lnk1
        $signals2 = Get-Signals $lnk2
        $visual = Ask 'After the desktop returned: S4-1 still absent and S4-2 still pinned? (y/n + notes)'
        Record 'Q3-explorer-restart' 'Explorer restart persistence' @{ s41 = $signals1; s42 = $signals2; visual = $visual }
    }
    else { Record 'Q3-explorer-restart' 'Explorer restart persistence' @{ skipped = $true } }
}
else {
    Bad '[auto] RemoveFromList did not unpin via any path form - recorded; UC-3 falls back to guided gesture.'
}

# ---------- wrap-up -----------------------------------------------------------

Action "Cleanup: right-click the S4-2 pin -> Rimuovi dalla barra delle applicazioni."
[void](Wait-PinEvent $lnk2 Disappear)

$resultsDir = Join-Path $PSScriptRoot 'results'
New-Item -ItemType Directory -Force $resultsDir | Out-Null
$resultsPath = Join-Path $resultsDir ("s4-run-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
@{ run = 's4-pinflow'; started = $script:steps[0].at; machineBuild = $build; steps = $script:steps } |
    ConvertTo-Json -Depth 8 | Set-Content $resultsPath -Encoding utf8
Good "`nDone. Results written to: $resultsPath"
Good 'Tell Claude the run is complete - the JSON will be transcribed into docs/spikes/s4-pinflow.md.'
