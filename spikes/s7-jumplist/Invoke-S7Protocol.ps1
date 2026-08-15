#Requires -Version 7
<#
PinnedLauncher spike S-7 (throwaway): guided protocol runner.

Automates everything automatable (builds, article generation with gate G0,
every ICustomDestinationList call, the AppsFolder indexing poll, pin-folder
waits, the no-process check, log polling with automatic expectation checks)
and pauses with ONE clear instruction whenever a human gesture or
observation is needed. Before every observable step it says WHAT TO WATCH,
then acts, then collects the answer. Every measurement and answer lands in
results\s7-run-<timestamp>.json for transcription into
docs/spikes/s7-jumplist.md.

Press 's' during any [auto] wait if the requested action turns out to be
impossible (recorded as skipped). Ctrl+C aborts; partial results are still
written.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S7Common.ps1')

# ---------- infrastructure ----------------------------------------------------

$jumplistExe = Join-Path $s7BinDir 's7jumplist.exe'
$taskEchoExe = Join-Path $s7BinDir 's7taskecho.exe'
$startLnk    = Join-Path $s7StartDir $s7LnkName

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
    $path = Join-Path $s7PinDir $Name
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

function Wait-S7LogAppend([string]$Path, [int]$Baseline, [string]$What, [int]$TimeoutSec = 60) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Info "  [auto] waiting up to ${TimeoutSec}s for $What... (press 's' if it cannot happen - skips this wait)"
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ([console]::KeyAvailable) {
            $key = [console]::ReadKey($true)
            if ($key.KeyChar -eq 's') {
                Bad "  [auto] wait skipped by user"
                return @{ detected = $false; skipped = $true }
            }
        }
        $lines = @(Get-S7LogLines $Path)
        if ($lines.Count -gt $Baseline) {
            $sw.Stop()
            $line = $lines[-1]
            Good ("  [auto] log line ({0:n1}s): {1}" -f $sw.Elapsed.TotalSeconds, $line)
            return @{
                detected     = $true
                afterSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
                line         = $line
                parsed       = (ConvertFrom-S7LogLine $line)
            }
        }
        Start-Sleep -Milliseconds 200
    }
    Bad "  [auto] TIMEOUT: no new line in $(Split-Path $Path -Leaf) within ${TimeoutSec}s"
    return @{ detected = $false }
}

function Test-S7Expect([hashtable]$Wait, [hashtable]$Expected, [string]$Label) {
    if (-not $Wait.detected) { Bad "  [auto] $Label - no log line to check"; return $false }
    $fails = @()
    foreach ($k in $Expected.Keys) {
        if ($Wait.parsed[$k] -ne $Expected[$k]) {
            $fails += "$k=$($Wait.parsed[$k]) (expected $($Expected[$k]))"
        }
    }
    if ($fails) { Bad ("  [auto] $Label MISMATCH: " + ($fails -join ', ')); return $false }
    Good "  [auto] $Label matches expectations"
    return $true
}

function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    Info ("  [auto] running: {0} {1}" -f $Exe, (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '))
    $output = & $Exe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host ($output.TrimEnd() -replace '(?m)^', '      ')
    return @{ exitCode = $code; output = $output.Trim() }
}

# ---------- preflight (all automatic) ----------------------------------------

Info '=== S-7 guided protocol runner ==='
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
Info "[auto] environment: $($cv.ProductName) $($cv.DisplayVersion) build $build edition $($cv.EditionID)"

if (-not (Test-Path $jumplistExe) -or -not (Test-Path $taskEchoExe)) {
    Info '[auto] binaries missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S7Binaries.ps1')
}

if (Test-Path (Join-Path $s7PinDir $s7LnkName)) {
    Action "leftover pin '$s7LnkName' from an earlier run - right-click it on the taskbar and unpin it."
    [void](Wait-PinEvent $s7LnkName Disappear)
}

Info '[auto] (re)generating the test article...'
& (Join-Path $PSScriptRoot 'New-S7Shortcuts.ps1')

