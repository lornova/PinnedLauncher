// PinnedLauncher spike S-8 — THROWAWAY scratch code, not product code.
// Windows.UI.Shell.TaskbarManager pin-API host for an UNPACKAGED desktop
// process. Sets the process-explicit AUMID (the launcher identity under
// test) BEFORE any window exists — that is what makes "current app" mean
// the generated Start entry — then runs one probe/pin route and prints
// parseable `s8 key="value"` lines (one pair per line).
//
// Usage: s8pin.exe <aumid> <command> [outfile]
//   probe        windowless support probes: ITaskbarManagerDesktopAppSupport-
//                Statics marker, IsSupported, IsPinningAllowed, the LAF
//                registry probe (Microsoft's documented seed-value check),
//                LimitedAccessFeatures.TryUnlockFeature status (no token),
//                IsCurrentAppPinnedAsync
//   pin-current  route A: foreground host window + RequestPinCurrentAppAsync
//                (the route Microsoft's unpackaged desktop sample blesses)
//   pin-entry    route B: AppListEntry acquisition attempt for <aumid>
//                (AppInfo.GetFromAppUserModelId -> Package.GetAppListEntries),
//                then RequestPinAppListEntryAsync if one was obtained
//   pin-tile     route C: SecondaryTile construct/pin/status/unpin attempts
//
// Output goes to stdout (visible when the runner pipes it) and, when the
// third argument is given, to that file as UTF-8 — the file is the
// authoritative copy (GUI-subsystem console capture can mojibake non-ASCII,
// e.g. localized HRESULT messages).
// Exit codes: 0 = command ran (individual facts carry their own errors),
// 2 = bad usage.
#include <windows.h>
#include <shellapi.h>
#include <shobjidl_core.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.ApplicationModel.Core.h>
#include <winrt/Windows.UI.Shell.h>
#include <winrt/Windows.UI.StartScreen.h>
#include <cstdio>
#include <string>

namespace WF   = winrt::Windows::Foundation;
namespace WAM  = winrt::Windows::ApplicationModel;
namespace WAMC = winrt::Windows::ApplicationModel::Core;
namespace WUS  = winrt::Windows::UI::Shell;
namespace WSS  = winrt::Windows::UI::StartScreen;

static FILE* g_file = nullptr;

static void emit_line(const std::wstring& line)
{
    fwprintf(stdout, L"%ls\n", line.c_str());
    fflush(stdout);
    if (g_file) { fwprintf(g_file, L"%ls\n", line.c_str()); fflush(g_file); }
}

static std::wstring sanitized(std::wstring v)
{
    for (auto& c : v) if (c == L'"' || c == L'\r' || c == L'\n') c = L'\'';
    return v;
}

static void fact(const std::wstring& key, const std::wstring& value)
{
    emit_line(L"s8 " + key + L"=\"" + sanitized(value) + L"\"");
}

static void fact(const std::wstring& key, bool v)
{
    fact(key, std::wstring(v ? L"true" : L"false"));
}

static std::wstring hex(long v)
{
    wchar_t b[16];
    swprintf_s(b, L"0x%08lX", static_cast<unsigned long>(v));
    return b;
}

static void fact_error(const std::wstring& key, winrt::hresult_error const& e)
{
    fact(key, hex(e.code().value) + L" " + std::wstring(e.message()));
}

// ---------- STA-safe await: poll + pump instead of a blocking .get() ---------

