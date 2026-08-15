// PinnedLauncher spike S-4 — THROWAWAY scratch code, not product code.
// Deep-link probe for the pin guide (management-window.md §9.2): can we open a
// shell view with our app entry pre-selected, so the user's remaining gesture is
// just right-click -> Pin to taskbar?
// Usage: s4select.exe <AUMID | shell:AppsFolder\AUMID | filesystem path>
//   e.g. s4select.exe PinnedLauncher.S4.PinTest1
// Parses the name, binds to the parent folder, and calls
// SHOpenFolderAndSelectItems (item selected in its parent view).
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <cstdio>
#include <cwchar>
#include <wchar.h>

int wmain(int argc, wchar_t** argv)
{
    if (argc < 2)
    {
        fwprintf(stderr, L"usage: s4select.exe <AUMID | shell:AppsFolder\\AUMID | path>\n");
        return 2;
    }

    wchar_t name[1024];
    if (wcschr(argv[1], L':') == nullptr && wcschr(argv[1], L'\\') == nullptr)
        swprintf(name, 1024, L"shell:AppsFolder\\%s", argv[1]); // bare AUMID
    else
        wcsncpy_s(name, argv[1], _TRUNCATE);

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    wprintf(L"CoInitializeEx            hr=0x%08X\n", static_cast<unsigned>(hr));

    PIDLIST_ABSOLUTE pidl = nullptr;
    hr = SHParseDisplayName(name, nullptr, &pidl, 0, nullptr);
    wprintf(L"SHParseDisplayName        hr=0x%08X (%s)\n", static_cast<unsigned>(hr), name);
    if (FAILED(hr)) { CoUninitialize(); return 1; }

    // Select the item in its parent folder view.
    hr = SHOpenFolderAndSelectItems(pidl, 0, nullptr, 0);
    wprintf(L"SHOpenFolderAndSelectItems hr=0x%08X\n", static_cast<unsigned>(hr));

    CoTaskMemFree(pidl);
    CoUninitialize();
    return SUCCEEDED(hr) ? 0 : 1;
}
