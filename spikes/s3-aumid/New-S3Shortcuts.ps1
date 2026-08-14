#Requires -Version 7
<#
PinnedLauncher spike S-3 (throwaway): generates the six proxy .lnk test articles
with explicit AppUserModelIDs (IShellLink + IPropertyStore, exactly the product
mechanism of architecture §2), verifies each stamped AUMID with an INDEPENDENT
reader (Shell.Application ExtendedProperty — gate G0), and installs Start-menu
entries for the manual pin gesture.

  -NoStartMenu   only write the shortcuts to out\ (no Start-menu copies)
  -VerifyPins    instead of generating: read the AUMIDs of the S3-* copies the
                 shell placed in the taskbar pin folder (gate G1, run after pinning)

Protocol and result recording: docs/spikes/s3-aumid.md

Interop note: PROPVARIANT must be declared with sequential layout and the
IPropertyStore methods with [PreserveSig] — an explicit-layout struct with
FieldOffset(8) silently breaks the out-direction marshaling on PowerShell 7
(GetValue returns VT_EMPTY; observed 2026-08-14 on 26200.8875).
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu,
    [switch]$VerifyPins
)
$ErrorActionPreference = 'Stop'

$csharp = @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace S3Lnk
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey
    {
        public Guid fmtid;
        public uint pid;
        public PropertyKey(Guid f, uint p) { fmtid = f; pid = p; }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PropVariant
    {
        public ushort vt;
        public ushort r1;
        public ushort r2;
        public ushort r3;
        public IntPtr p1;
        public IntPtr p2;
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    public class CShellLink { }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellLinkW
    {
        void GetPath([MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out ushort pwHotkey);
        void SetHotkey(ushort wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint cProps);
        [PreserveSig] int GetAt(uint iProp, out PropertyKey pkey);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant pv);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant pv);
        [PreserveSig] int Commit();
    }

    public static class ShortcutFactory
    {
        const ushort VT_LPWSTR = 31;
        static readonly Guid AppUserModelFmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PropVariant pvar);

        public static void Create(string lnkPath, string target, string args, string workDir,
                                  string iconPath, int iconIndex, string description, string aumid)
        {
            var link = (IShellLinkW)new CShellLink();
            link.SetPath(target);
            if (!string.IsNullOrEmpty(args)) link.SetArguments(args);
            if (!string.IsNullOrEmpty(workDir)) link.SetWorkingDirectory(workDir);
            if (!string.IsNullOrEmpty(iconPath)) link.SetIconLocation(iconPath, iconIndex);
            if (!string.IsNullOrEmpty(description)) link.SetDescription(description);

            var store = (IPropertyStore)link;
            var key = new PropertyKey(AppUserModelFmtid, 5); // PKEY_AppUserModel_ID
            var pv = new PropVariant { vt = VT_LPWSTR, p1 = Marshal.StringToCoTaskMemUni(aumid) };
            int hr = store.SetValue(ref key, ref pv);
            if (hr != 0) throw new COMException("IPropertyStore::SetValue failed", hr);
            hr = store.Commit();
            if (hr != 0) throw new COMException("IPropertyStore::Commit failed", hr);
            PropVariantClear(ref pv);

            ((IPersistFile)link).Save(lnkPath, true);
            Marshal.ReleaseComObject(link);
        }
    }
}
'@
if (-not ('S3Lnk.ShortcutFactory' -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

# Independent verifier: the shell's own property reader, no shared code with Create.
$script:shellApp = New-Object -ComObject Shell.Application
function Read-LnkAumid([string]$Path) {
    $item = $script:shellApp.Namespace((Split-Path $Path)).ParseName((Split-Path $Path -Leaf))
    $item.ExtendedProperty('System.AppUserModel.ID')
}

if ($VerifyPins) {
    $pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    $pins = @(Get-ChildItem $pinDir -Filter 'S3-*.lnk' -ErrorAction SilentlyContinue)
    if ($pins.Count -eq 0) { Write-Warning "No S3-* pins found in $pinDir"; return }
    $pins | ForEach-Object {
        [pscustomobject]@{ Pin = $_.Name; Aumid = Read-LnkAumid $_.FullName }
    } | Format-Table -AutoSize -Wrap
    return
}

$binDir = Join-Path $PSScriptRoot 'bin'
$outDir = Join-Path $PSScriptRoot 'out'
$proxyExe = Join-Path $binDir 's3proxy.exe'
$selfExe = Join-Path $binDir 's3selfaumid.exe'
$charmap = Join-Path $env:windir 'System32\charmap.exe'
$notepadAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\notepad.exe'
$notepadIcon = Join-Path $env:windir 'System32\notepad.exe'
if (-not (Test-Path $notepadIcon)) { $notepadIcon = Join-Path $env:windir 'System32\imageres.dll' }

foreach ($required in $proxyExe, $selfExe) {
    if (-not (Test-Path $required)) { throw "Missing $required — run .\Build-S3Binaries.ps1 first." }
}
foreach ($required in $charmap, $notepadAlias) {
    if (-not (Test-Path $required)) { throw "Missing test target $required — pick a substitute on this machine and update this script." }
}

$cases = @(
    [pscustomobject]@{ Id = 'A1'; File = 'S3-A1 plain direct';         Target = $charmap;      Args = '';                  Icon = $charmap;     Aumid = 'PinnedLauncher.S3.A1.PlainWin32' }
    [pscustomobject]@{ Id = 'A2'; File = 'S3-A2 self-AUMID direct';    Target = $selfExe;      Args = '';                  Icon = $selfExe;     Aumid = 'PinnedLauncher.S3.A2.SelfAumid' }
    [pscustomobject]@{ Id = 'A3'; File = 'S3-A3 packaged direct';      Target = $notepadAlias; Args = '';                  Icon = $notepadIcon; Aumid = 'PinnedLauncher.S3.A3.Packaged' }
    [pscustomobject]@{ Id = 'B1'; File = 'S3-B1 plain via proxy';      Target = $proxyExe;     Args = "`"$charmap`"";      Icon = $charmap;     Aumid = 'PinnedLauncher.S3.B1.PlainWin32' }
    [pscustomobject]@{ Id = 'B2'; File = 'S3-B2 self-AUMID via proxy'; Target = $proxyExe;     Args = "`"$selfExe`"";      Icon = $selfExe;     Aumid = 'PinnedLauncher.S3.B2.SelfAumid' }
    [pscustomobject]@{ Id = 'B3'; File = 'S3-B3 packaged via proxy';   Target = $proxyExe;     Args = "`"$notepadAlias`""; Icon = $notepadIcon; Aumid = 'PinnedLauncher.S3.B3.Packaged' }
)

New-Item -ItemType Directory -Force $outDir | Out-Null
$results = foreach ($case in $cases) {
    $lnk = Join-Path $outDir "$($case.File).lnk"
    Remove-Item $lnk -Force -ErrorAction SilentlyContinue
    [S3Lnk.ShortcutFactory]::Create(
        $lnk, $case.Target, $case.Args, (Split-Path $case.Target),
        $case.Icon, 0, "PinnedLauncher spike S-3 case $($case.Id) | AUMID=$($case.Aumid)", $case.Aumid)
    $readBack = Read-LnkAumid $lnk
    [pscustomobject]@{
        Case          = $case.Id
        Shortcut      = "$($case.File).lnk"
        AumidStamped  = $case.Aumid
        AumidReadBack = $readBack
        G0            = ($readBack -ceq $case.Aumid) ? 'PASS' : 'FAIL'
    }
}

$results | Format-Table -AutoSize -Wrap
if ($results.G0 -contains 'FAIL') { throw 'Gate G0 failed: at least one .lnk did not round-trip its AUMID.' }
"Gate G0: PASS (all $($results.Count) shortcuts verified by independent reader)"

if (-not $NoStartMenu) {
    $startDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S3 Spike'
    New-Item -ItemType Directory -Force $startDir | Out-Null
    Copy-Item (Join-Path $outDir '*.lnk') $startDir -Force
    "Start-menu entries installed: $startDir"
}
"Shortcuts written to: $outDir"
