// PinnedLauncher spike S-4 — THROWAWAY scratch code, not product code.
// Programmatic unpin probe: IStartMenuPinnedList::RemoveFromList on a shortcut.
// Usage: s4unpin.exe <absolute path to .lnk>
// Exit code 0 = S_OK; prints every HRESULT so partial failures are diagnosable.
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <cstdio>

// CLSID_StartMenuPin — the documented coclass for IStartMenuPinnedList
static const CLSID kClsidStartMenuPin =
    { 0xa2a9545d, 0xa0c2, 0x42b4, { 0x97, 0x08, 0xa0, 0xb2, 0xba, 0xdd, 0x77, 0xc8 } };

int wmain(int argc, wchar_t** argv)
{
    if (argc < 2)
    {
        fwprintf(stderr, L"usage: s4unpin.exe <absolute path to .lnk>\n");
        return 2;
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    wprintf(L"CoInitializeEx            hr=0x%08X\n", static_cast<unsigned>(hr));

    IShellItem* item = nullptr;
    hr = SHCreateItemFromParsingName(argv[1], nullptr, IID_PPV_ARGS(&item));
    wprintf(L"SHCreateItemFromParsingName hr=0x%08X (%s)\n", static_cast<unsigned>(hr), argv[1]);
    if (FAILED(hr)) { CoUninitialize(); return 1; }

    IStartMenuPinnedList* pinned = nullptr;
    hr = CoCreateInstance(kClsidStartMenuPin, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pinned));
    wprintf(L"CoCreateInstance(StartMenuPin) hr=0x%08X\n", static_cast<unsigned>(hr));
    if (FAILED(hr)) { item->Release(); CoUninitialize(); return 1; }

    hr = pinned->RemoveFromList(item);
    wprintf(L"RemoveFromList            hr=0x%08X\n", static_cast<unsigned>(hr));

    pinned->Release();
    item->Release();
    CoUninitialize();
    return SUCCEEDED(hr) ? 0 : 1;
}
