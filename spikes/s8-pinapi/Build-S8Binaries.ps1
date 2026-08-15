#Requires -Version 7
# PinnedLauncher spike S-8 (throwaway): compiles the scratch tool into bin\
# using the newest installed Visual Studio C++ toolchain (x64). s8pin is a
# WINDOWS-subsystem C++/WinRT host (the pin request needs a real foreground
# window); it still prints to stdout when the runner pipes it.
$ErrorActionPreference = 'Stop'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found — install Visual Studio with the C++ workload.' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'No Visual Studio instance with the C++ toolchain found.' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$installerDir = Split-Path $vswhere

$binDir = Join-Path $PSScriptRoot 'bin'
$srcDir = Join-Path $PSScriptRoot 'src'
New-Item -ItemType Directory -Force $binDir | Out-Null

$targets = @(
    @{ name = 's8pin'; subsystem = 'WINDOWS'; libs = 'windowsapp.lib user32.lib shell32.lib advapi32.lib ole32.lib' }
)

Push-Location $binDir
try {
    foreach ($t in $targets) {
        # vcvars64.bat invokes vswhere itself and expects it on PATH
        cmd /c "set `"PATH=$installerDir;%PATH%`" && `"$vcvars`" >nul && cl /nologo /O1 /W4 /EHsc /std:c++20 /DUNICODE /D_UNICODE `"$srcDir\$($t.name).cpp`" /Fe:$($t.name).exe /link /SUBSYSTEM:$($t.subsystem) $($t.libs)"
        if ($LASTEXITCODE) { throw "cl failed for $($t.name) (exit $LASTEXITCODE)" }
    }
}
finally { Pop-Location }
Remove-Item (Join-Path $binDir '*.obj') -ErrorAction SilentlyContinue

Get-ChildItem $binDir -Filter *.exe | Format-Table Name, Length, LastWriteTime -AutoSize
