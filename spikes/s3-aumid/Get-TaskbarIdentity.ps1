#Requires -Version 7
<#
PinnedLauncher spike S-3 (throwaway): secondary identity oracle. Lists visible
top-level windows with their process image, the window property-store AUMID
(explicit window-level IDs only), and the packaged-app AUMID (packaged processes
only). Empty in both columns means the taskbar computed the identity itself —
expected for a plain Win32 target; the behavioral oracle (grouping probe O5 in
docs/spikes/s3-aumid.md) covers that case.

  -ProcessName <name>   filter by image name without extension,
                        e.g. charmap, s3selfaumid, Notepad
#>
[CmdletBinding()]
param(
    [string]$ProcessName
)
$ErrorActionPreference = 'Stop'

$csharp = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace S3Diag
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey
    {
        public Guid fmtid;
        public uint pid;
        public PropertyKey(Guid f, uint p) { fmtid = f; pid = p; }
    }

    // Sequential layout + [PreserveSig] are required: an explicit-layout
    // PROPVARIANT breaks the out-direction marshaling on PowerShell 7
    // (GetValue returns VT_EMPTY; see New-S3Shortcuts.ps1 header note).
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

    public class WindowRow
    {
        public int Pid;
        public string Exe;
        public string Title;
        public string WindowAumid;
        public string PackageAumid;
    }

    public static class TaskbarIdentity
    {
        delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int GetWindowTextW(IntPtr hWnd, StringBuilder sb, int cch);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern bool QueryFullProcessImageName(IntPtr h, uint flags, StringBuilder sb, ref uint size);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern int GetApplicationUserModelId(IntPtr h, ref uint length, StringBuilder sb);
        [DllImport("shell32.dll")]
        static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out IPropertyStore ps);
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant pvar);

        const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        const ushort VT_LPWSTR = 31;

        public static List<WindowRow> Snapshot()
        {
            var rows = new List<WindowRow>();
            EnumProc cb = delegate (IntPtr hwnd, IntPtr lparam)
            {
                if (!IsWindowVisible(hwnd)) return true;
                var title = new StringBuilder(512);
                GetWindowTextW(hwnd, title, title.Capacity);
                if (title.Length == 0) return true;

                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                var row = new WindowRow { Pid = (int)pid, Title = title.ToString() };

                IntPtr hp = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
                if (hp != IntPtr.Zero)
                {
                    uint size = 1024;
                    var image = new StringBuilder((int)size);
                    if (QueryFullProcessImageName(hp, 0, image, ref size)) row.Exe = image.ToString();
                    uint len = 1024;
                    var aumid = new StringBuilder((int)len);
                    if (GetApplicationUserModelId(hp, ref len, aumid) == 0) row.PackageAumid = aumid.ToString();
                    CloseHandle(hp);
                }

                Guid iid = typeof(IPropertyStore).GUID;
                IPropertyStore store;
                if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) == 0 && store != null)
                {
                    var key = new PropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
                    PropVariant pv;
                    if (store.GetValue(ref key, out pv) == 0 && pv.vt == VT_LPWSTR && pv.p1 != IntPtr.Zero)
                        row.WindowAumid = Marshal.PtrToStringUni(pv.p1);
                    PropVariantClear(ref pv);
                    Marshal.ReleaseComObject(store);
                }

                rows.Add(row);
                return true;
            };
            EnumWindows(cb, IntPtr.Zero);
            GC.KeepAlive(cb);
            return rows;
        }
    }
}
'@
if (-not ('S3Diag.TaskbarIdentity' -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

$rows = [S3Diag.TaskbarIdentity]::Snapshot()
if ($ProcessName) {
    $rows = $rows | Where-Object { $_.Exe -and [IO.Path]::GetFileNameWithoutExtension($_.Exe) -ieq $ProcessName }
}
$rows | Sort-Object Exe, Pid | Format-Table `
    @{ n = 'PID'; e = { $_.Pid } },
    @{ n = 'Exe'; e = { $_.Exe ? [IO.Path]::GetFileName($_.Exe) : '?' } },
    WindowAumid, PackageAumid, Title -AutoSize
