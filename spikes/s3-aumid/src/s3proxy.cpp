// PinnedLauncher spike S-3 — THROWAWAY scratch code, not product code.
// Windowless flavor-B proxy: launches argv[1] as a fresh shell activation and
// exits immediately. No window, no message loop, no taskbar presence.
#include <windows.h>
#include <shellapi.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv == nullptr || argc < 2)
        return 2;

    (void)CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOASYNC; // the launch must complete before this process exits
    sei.lpVerb = L"open";
    sei.lpFile = argv[1];
    sei.nShow = SW_SHOWNORMAL;
    const BOOL ok = ShellExecuteExW(&sei);

    CoUninitialize();
    LocalFree(argv);
    return ok ? 0 : 1;
}
