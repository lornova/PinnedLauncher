#Requires -Version 7
<#
PinnedLauncher spike S-4 (throwaway): generates the two pin-lifecycle test
shortcuts (explicit AUMIDs, same product mechanism as S-3) and installs
Start-menu entries. Verified by an independent reader (gate G0).

The targets are never clicked in this spike — lifecycle only — so a direct
charmap target is fine despite the S-3 flavor-A finding.

Protocol and result recording: docs/spikes/s4-pinflow.md
#>
[CmdletBinding()]
param(
    [switch]$NoStartMenu
)
$ErrorActionPreference = 'Stop'

$csharp = @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace S4Lnk
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey
    {
        public Guid fmtid;
        public uint pid;
        public PropertyKey(Guid f, uint p) { fmtid = f; pid = p; }
    }

    // Sequential layout + [PreserveSig] required — see S-3's interop note.
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

        public static void Create(string lnkPath, string target, string iconPath,
                                  string description, string aumid)
        {
            var link = (IShellLinkW)new CShellLink();
            link.SetPath(target);
            link.SetWorkingDirectory(System.IO.Path.GetDirectoryName(target));
            link.SetIconLocation(iconPath, 0);
            link.SetDescription(description);

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
if (-not ('S4Lnk.ShortcutFactory' -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

$script:shellApp = New-Object -ComObject Shell.Application
function Read-LnkAumid([string]$Path) {
    $item = $script:shellApp.Namespace((Split-Path $Path)).ParseName((Split-Path $Path -Leaf))
    $item.ExtendedProperty('System.AppUserModel.ID')
}

$outDir = Join-Path $PSScriptRoot 'out'
$charmap = Join-Path $env:windir 'System32\charmap.exe'

$cases = @(
    [pscustomobject]@{ File = 'S4-1 pin test'; Aumid = 'PinnedLauncher.S4.PinTest1' }
    [pscustomobject]@{ File = 'S4-2 pin test'; Aumid = 'PinnedLauncher.S4.PinTest2' }
)

New-Item -ItemType Directory -Force $outDir | Out-Null
$results = foreach ($case in $cases) {
    $lnk = Join-Path $outDir "$($case.File).lnk"
    Remove-Item $lnk -Force -ErrorAction SilentlyContinue
    [S4Lnk.ShortcutFactory]::Create(
        $lnk, $charmap, $charmap,
        "PinnedLauncher spike S-4 | AUMID=$($case.Aumid)", $case.Aumid)
    $readBack = Read-LnkAumid $lnk
    [pscustomobject]@{
        Shortcut      = "$($case.File).lnk"
        AumidStamped  = $case.Aumid
        AumidReadBack = $readBack
        G0            = ($readBack -ceq $case.Aumid) ? 'PASS' : 'FAIL'
    }
}

$results | Format-Table -AutoSize -Wrap
if ($results.G0 -contains 'FAIL') { throw 'Gate G0 failed.' }
"Gate G0: PASS (all $($results.Count) shortcuts verified by independent reader)"

if (-not $NoStartMenu) {
    $startDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S4 Spike'
    New-Item -ItemType Directory -Force $startDir | Out-Null
    Copy-Item (Join-Path $outDir '*.lnk') $startDir -Force
    "Start-menu entries installed: $startDir"
}
"Shortcuts written to: $outDir"