Record 'env' 'Environment and baseline' @{
    build = $build; edition = $cv.EditionID; displayVersion = $cv.DisplayVersion
    taskLogLines = @(Get-S7LogLines $s7TaskLog).Count
    baselineFolder = @((Get-ChildItem $s7PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Name)
}

try {

# ---------- Part 0: commit before pin, then pin --------------------------------

Info "`n--- Part 0: commit the task list BEFORE any pin exists (product creation order), then pin ---"

$commit1 = Invoke-Tool $jumplistExe @('commit', $s7Aumid, $taskEchoExe)
Record 'P0-commit' 'Initial task list committed (pre-pin)' @{ tool = $commit1 }
if ($commit1.exitCode -ne 0) { Bad '  [auto] commit FAILED - continuing to record what renders anyway' }

# S-6 finding: a freshly installed Start entry is not immediately parseable in
# shell:AppsFolder - poll before deep-linking, recording the latency.
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$indexed = $false
Info '[auto] waiting up to 120s for the shell to index the new AUMID in shell:AppsFolder... (press ''s'' to skip)'
while ($sw.Elapsed.TotalSeconds -lt 120) {
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.KeyChar -eq 's') { Bad '  [auto] wait skipped by user'; break }
    }
    $apps = (New-Object -ComObject Shell.Application).Namespace('shell:AppsFolder')
    if ($null -ne $apps.ParseName($s7Aumid)) { $indexed = $true; break }
    Start-Sleep -Seconds 1
}
$indexLatency = [math]::Round($sw.Elapsed.TotalSeconds, 1)
if ($indexed) { Good "  [auto] AUMID indexed after ${indexLatency}s" }
else          { Bad  "  [auto] AUMID still not indexed after ${indexLatency}s - falling back to the Start route" }

$s4select = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4select.exe'
if ($indexed -and (Test-Path $s4select)) {
    Info '[auto] opening the Apps view with the S7 entry pre-selected (the S-4-decided deep link)...'
    $tool = Invoke-Tool $s4select @($s7Aumid)
    Action "In the opened view, right-click the highlighted 'S7 jumplist test' -> Aggiungi alla barra delle applicazioni."
}
else {
    $tool = $null
    Action "Open Start -> Tutto -> right-click 'S7 jumplist test' (the single-entry spike folder is FLATTENED - the entry sits directly in the list) -> Aggiungi alla barra delle applicazioni."
}
$wait = Wait-PinEvent $s7LnkName Appear
Record 'P0-pin' 'Baseline pin placed' @{
    appsFolderIndexed = $indexed; indexLatencySeconds = $indexLatency
    deepLink = $tool; wait = $wait
}

# ---------- Part 1 (Q1): render with no process running ------------------------

Info "`n--- Part 1 (Q1): do the pre-pin-committed tasks render, with no process of ours running? ---"

$alive = @(Get-Process s7jumplist, s7taskecho -ErrorAction SilentlyContinue)
if ($alive.Count -eq 0) { Good '  [auto] no s7 process alive - the no-process premise holds' }
else { Bad ("  [auto] UNEXPECTED: s7 processes alive: " + (($alive | ForEach-Object ProcessName) -join ', ')) }

Info 'WHAT TO WATCH when the menu opens:'
Info '  1. a Tasks section (it-IT header: "Attivita''") listing: S7 Alpha task, S7 Beta task, a separator line, S7 Gamma task;'
Info '  2. the tasks sit ABOVE the system entries (the launcher''s own name, "Rimuovi dalla barra delle applicazioni");'
Info '  3. task icons (each task points at s7taskecho.exe - a generic icon is fine and expected).'
Action 'RIGHT-CLICK the S7 pin now and leave the menu open while you check.'
$tasksShown = AskYN 'Are the three tasks (Alpha, Beta, Gamma) listed?'
$sepShown   = AskYN 'Is there a separator line between Beta and Gamma?'
$aboveSys   = AskYN 'Are the tasks ABOVE the system entries?'
$header     = Ask 'What is the section header text, exactly? (Enter if none)'
Record 'Q1-render' 'Q1: render with no process running' @{
    aliveProcesses = $alive.Count; tasksShown = $tasksShown
    separatorShown = $sepShown; aboveSystemEntries = $aboveSys; header = $header
}

# ---------- Part 2 (Q2): task invocation ---------------------------------------

