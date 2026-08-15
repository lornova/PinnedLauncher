#Requires -Version 7
<#
PinnedLauncher spike S-6 (throwaway): guided protocol runner.

Automates everything automatable (builds, article generation with gate G0,
config swaps, pin-folder waits, log polling with automatic expectation
checks, the programmatic-RunAs guard scenario, the token matrix) and pauses
with ONE clear instruction whenever a human gesture or observation is
needed. Before every observable step it says WHAT TO WATCH, then acts, then
collects the answer. Every measurement and answer lands in
results\s6-run-<timestamp>.json for transcription into
docs/spikes/s6-elevation.md.

Press 's' during any [auto] wait if the requested action turns out to be
impossible (recorded as skipped). Ctrl+C aborts; partial results are still
written.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'S6Common.ps1')

# ---------- infrastructure ----------------------------------------------------

$proxyExe  = Join-Path $s6BinDir 's6proxy.exe'
$targetExe = Join-Path $s6BinDir 's6target.exe'
$startLnk  = Join-Path $s6StartDir $s6LnkName

$script:steps     = [System.Collections.Generic.List[object]]::new()
$script:tokenRows = [System.Collections.Generic.List[object]]::new()

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
    $path = Join-Path $s6PinDir $Name
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

# Polls a log file until a line beyond $Baseline appears. Returns the parsed
# last line. Timeout is generous: the line lands only after the UAC is answered.
function Wait-S6LogAppend([string]$Path, [int]$Baseline, [string]$What, [int]$TimeoutSec = 180) {
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
        $lines = @(Get-S6LogLines $Path)
        if ($lines.Count -gt $Baseline) {
            $sw.Stop()
            $line = $lines[-1]
            Good ("  [auto] log line ({0:n1}s): {1}" -f $sw.Elapsed.TotalSeconds, $line)
            return @{
                detected     = $true
                afterSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
                line         = $line
                parsed       = (ConvertFrom-S6LogLine $line)
            }
        }
        Start-Sleep -Milliseconds 200
    }
    Bad "  [auto] TIMEOUT: no new line in $(Split-Path $Path -Leaf) within ${TimeoutSec}s"
    return @{ detected = $false }
}

