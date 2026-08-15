#Requires -Version 7
<#
PinnedLauncher spike S-5 (throwaway): shared paths, COM interop, and icon
helpers, dot-sourced by New-S5Shortcuts.ps1 and Invoke-S5Protocol.ps1.

Shortcut interop is S-4's proven factory (S-3 interop notes apply) plus an
IPersistFile::Load-based icon-location editor (same link object, so the AUMID
property store must survive the edit — gate G0 re-checks it). The ICO writer is
dependency-free (no System.Drawing): 32bpp BMP-encoded entries, alpha-governed
transparency, two unmistakable variants for propagation observation.
#>
$ErrorActionPreference = 'Stop'

$s5PinDir     = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$s5StartDir   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PinnedLauncher S5 Spike'
$s5OutDir     = Join-Path $PSScriptRoot 'out'
$s5BinDir     = Join-Path $PSScriptRoot 'bin'
$s5LnkName        = 'S5 edit test.lnk'
$s5LnkRenamedName = 'S5 renamed test.lnk'
$s5Aumid      = 'PinnedLauncher.S5.EditTest1'
$s5IconPath   = Join-Path $s5OutDir 's5-icon.ico'
$s5IconV2Path = Join-Path $s5OutDir 's5-icon-v2.ico'

$csharp = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace S5Lnk
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
            link.SetWorkingDirectory(Path.GetDirectoryName(target));
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

        // Q3's edit path: load the existing .lnk, change only the icon location,
        // save. Uses the same link object end-to-end, so every other data block
        // (including the AUMID property store) must round-trip — verified by the
        // runner's G0 re-check.
        public static void SetIcon(string lnkPath, string iconPath)
        {
            var link = (IShellLinkW)new CShellLink();
            ((IPersistFile)link).Load(lnkPath, 0x00000002 /* STGM_READWRITE */);
            link.SetIconLocation(iconPath, 0);
            ((IPersistFile)link).Save(lnkPath, true);
            Marshal.ReleaseComObject(link);
        }
    }

    public static class IconFactory
    {
        // Multi-size 32bpp ICO, BMP-encoded entries, no external dependencies.
        // Variant A: orange square + green corner badge.
        // Variant B: blue circle + red corner badge.
        // Shape, color, and badge all differ so a propagated update is
        // unmistakable at taskbar size.
        public static void Write(string path, string variant)
        {
            int[] sizes = { 16, 24, 32, 48, 256 };
            var blobs = new List<byte[]>();
            foreach (int s in sizes) blobs.Add(EncodeEntry(s, variant));
            using (var bw = new BinaryWriter(new FileStream(path, FileMode.Create, FileAccess.Write)))
            {
                bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)sizes.Length);
                uint offset = (uint)(6 + 16 * sizes.Length);
                for (int i = 0; i < sizes.Length; i++)
                {
                    int s = sizes[i];
                    bw.Write((byte)(s == 256 ? 0 : s));        // width  (0 means 256)
                    bw.Write((byte)(s == 256 ? 0 : s));        // height
                    bw.Write((byte)0); bw.Write((byte)0);      // palette, reserved
                    bw.Write((ushort)1); bw.Write((ushort)32); // planes, bpp
                    bw.Write((uint)blobs[i].Length); bw.Write(offset);
                    offset += (uint)blobs[i].Length;
                }
                foreach (var b in blobs) bw.Write(b);
            }
        }

        static byte[] EncodeEntry(int s, string variant)
        {
            bool circle = variant == "B";
            uint main  = circle ? 0xFF2B6BD8u : 0xFFE87C1Eu; // ARGB
            uint badge = circle ? 0xFFD22B2Bu : 0xFF1E9E50u;
            int maskStride = ((s + 31) / 32) * 4;            // 1bpp AND mask rows
            var d = new byte[40 + s * s * 4 + maskStride * s];
            PutInt(d, 0, 40); PutInt(d, 4, s); PutInt(d, 8, s * 2); // biHeight doubled: XOR + AND
            d[12] = 1; d[14] = 32;
            PutInt(d, 20, s * s * 4 + maskStride * s);
            double c = (s - 1) / 2.0, r = s * 0.47;
            int m = Math.Max(1, s / 10);
            int b0 = s - Math.Max(4, (int)(s * 0.44));
            for (int y = 0; y < s; y++)
            {
                int row = 40 + (s - 1 - y) * s * 4; // bottom-up
                for (int x = 0; x < s; x++)
                {
                    bool inMain = circle
                        ? (x - c) * (x - c) + (y - c) * (y - c) <= r * r
                        : x >= m && x < s - m && y >= m && y < s - m;
                    uint argb = (x >= b0 && y >= b0) ? badge : inMain ? main : 0u;
                    int o = row + x * 4;
                    d[o]     = (byte)argb;         // B
                    d[o + 1] = (byte)(argb >> 8);  // G
                    d[o + 2] = (byte)(argb >> 16); // R
                    d[o + 3] = (byte)(argb >> 24); // A
                }
            }
            return d; // AND mask stays zeroed — the alpha channel governs
        }

        static void PutInt(byte[] d, int o, int v)
        {
            d[o] = (byte)v; d[o + 1] = (byte)(v >> 8);
            d[o + 2] = (byte)(v >> 16); d[o + 3] = (byte)(v >> 24);
        }
    }
}
'@
if (-not ('S5Lnk.ShortcutFactory' -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

function Write-S5Icon([string]$Path, [ValidateSet('A', 'B')][string]$Variant) {
    [S5Lnk.IconFactory]::Write($Path, $Variant)
}

function Set-S5LnkIcon([string]$LnkPath, [string]$IconPath) {
    [S5Lnk.ShortcutFactory]::SetIcon($LnkPath, $IconPath)
}

# Independent reader (Shell COM, not our interop) — gate G0.
function Read-S5LnkAumid([string]$Path) {
    $shell = New-Object -ComObject Shell.Application
    $item = $shell.Namespace((Split-Path $Path)).ParseName((Split-Path $Path -Leaf))
    $item.ExtendedProperty('System.AppUserModel.ID')
}
