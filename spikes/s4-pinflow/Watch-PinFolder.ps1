#Requires -Version 7
<#
PinnedLauncher spike S-4 (throwaway): live watcher on the taskbar pin folder.
Prints a timestamped line for every .lnk create/delete/rename so pin/unpin
gesture -> file-system signal latency can be observed. Ctrl+C to stop.
Run this in its OWN terminal while performing the protocol gestures.
#>
$ErrorActionPreference = 'Stop'

$pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
"Watching: $pinDir"
"Existing pins:"
Get-ChildItem $pinDir -Filter *.lnk | ForEach-Object { "  {0}  {1}" -f $_.LastWriteTime.ToString('HH:mm:ss.fff'), $_.Name }
"--- events (Ctrl+C to stop) ---"

$fsw = [System.IO.FileSystemWatcher]::new($pinDir, '*.lnk')
$fsw.IncludeSubdirectories = $false
$subs = foreach ($evt in 'Created', 'Deleted', 'Changed', 'Renamed') {
    Register-ObjectEvent $fsw $evt -Action {
        $a = $Event.SourceEventArgs
        $name = if ($a.PSObject.Properties['OldName']) { "$($a.OldName) -> $($a.Name)" } else { $a.Name }
        Write-Host ("{0:HH:mm:ss.fff}  {1,-8}  {2}" -f (Get-Date), $a.ChangeType, $name)
    }
}
$fsw.EnableRaisingEvents = $true

try { while ($true) { Start-Sleep -Seconds 1 } }
finally {
    $fsw.EnableRaisingEvents = $false
    $subs | ForEach-Object { Unregister-Event -SourceIdentifier $_.Name -ErrorAction SilentlyContinue }
    $fsw.Dispose()
}