static void pump_once()
{
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

template <typename TAsync>
static auto pump_get(TAsync const& op)
{
    while (op.Status() == WF::AsyncStatus::Started)
    {
        pump_once();
        MsgWaitForMultipleObjectsEx(0, nullptr, 50, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    }
    pump_once();
    return op.GetResults(); // throws hresult_error if the operation failed
}

// ---------- host window (the pin request requires the app in foreground) -----

static HWND create_host_window()
{
    WNDCLASSW wc{};
    wc.lpfnWndProc   = DefWindowProcW;
    wc.hInstance     = GetModuleHandleW(nullptr);
    wc.hCursor       = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = L"S8PinHost";
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowExW(0, L"S8PinHost", L"S8 pin host",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT, CW_USEDEFAULT, 460, 140,
        nullptr, nullptr, wc.hInstance, nullptr);
    CreateWindowExW(0, L"STATIC",
        L"S-8 TaskbarManager pin host - keep this window in the foreground.",
        WS_CHILD | WS_VISIBLE, 12, 16, 420, 60, hwnd, nullptr, wc.hInstance, nullptr);
    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);
    SetForegroundWindow(hwnd);
    return hwnd;
}

static bool wait_foreground(HWND hwnd, int timeoutMs)
{
    const ULONGLONG start = GetTickCount64();
    while (GetTickCount64() - start < static_cast<ULONGLONG>(timeoutMs))
    {
        pump_once();
        if (GetForegroundWindow() == hwnd)
        {
            fact(L"foregroundAfterMs", std::to_wstring(GetTickCount64() - start));
            return true;
        }
        Sleep(100);
    }
    fact(L"foregroundAfterMs", std::wstring(L"timeout"));
    return false;
}

// ---------- probes -----------------------------------------------------------

static void do_support_probes()
{
    bool desktopSupport = false;
    try
    {
        desktopSupport = static_cast<bool>(
            winrt::try_get_activation_factory<WUS::TaskbarManager,
                WUS::ITaskbarManagerDesktopAppSupportStatics>());
    }
    catch (winrt::hresult_error const& e) { fact_error(L"desktopSupportError", e); }
    fact(L"desktopSupport", desktopSupport);

    try
    {
        auto tm = WUS::TaskbarManager::GetDefault();
        fact(L"getDefault", std::wstring(tm ? L"ok" : L"null"));
        if (tm)
        {
            fact(L"isSupported", tm.IsSupported());
            fact(L"isPinningAllowed", tm.IsPinningAllowed());
        }
    }
    catch (winrt::hresult_error const& e) { fact_error(L"getDefaultError", e); }
}

static void do_laf_probes()
{
    // Registry probe: semantics verbatim from Microsoft's pin-to-taskbar
    // page (IsLAFTokenRequiredForTaskbarPinning) — key absent => no token.
    static constexpr wchar_t c_seed[] =
        L"4096B239A7295B635C090E647E867B5707DA6AB6CB78340B01FE4E0C8F4953D4";
    HKEY key{};
    const LSTATUS open = RegOpenKeyExW(HKEY_LOCAL_MACHINE,
        L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModel"
        L"\\LimitedAccessFeatures\\com.microsoft.windows.taskbar.pin",
        0, KEY_READ, &key);
    fact(L"lafRegKeyPresent", open == ERROR_SUCCESS);
    bool required = false;
    if (open == ERROR_SUCCESS)
    {
        DWORD value = 0, size = sizeof(value);
        const LSTATUS qs = RegQueryValueExW(key, c_seed, nullptr, nullptr,
            reinterpret_cast<LPBYTE>(&value), &size);
        fact(L"lafSeedQuery", hex(qs));
        if (qs == ERROR_SUCCESS) fact(L"lafSeedValue", std::to_wstring(value));
        required = (qs == ERROR_SUCCESS) && value != 0;
        RegCloseKey(key);
    }
    fact(L"lafTokenRequired", required);

    // What TryUnlockFeature says with NO token — does it agree with the
    // registry probe? (Post-KB expectation: usable without a token.)
    try
    {
        auto res = WAM::LimitedAccessFeatures::TryUnlockFeature(
            L"com.microsoft.windows.taskbar.pin", L"", L"");
        std::wstring name;
        switch (res.Status())
        {
        case WAM::LimitedAccessFeatureStatus::Unavailable:            name = L"Unavailable"; break;
        case WAM::LimitedAccessFeatureStatus::Available:              name = L"Available"; break;
        case WAM::LimitedAccessFeatureStatus::AvailableWithoutToken:  name = L"AvailableWithoutToken"; break;
        case WAM::LimitedAccessFeatureStatus::Unknown:                name = L"Unknown"; break;
        default: name = L"(" + std::to_wstring(static_cast<int>(res.Status())) + L")"; break;
        }
        fact(L"lafTryUnlockStatus", name);
    }
    catch (winrt::hresult_error const& e) { fact_error(L"lafTryUnlockError", e); }
}

static void do_is_pinned(const std::wstring& key)
{
    try
    {
        auto tm = WUS::TaskbarManager::GetDefault();
        if (!tm) { fact(key, std::wstring(L"getDefault-null")); return; }
        fact(key, pump_get(tm.IsCurrentAppPinnedAsync()));
    }
    catch (winrt::hresult_error const& e) { fact_error(key + L"Error", e); }
}

// ---------- route A: current-app request -------------------------------------

static int do_pin_current()
{
    do_support_probes();
    const HWND hwnd = create_host_window();
    fact(L"foregroundReached", wait_foreground(hwnd, 60000));
    // Pre-run probe datum: windowless IsPinningAllowed read false on
    // 26200.9168 — does holding the foreground flip it?
    try
    {
        auto tm = WUS::TaskbarManager::GetDefault();
        if (tm) fact(L"isPinningAllowedForeground", tm.IsPinningAllowed());
    }
    catch (winrt::hresult_error const& e) { fact_error(L"isPinningAllowedForegroundError", e); }
    do_is_pinned(L"isCurrentAppPinnedBefore");
    try
    {
        auto tm = WUS::TaskbarManager::GetDefault();
        fact(L"requestPinCurrentApp", pump_get(tm.RequestPinCurrentAppAsync()));
    }
    catch (winrt::hresult_error const& e) { fact_error(L"requestPinCurrentAppError", e); }
    do_is_pinned(L"isCurrentAppPinnedAfter");
    DestroyWindow(hwnd);
    return 0;
}

// ---------- route B: AppListEntry request ------------------------------------

static int do_pin_entry(std::wstring const& aumid)
{
    // Acquisition: the only documented AppListEntry producers are
    // Package.GetAppListEntries[Async] — so unpackaged .lnk-based entries
    // are expected to dead-end here; whatever happens is the datum.
    WAMC::AppListEntry match{ nullptr };
    try
    {
        auto info = WAM::AppInfo::GetFromAppUserModelId(aumid);
        fact(L"appInfoFound", info != nullptr);
        if (info)
        {
            fact(L"appInfoAumid", std::wstring(info.AppUserModelId()));
            try { fact(L"appInfoDisplayName", std::wstring(info.DisplayInfo().DisplayName())); }
            catch (winrt::hresult_error const& e) { fact_error(L"appInfoDisplayNameError", e); }

            WAM::Package pkg{ nullptr };
            try { pkg = info.Package(); }
            catch (winrt::hresult_error const& e) { fact_error(L"appInfoPackageError", e); }
            fact(L"packagePresent", pkg != nullptr);
            if (pkg)
            {
                auto entries = pkg.GetAppListEntries();
                fact(L"appListEntryCount", std::to_wstring(entries.Size()));
                for (auto const& entry : entries)
                {
                    if (_wcsicmp(entry.AppUserModelId().c_str(), aumid.c_str()) == 0)
                    {
                        match = entry;
                        break;
                    }
                }
            }
        }
    }
    catch (winrt::hresult_error const& e) { fact_error(L"appInfoError", e); }
    fact(L"appListEntryAcquired", match != nullptr);
    if (!match) return 0;

    const HWND hwnd = create_host_window();
    fact(L"foregroundReached", wait_foreground(hwnd, 60000));
    try
    {
        auto tm = WUS::TaskbarManager::GetDefault();
        fact(L"isAppListEntryPinnedBefore", pump_get(tm.IsAppListEntryPinnedAsync(match)));
        fact(L"requestPinAppListEntry", pump_get(tm.RequestPinAppListEntryAsync(match)));
        fact(L"isAppListEntryPinnedAfter", pump_get(tm.IsAppListEntryPinnedAsync(match)));
    }
    catch (winrt::hresult_error const& e) { fact_error(L"requestPinAppListEntryError", e); }
    DestroyWindow(hwnd);
    return 0;
}

// ---------- route C: secondary tile ------------------------------------------

static int do_pin_tile()
{
    const wchar_t* tileId = L"PinnedLauncher.Test.S8Tile1";
    WSS::SecondaryTile tile{ nullptr };
    try
    {
        tile = WSS::SecondaryTile(tileId);
        fact(L"tileConstruct", std::wstring(L"ok"));
        tile.DisplayName(L"S8 tile test");
        tile.Arguments(L"s8tile");
        fact(L"tileConfigure", std::wstring(L"ok"));
    }
    catch (winrt::hresult_error const& e) { fact_error(L"tileConstructError", e); }

    const HWND hwnd = create_host_window();
    fact(L"foregroundReached", wait_foreground(hwnd, 30000));

    WUS::TaskbarManager tm{ nullptr };
    try { tm = WUS::TaskbarManager::GetDefault(); }
    catch (winrt::hresult_error const& e) { fact_error(L"getDefaultError", e); }
    if (tm)
    {
        if (tile)
        {
            try { fact(L"requestPinSecondaryTile", pump_get(tm.RequestPinSecondaryTileAsync(tile))); }
            catch (winrt::hresult_error const& e) { fact_error(L"requestPinSecondaryTileError", e); }
        }
        try { fact(L"isSecondaryTilePinned", pump_get(tm.IsSecondaryTilePinnedAsync(tileId))); }
        catch (winrt::hresult_error const& e) { fact_error(L"isSecondaryTilePinnedError", e); }
        try { fact(L"tryUnpinSecondaryTile", pump_get(tm.TryUnpinSecondaryTileAsync(tileId))); }
        catch (winrt::hresult_error const& e) { fact_error(L"tryUnpinSecondaryTileError", e); }
    }
    DestroyWindow(hwnd);
    return 0;
}

// -----------------------------------------------------------------------------

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv || argc < 3)
    {
        emit_line(L"usage: s8pin.exe <aumid> probe|pin-current|pin-entry|pin-tile [outfile]");
        return 2;
    }
    const std::wstring aumid = argv[1];
    const std::wstring cmd = argv[2];
    if (argc > 3) (void)_wfopen_s(&g_file, argv[3], L"wt, ccs=UTF-8");

    // Identity first: the process-explicit AUMID must be set before any UI
    // exists — the "current app" the shell sees IS this AUMID.
    const HRESULT hrAumid = SetCurrentProcessExplicitAppUserModelID(aumid.c_str());
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    fact(L"aumid", aumid);
    fact(L"command", cmd);
    fact(L"setProcessAumid", hex(hrAumid));

    int rc = 0;
    if (cmd == L"probe")
    {
        do_support_probes();
        do_laf_probes();
        do_is_pinned(L"isCurrentAppPinned");
    }
    else if (cmd == L"pin-current") rc = do_pin_current();
    else if (cmd == L"pin-entry")   rc = do_pin_entry(aumid);
    else if (cmd == L"pin-tile")    rc = do_pin_tile();
    else { emit_line(L"unknown command: " + cmd); rc = 2; }

    if (g_file) fclose(g_file);
    return rc;
}
