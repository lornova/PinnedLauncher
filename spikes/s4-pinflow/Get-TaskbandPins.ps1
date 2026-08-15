#Requires -Version 7
<#
PinnedLauncher spike S-4 (throwaway): compares the two pin-state signals.

1. File heuristic: .lnk copies under User Pinned\TaskBar (the management
   window's planned best-effort indicator).
2. Registry: crude string extraction of .lnk names from the Taskband
   "Favorites" binary blob (HKCU\...\Explorer\Taskband) — the shell's own
   persisted pin order. Known to be written lazily; this script exists to
   measure exactly how lazily.
#>
$ErrorActionPreference = 'Stop'

$pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
"== File heuristic ($pinDir) =="
Get-ChildItem $pinDir -Filter *.lnk -ErrorAction SilentlyContinue |
    ForEach-Object { "  {0}  {1}" -f $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $_.Name }

"== Taskband\Favorites blob (registry) =="
$tb = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -ErrorAction SilentlyContinue
if (-not $tb -or -not $tb.Favorites) { "  (no Favorites value)"; return }

# UTF-16 strings can sit at even or odd byte offsets inside the pidl stream —
# decode both alignments and collect anything that looks like a .lnk name.
$bytes = $tb.Favorites
$found = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($offset in 0, 1) {
    $slice = $bytes[$offset..($bytes.Length - 1)]
    $text = [System.Text.Encoding]::Unicode.GetString($slice)
    foreach ($m in [regex]::Matches($text, '[\w \-\.\(\)]{3,}\.lnk')) { [void]$found.Add($m.Value) }
}
if ($found.Count) { $found | ForEach-Object { "  $_" } } else { "  (no .lnk names extracted)" }
"Blob size: $($bytes.Length) bytes; registry key last write is not exposed via this API — compare content only."