Info "`n--- Part 2 (Q2): a clicked task invokes our exe with its stored arguments ---"
$tb = @(Get-S7LogLines $s7TaskLog).Count
Info 'WHAT TO WATCH: nothing should flash (the echo target is windowless); the runner reads the log.'
Action "Open the S7 pin's jump list again and CLICK 'S7 Alpha task'."
$aWait = Wait-S7LogAppend $s7TaskLog $tb 'the task target to log its invocation'
[void](Test-S7Expect $aWait @{ exe = 's7taskecho'; args = 'alpha' } 'Q2 Alpha invocation')
$q2notes = Ask 'Anything visible when you clicked (flash, focus change)? (Enter for none)'
Record 'Q2-invoke' 'Q2: task invocation round-trip' @{ wait = $aWait; notes = $q2notes }

# ---------- Part 3 (Q3): update and delete -------------------------------------

Info "`n--- Part 3 (Q3): update on re-commit, then DeleteList ---"

$commit2 = Invoke-Tool $jumplistExe @('commit2', $s7Aumid, $taskEchoExe)
Info '[auto] edited list committed: expected menu now = "S7 Alpha task v2" + "S7 Gamma task" (Beta and the separator GONE).'
Action 'RIGHT-CLICK the S7 pin again and compare.'
$updShown = AskYN 'Does the menu now show exactly Alpha v2 + Gamma (no Beta, no separator)?'
$updNotes = Ask 'Any staleness (old entries still there, delay)? (Enter for none)'
Record 'Q3-update' 'Q3a: re-commit updates the menu' @{ tool = $commit2; updated = $updShown; notes = $updNotes }

$tb = @(Get-S7LogLines $s7TaskLog).Count
Action "In the same or a fresh jump list, CLICK 'S7 Alpha task v2'."
$a2Wait = Wait-S7LogAppend $s7TaskLog $tb 'the updated task to log its invocation'
[void](Test-S7Expect $a2Wait @{ exe = 's7taskecho'; args = 'alpha2' } 'Q3 Alpha-v2 invocation (updated args)')
Record 'Q3-invoke2' 'Q3a: updated task invocation' @{ wait = $a2Wait }

$del = Invoke-Tool $jumplistExe @('delete', $s7Aumid)
Info '[auto] DeleteList issued: expected menu now = system entries ONLY (no Tasks section).'
Action 'RIGHT-CLICK the S7 pin one more time.'
$gone = AskYN 'Is the Tasks section gone entirely (only the launcher name + unpin remain)?'
Record 'Q3-delete' 'Q3b: DeleteList removes the tasks' @{ tool = $del; tasksGone = $gone }

# ---------- wrap-up ------------------------------------------------------------

Info "`n--- Cleanup ---"
$late = Ask 'Before cleanup: anything unexpected at ANY point (stale menus, extra entries, wrong icons)? (Enter for no, else notes)'
Record 'late-observations' 'Late / unexpected observations' @{ notes = $late }

$s4unpin = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4unpin.exe'
if (Test-Path $s4unpin) {
    Info '[auto] unpinning via the S-4-validated RemoveFromList...'
    $tool = Invoke-Tool $s4unpin @($startLnk)
    $wait = Wait-PinEvent $s7LnkName Disappear -TimeoutSec 10
    if (-not $wait.detected) {
        Action 'Programmatic unpin did not land - right-click the S7 pin -> Rimuovi dalla barra delle applicazioni.'
        $wait = Wait-PinEvent $s7LnkName Disappear
    }
    Record 'cleanup-unpin' 'Unpin (programmatic, S-4 mechanism)' @{ tool = $tool; wait = $wait }
}
else {
    Action 'Right-click the S7 pin -> Rimuovi dalla barra delle applicazioni.'
    Record 'cleanup-unpin' 'Unpin (gesture)' @{ wait = (Wait-PinEvent $s7LnkName Disappear) }
}
Info "[auto] Start-menu folder and out\ left in place for re-runs; remove per protocol SS5.5 when the spike is closed."

}
finally {
    if ($script:steps.Count -gt 0) {
        $resultsDir = Join-Path $PSScriptRoot 'results'
        New-Item -ItemType Directory -Force $resultsDir | Out-Null
        $resultsPath = Join-Path $resultsDir ("s7-run-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        @{ run = 's7-jumplist'; started = $script:steps[0].at; machineBuild = $build; steps = $script:steps } |
            ConvertTo-Json -Depth 8 | Set-Content $resultsPath -Encoding utf8
        Good "`nResults written to: $resultsPath"
        Good 'Tell Claude the run is complete - the JSON will be transcribed into docs/spikes/s7-jumplist.md.'
    }
}
