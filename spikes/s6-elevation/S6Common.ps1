#Requires -Version 7
<#
PinnedLauncher spike S-6 (throwaway): shared paths, COM interop, and log
helpers, dot-sourced by New-S6Shortcuts.ps1 and Invoke-S6Protocol.ps1.

Shortcut interop is the S-4/S-5-proven factory (S-3 interop notes apply),
minus the icon handling — the icon is not under test here. The log helpers
parse the key=value lines s6proxy.exe / s6target.exe append, which are the
spike's automated oracle for token facts and launch outcomes.
#>
$ErrorActionPreference = 'Stop'

$s6PinDir     = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$s6StartDir   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S6 Spike'
$s6OutDir     = Join-Path $PSScriptRoot 'out'
$s6BinDir     = Join-Path $PSScriptRoot 'bin'
$s6LnkName    = 'S6 elevation test.lnk'
$s6Aumid      = 'PinnedLauncher.S6.ElevTest1'
$s6ConfigPath = Join-Path $s6OutDir 's6config.txt'
$s6ProxyLog   = Join-Path $s6OutDir 's6-proxy-log.txt'
$s6TargetLog  = Join-Path $s6OutDir 's6-target-log.txt'

$csharp = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace S6Lnk
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

        public static void Create(string lnkPath, string target, string description, string aumid)
        {
            var link = (IShellLinkW)new CShellLink();
            link.SetPath(target);
            link.SetWorkingDirectory(Path.GetDirectoryName(target));
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
if (-not ('S6Lnk.ShortcutFactory' -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

# Independent reader (Shell COM, not our interop) — gate G0.
function Read-S6LnkAumid([string]$Path) {
    $shell = New-Object -ComObject Shell.Application
    $item = $shell.Namespace((Split-Path $Path)).ParseName((Split-Path $Path -Leaf))
    $item.ExtendedProperty('System.AppUserModel.ID')
}

# The config-derived command the proxy consumes (UTF-8, first line = target path).
function Set-S6ConfigTarget([string]$TargetPath) {
    Set-Content -Path $s6ConfigPath -Value $TargetPath -Encoding utf8NoBOM
}

# Callers must wrap the result in @(...): function return unrolls the array,
# so a one-line log would otherwise come back as a bare string — and indexing
# a string with [-1] silently yields its last character, not the line.
function Get-S6LogLines([string]$Path) {
    if (Test-Path $Path) { Get-Content $Path | Where-Object { $_ -match '\S' } }
}

# One log line -> hashtable, e.g. 'elevated=1 type=Full ...' -> @{elevated='1'; type='Full'; ...}
function ConvertFrom-S6LogLine([string]$Line) {
    $h = @{}
    foreach ($token in ($Line -split '\s+')) {
        if ($token -match '^([A-Za-z]+)=(.*)$') { $h[$Matches[1]] = $Matches[2] }
    }
    $h
}