# Compares a parsed log line against expectations; prints PASS/MISMATCH.
function Test-S6Expect([hashtable]$Wait, [hashtable]$Expected, [string]$Label) {
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

function Add-TokenRow([string]$Scenario, [hashtable]$Wait) {
    if ($Wait.detected -and $Wait.parsed) {
        $p = $Wait.parsed
        $script:tokenRows.Add([ordered]@{
            scenario = $Scenario; exe = $p.exe; elevated = $p.elevated
            type = $p.type; integrity = $p.integrity; action = $p.action
        })
    }
}

function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    Info ("  [auto] running: {0} {1}" -f $Exe, (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '))
    $output = & $Exe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host ($output.TrimEnd() -replace '(?m)^', '      ')
    return @{ exitCode = $code; output = $output.Trim() }
}

# ---------- preflight (all automatic) ----------------------------------------

Info '=== S-6 guided protocol runner ==='
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
Info "[auto] environment: $($cv.ProductName) $($cv.DisplayVersion) build $build edition $($cv.EditionID)"

# The runner itself must be medium-IL: an elevated console would start every
# child elevated and make Part 1 meaningless.
$runnerElevated = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($runnerElevated) {
    throw 'This console is elevated. Re-run the protocol from a NORMAL (medium-IL) terminal.'
}

if (-not (Test-Path $proxyExe) -or -not (Test-Path $targetExe)) {
    Info '[auto] binaries missing - building...'
    & (Join-Path $PSScriptRoot 'Build-S6Binaries.ps1')
}

if (Test-Path (Join-Path $s6PinDir $s6LnkName)) {
    Action "leftover pin '$s6LnkName' from an earlier run - right-click it on the taskbar and unpin it."
    [void](Wait-PinEvent $s6LnkName Disappear)
}

Info '[auto] (re)generating the test article - resets the config to the s6target path...'
& (Join-Path $PSScriptRoot 'New-S6Shortcuts.ps1')

Record 'env' 'Environment and baseline' @{
    build = $build; edition = $cv.EditionID; displayVersion = $cv.DisplayVersion
    proxyLogLines = (Get-S6LogLines $s6ProxyLog).Count
    targetLogLines = (Get-S6LogLines $s6TargetLog).Count
    baselineFolder = @((Get-ChildItem $s6PinDir -Filter *.lnk -ErrorAction SilentlyContinue).Name)
}

try {

# ---------- Part 0: baseline pin ----------------------------------------------

Info "`n--- Part 0: pin the S6 entry (baseline) ---"

# A freshly installed Start-menu entry is NOT in shell:AppsFolder immediately
# (first-run evidence: SHParseDisplayName -> 0x80070002 seconds after install).
# Poll until the shell has indexed the AUMID and record the latency - the
# product's pin guide needs the same wait (feeds management-window SS5.3).
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$indexed = $false
Info '[auto] waiting up to 120s for the shell to index the new AUMID in shell:AppsFolder... (press ''s'' to skip)'
while ($sw.Elapsed.TotalSeconds -lt 120) {
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.KeyChar -eq 's') { Bad '  [auto] wait skipped by user'; break }
    }
    $apps = (New-Object -ComObject Shell.Application).Namespace('shell:AppsFolder')
    if ($null -ne $apps.ParseName($s6Aumid)) { $indexed = $true; break }
    Start-Sleep -Seconds 1
}
$indexLatency = [math]::Round($sw.Elapsed.TotalSeconds, 1)
if ($indexed) { Good "  [auto] AUMID indexed after ${indexLatency}s" }
else          { Bad  "  [auto] AUMID still not indexed after ${indexLatency}s - falling back to the Start route" }

$s4select = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4select.exe'
if ($indexed -and (Test-Path $s4select)) {
    Info '[auto] opening the Apps view with the S6 entry pre-selected (the S-4-decided deep link)...'
    $tool = Invoke-Tool $s4select @($s6Aumid)
    Action "In the opened view, right-click the highlighted 'S6 elevation test' -> Aggiungi alla barra delle applicazioni."
}
else {
    $tool = $null
    Action "Open Start -> Tutto -> right-click 'S6 elevation test' (S-5 note: the single-entry spike folder is FLATTENED - the entry sits directly in the list) -> Aggiungi alla barra delle applicazioni."
}
$wait = Wait-PinEvent $s6LnkName Appear
Record 'P0-pin' 'Baseline pin placed' @{
    appsFolderIndexed = $indexed; indexLatencySeconds = $indexLatency
    deepLink = $tool; wait = $wait
}

# ---------- Part 1 (Q1): supported elevated launch ----------------------------

Info "`n--- Part 1 (Q1): supported elevated launch - medium-IL proxy, runas on the target ---"

# --- S-A: launch + accept ---
Info "`n[S-A] plain click, ACCEPT the UAC."
Info 'WHAT TO WATCH, in order:'
Info '  1. the UAC dialog: the EXACT program name it shows (expected: s6target.exe, unknown publisher - NOT s6proxy);'
Info '  2. how many UAC prompts appear in total (expected: exactly ONE);'
Info '  3. the taskbar while the UAC is open: any NEW transient button (expected: none - the proxy is windowless).'
$pb = (Get-S6LogLines $s6ProxyLog).Count
$tb = (Get-S6LogLines $s6TargetLog).Count
Action 'Click the S6 pin ONCE, then accept the UAC prompt. Leave the target message box OPEN.'
$pWait = Wait-S6LogAppend $s6ProxyLog $pb 'the proxy to log its outcome (lands after the UAC is answered)'
$tWait = Wait-S6LogAppend $s6TargetLog $tb 'the elevated target to log its token' -TimeoutSec 60
[void](Test-S6Expect $pWait @{ exe = 's6proxy'; elevated = '0'; action = 'LAUNCHED' } 'S-A proxy')
[void](Test-S6Expect $tWait @{ exe = 's6target'; elevated = '1'; integrity = 'High'; action = 'RUNNING' } 'S-A target (the elevation oracle)')
Add-TokenRow 'S-A proxy'  $pWait
Add-TokenRow 'S-A target' $tWait
$uacName  = Ask 'What EXACT program name did the UAC dialog show?'
$prompts  = Ask 'How many UAC prompts appeared in total? (expected 1)'
$transient = AskYN 'Did any NEW taskbar button appear while the UAC was open?'
$ownBtn   = AskYN "Does the target's message box have its OWN taskbar button, separate from the S6 pin?"
Action 'Now press OK in the S6 target message box to let it exit.'
Record 'SA-launch' 'S-A: supported elevated launch, accepted' @{
    proxy = $pWait; target = $tWait; uacName = $uacName; promptCount = $prompts
    transientProxyButton = $transient; targetOwnButton = $ownBtn
}

# --- S-B: launch + cancel ---
Info "`n[S-B] plain click, CANCEL the UAC."
Info 'WHAT TO WATCH: after cancelling - any error dialog or other UI (expected: none), and the taskbar for leftovers.'
$pb = (Get-S6LogLines $s6ProxyLog).Count
Action 'Click the S6 pin ONCE, then press NO / Annulla on the UAC prompt.'
$pWait = Wait-S6LogAppend $s6ProxyLog $pb 'the proxy to log the cancellation'
[void](Test-S6Expect $pWait @{ exe = 's6proxy'; action = 'CANCELLED'; detail = '1223' } 'S-B proxy (ERROR_CANCELLED)')
Add-TokenRow 'S-B proxy' $pWait
$errUi  = AskYN 'Did ANY error dialog or other UI appear after cancelling?'
$linger = AskYN 'Is anything lingering on the taskbar besides the pin itself?'
Record 'SB-cancel' 'S-B: supported launch, UAC cancelled' @{ proxy = $pWait; errorUi = $errUi; lingering = $linger }

# --- S-C: signed-target naming ---
Info "`n[S-C] signed-OS-binary naming check (regedit.exe; it is CANCELLED, never launched)."
Set-S6ConfigTarget (Join-Path $env:windir 'regedit.exe')
Info '[auto] config now points at regedit.exe - a signed Windows binary.'
Info 'WHAT TO WATCH: the UAC dialog text - the display name it shows and the publisher line (expected: "Editor del Registro di sistema", editore verificato Microsoft Windows).'
$pb = (Get-S6LogLines $s6ProxyLog).Count
Action 'Click the S6 pin ONCE, READ the UAC dialog carefully, then CANCEL it.'
$pWait = Wait-S6LogAppend $s6ProxyLog $pb 'the proxy to log the cancellation'
[void](Test-S6Expect $pWait @{ exe = 's6proxy'; action = 'CANCELLED' } 'S-C proxy')
$scName = Ask 'What display name did the UAC show?'
$scPub  = Ask 'What did the publisher line say?'
Record 'SC-signed' 'S-C: signed-target UAC naming (cancelled)' @{ proxy = $pWait; uacName = $scName; publisher = $scPub }
Set-S6ConfigTarget $targetExe
Info '[auto] config restored to the s6target path.'

# ---------- Part 2 (Q2+Q3): elevated-start vectors + the guard -----------------

Info "`n--- Part 2 (Q2/Q3): elevated proxy starts - the confused-deputy guard ---"

# --- S-D: Ctrl+Shift+click ---
Info "`n[S-D] Ctrl+Shift+click - the shell elevates the PROXY: the exact vector the guard exists for."
Info 'WHAT TO WATCH, in order:'
Info '  1. the UAC dialog: it should now name s6proxy.exe (you are elevating the proxy, deliberately - accept it);'
Info '  2. after consent: the refusal message must appear and the S6 target must NOT start;'
Info '  3. the taskbar after closing the refusal: nothing left behind.'
$pb = (Get-S6LogLines $s6ProxyLog).Count
$tb = (Get-S6LogLines $s6TargetLog).Count
Action 'Hold Ctrl+Shift and CLICK the S6 pin. Accept the UAC prompt. Leave the refusal message open.'
$pWait = Wait-S6LogAppend $s6ProxyLog $pb 'the elevated proxy to log its verdict'
[void](Test-S6Expect $pWait @{ exe = 's6proxy'; elevated = '1'; action = 'REFUSED' } 'S-D guard')
Add-TokenRow 'S-D proxy' $pWait
if ((Get-S6LogLines $s6TargetLog).Count -eq $tb) { Good '  [auto] target log unchanged - config was NOT consumed' }
else { Bad '  [auto] target log GREW - the target was launched despite the guard!' }
$sdUac    = Ask 'What did the UAC name this time? (expected s6proxy.exe)'
$sdMsg    = AskYN 'Did the refusal message appear?'
$sdTarget = AskYN 'Did the S6 target start anyway?'
Action 'Close the refusal message.'
$sdLinger = AskYN 'Anything left on the taskbar besides the pin?'
Record 'SD-ctrlshift' 'S-D: Ctrl+Shift+click guard' @{
    proxy = $pWait; uacName = $sdUac; refusalShown = $sdMsg
    targetLaunched = $sdTarget; targetLogGrew = ((Get-S6LogLines $s6TargetLog).Count -ne $tb)
    lingering = $sdLinger
}

# --- S-E: jump-list context menu ---
Info "`n[S-E] the jump list's own run-as-administrator, if the shell offers it."
Action "Right-click the S6 pin; in the jump list, RIGHT-CLICK the entry named 'S6 elevation test'. Look for 'Esegui come amministratore'."
$offered = AskYN "Is 'Esegui come amministratore' offered in that context menu?"
if ($offered -eq 'y') {
    Info 'WHAT TO WATCH: same three points as S-D (UAC names the proxy; refusal appears; no target, no residue).'
    $pb = (Get-S6LogLines $s6ProxyLog).Count
    $tb = (Get-S6LogLines $s6TargetLog).Count
    Action "Invoke 'Esegui come amministratore' and accept the UAC."
    $pWait = Wait-S6LogAppend $s6ProxyLog $pb 'the elevated proxy to log its verdict'
    [void](Test-S6Expect $pWait @{ exe = 's6proxy'; elevated = '1'; action = 'REFUSED' } 'S-E guard')
    Add-TokenRow 'S-E proxy' $pWait
    $seMsg = AskYN 'Did the refusal message appear (and the target NOT start)?'
    Action 'Close the refusal message.'
    Record 'SE-jumplist' 'S-E: jump-list run-as-admin guard' @{
        offered = $offered; proxy = $pWait; refusalShown = $seMsg
        targetLogGrew = ((Get-S6LogLines $s6TargetLog).Count -ne $tb)
    }
}
else {
    Info '  [auto] vector absent on this build - itself a finding (the guard surface is Ctrl+Shift+click + programmatic).'
    Record 'SE-jumplist' 'S-E: jump-list run-as-admin guard' @{ offered = $offered }
}

# --- S-F: programmatic RunAs (automated) ---
Info "`n[S-F] programmatic RunAs verb on the proxy - the repeatable regression form of the guard."
Info 'WHAT TO WATCH: a UAC naming s6proxy.exe appears (accept it), then the refusal message.'
$pb = (Get-S6LogLines $s6ProxyLog).Count
$tb = (Get-S6LogLines $s6TargetLog).Count
Info '  [auto] Start-Process -Verb RunAs on s6proxy.exe...'
$sfCancelled = $false
try { Start-Process -FilePath $proxyExe -Verb RunAs -WorkingDirectory $s6BinDir }
catch { $sfCancelled = $true; Bad "  [auto] RunAs was cancelled or failed: $($_.Exception.Message)" }
if (-not $sfCancelled) {
    Action 'Accept the UAC prompt (it names s6proxy.exe).'
    $pWait = Wait-S6LogAppend $s6ProxyLog $pb 'the elevated proxy to log its verdict'
    [void](Test-S6Expect $pWait @{ exe = 's6proxy'; elevated = '1'; action = 'REFUSED' } 'S-F guard')
    Add-TokenRow 'S-F proxy' $pWait
    $sfMsg = AskYN 'Did the refusal message appear?'
    Action 'Close the refusal message.'
    Record 'SF-runas' 'S-F: programmatic RunAs guard' @{
        proxy = $pWait; refusalShown = $sfMsg
        targetLogGrew = ((Get-S6LogLines $s6TargetLog).Count -ne $tb)
    }
}
else {
    Record 'SF-runas' 'S-F: programmatic RunAs guard' @{ cancelled = $true }
}

# --- token matrix (Q3) ---
Info "`n[auto] Q3 token matrix - the detection-signal answer, straight from the logs:"
$script:tokenRows | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize | Out-String | Write-Host
Record 'token-matrix' 'Q3: token facts per scenario' @{ rows = @($script:tokenRows) }

# ---------- wrap-up ------------------------------------------------------------

Info "`n--- Cleanup ---"
$late = Ask 'Before cleanup: anything unexpected observed at ANY point (extra prompts, delayed windows, taskbar oddities)? (Enter for no, else notes)'
Record 'late-observations' 'Late / unexpected observations' @{ notes = $late }

$s4unpin = Join-Path $PSScriptRoot '..\s4-pinflow\bin\s4unpin.exe'
if (Test-Path $s4unpin) {
    Info '[auto] unpinning via the S-4-validated RemoveFromList (bonus data point on a third AUMID)...'
    $tool = Invoke-Tool $s4unpin @($startLnk)
    $wait = Wait-PinEvent $s6LnkName Disappear -TimeoutSec 10
    if (-not $wait.detected) {
        Action 'Programmatic unpin did not land - right-click the S6 pin -> Rimuovi dalla barra delle applicazioni.'
        $wait = Wait-PinEvent $s6LnkName Disappear
    }
    Record 'cleanup-unpin' 'Unpin (programmatic, S-4 mechanism)' @{ tool = $tool; wait = $wait }
}
else {
    Action 'Right-click the S6 pin -> Rimuovi dalla barra delle applicazioni.'
    Record 'cleanup-unpin' 'Unpin (gesture)' @{ wait = (Wait-PinEvent $s6LnkName Disappear) }
}
Info "[auto] Start-menu folder and out\ left in place for re-runs; remove per protocol SS5.4 when the spike is closed."

}
finally {
    if ($script:steps.Count -gt 0) {
        $resultsDir = Join-Path $PSScriptRoot 'results'
        New-Item -ItemType Directory -Force $resultsDir | Out-Null
        $resultsPath = Join-Path $resultsDir ("s6-run-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        @{ run = 's6-elevation'; started = $script:steps[0].at; machineBuild = $build; steps = $script:steps } |
            ConvertTo-Json -Depth 8 | Set-Content $resultsPath -Encoding utf8
        Good "`nResults written to: $resultsPath"
        Good 'Tell Claude the run is complete - the JSON will be transcribed into docs/spikes/s6-elevation.md.'
    }
}
