#Requires -Version 7
<#
PinnedLauncher spike S-8 (throwaway): shared paths, COM interop, and output
parsing, dot-sourced by New-S8Shortcuts.ps1 and Invoke-S8Protocol.ps1.

Shortcut interop is the S-4..S-9-proven factory (S-3 interop notes apply).
Two parsers: s9uia.exe element lines (the S-9 oracle tool, reused as-is)
and s8pin.exe `s8 key="value"` fact lines.
#>
$ErrorActionPreference = 'Stop'

$s8PinDir   = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$s8StartDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S8 Spike'
$s8OutDir   = Join-Path $PSScriptRoot 'out'
$s8BinDir   = Join-Path $PSScriptRoot 'bin'
$s8LnkName  = 'S8 pin test.lnk'
$s8Name     = 'S8 pin test'                    # display name of the article
$s8Aumid    = 'PinnedLauncher.Test.S8PinApi1'  # reserved test namespace (S-9 hygiene)

# Packaged control entries for the RequestPinAppListEntryAsync route (route B):
# first one indexed in shell:AppsFolder is used. Settings is on every Win11.
$s8ControlCandidates = @(
    'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
    'Microsoft.WindowsNotepad_8wekyb3d8bbwe!App'
    'windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'
)

$csharp = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace S8Lnk
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
if (-not ('S8Lnk.ShortcutFactory' -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

# Independent reader (Shell COM, not our interop) — gate G0, the hygiene
# sweep, and the Q3 equivalence check on the pinned copy.
function Read-S8LnkAumid([string]$Path) {
    $shell = New-Object -ComObject Shell.Application
    $item = $shell.Namespace((Split-Path $Path)).ParseName((Split-Path $Path -Leaf))
    $item.ExtendedProperty('System.AppUserModel.ID')
}

# S-9-validated oracle rule: a pinned button's AutomationId is
# "Appid: <AUMID>"; accept the bare AUMID too (prefix is undocumented).
function Test-S8IsPinId([string]$AutomationId) {
    ($AutomationId -ceq $s8Aumid) -or ($AutomationId -ceq "Appid: $s8Aumid")
}

# One s9uia element line -> hashtable (S-9's parser). Quoted values first,
# then bare ones; the bare pattern cannot match inside a quoted value
# because it excludes the quote character.
function ConvertFrom-S8UiaLine([string]$Line) {
    $h = @{}
    foreach ($m in [regex]::Matches($Line, '(\w+)="([^"]*)"')) {
        $h[$m.Groups[1].Value] = $m.Groups[2].Value
    }
    foreach ($m in [regex]::Matches($Line, '(\w+)=([^"\s]+)')) {
        if (-not $h.ContainsKey($m.Groups[1].Value)) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
    $h
}

# s8pin.exe fact lines ('s8 key="value"', one pair per line) -> one ordered
# hashtable. Console capture of a GUI-subsystem exe can mojibake non-ASCII,
# so the runner passes an outfile (UTF-8) and parses that when present.
function ConvertFrom-S8PinOutput([string[]]$Lines) {
    $facts = [ordered]@{}
    foreach ($line in $Lines) {
        if ($line -like 's8 *') {
            foreach ($m in [regex]::Matches($line, '(\w+)="([^"]*)"')) {
                $facts[$m.Groups[1].Value] = $m.Groups[2].Value
            }
        }
    }
    $facts
}
