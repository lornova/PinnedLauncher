#Requires -Version 7
# PinnedLauncher spike S-6 (throwaway): compiles the scratch tools into bin\
# using the newest installed Visual Studio C++ toolchain (x64). Both are
# /SUBSYSTEM:WINDOWS — the proxy is windowless by design, the target's only
# window is its message box.
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

Push-Location $binDir
try {
    foreach ($name in 's6proxy', 's6target') {
        # vcvars64.bat invokes vswhere itself and expects it on PATH
        cmd /c "set `"PATH=$installerDir;%PATH%`" && `"$vcvars`" >nul && cl /nologo /O1 /W4 /EHsc /std:c++20 /DUNICODE /D_UNICODE `"$srcDir\$name.cpp`" /Fe:$name.exe /link /SUBSYSTEM:WINDOWS shell32.lib ole32.lib user32.lib advapi32.lib"
        if ($LASTEXITCODE) { throw "cl failed for $name (exit $LASTEXITCODE)" }
    }
}
finally { Pop-Location }
Remove-Item (Join-Path $binDir '*.obj') -ErrorAction SilentlyContinue

Get-ChildItem $binDir -Filter *.exe | Format-Table Name, Length, LastWriteTime -AutoSize
