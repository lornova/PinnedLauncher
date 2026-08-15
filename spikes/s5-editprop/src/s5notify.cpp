// PinnedLauncher spike S-5 — THROWAWAY scratch code, not product code.
// SHChangeNotify probe: sends exactly one shell change notification per
// invocation, so the icon/name refresh escalation ladder can be climbed one
// rung at a time.
// Usage:
//   s5notify.exe updateitem <absolute path>
//   s5notify.exe updatedir  <absolute path>
//   s5notify.exe renameitem <old absolute path> <new absolute path>
//   s5notify.exe updateimage [imagelist index, default -1 = whole cache]
//   s5notify.exe assocchanged
// SHCNF_FLUSH on every call: returns only after the notification is processed.
// Exit code 0 = sent; 2 = bad usage.
#include <windows.h>
#include <shlobj.h>
#include <cstdio>
#include <cstdlib>
#include <cwchar>

int wmain(int argc, wchar_t** argv)
{
    if (argc >= 3 && !wcscmp(argv[1], L"updateitem"))
    {
        SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSH, argv[2], nullptr);
        wprintf(L"sent SHCNE_UPDATEITEM (SHCNF_PATHW|FLUSH) item=%s\n", argv[2]);
    }
    else if (argc >= 3 && !wcscmp(argv[1], L"updatedir"))
    {
        SHChangeNotify(SHCNE_UPDATEDIR, SHCNF_PATHW | SHCNF_FLUSH, argv[2], nullptr);
        wprintf(L"sent SHCNE_UPDATEDIR (SHCNF_PATHW|FLUSH) dir=%s\n", argv[2]);
    }
    else if (argc >= 4 && !wcscmp(argv[1], L"renameitem"))
    {
        SHChangeNotify(SHCNE_RENAMEITEM, SHCNF_PATHW | SHCNF_FLUSH, argv[2], argv[3]);
        wprintf(L"sent SHCNE_RENAMEITEM (SHCNF_PATHW|FLUSH) old=%s new=%s\n", argv[2], argv[3]);
    }
    else if (argc >= 2 && !wcscmp(argv[1], L"updateimage"))
    {
        const DWORD_PTR index = (argc >= 3)
            ? static_cast<DWORD_PTR>(wcstol(argv[2], nullptr, 10))
            : static_cast<DWORD_PTR>(-1);
        SHChangeNotify(SHCNE_UPDATEIMAGE, SHCNF_DWORD | SHCNF_FLUSH,
                       reinterpret_cast<LPCVOID>(index), nullptr);
        wprintf(L"sent SHCNE_UPDATEIMAGE (SHCNF_DWORD|FLUSH) index=%lld\n",
                static_cast<long long>(static_cast<INT_PTR>(index)));
    }
    else if (argc >= 2 && !wcscmp(argv[1], L"assocchanged"))
    {
        SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST | SHCNF_FLUSH, nullptr, nullptr);
        wprintf(L"sent SHCNE_ASSOCCHANGED (SHCNF_IDLIST|FLUSH)\n");
    }
    else
    {
        fwprintf(stderr,
            L"usage: s5notify.exe updateitem <path>\n"
            L"       s5notify.exe updatedir <path>\n"
            L"       s5notify.exe renameitem <old path> <new path>\n"
            L"       s5notify.exe updateimage [index=-1]\n"
            L"       s5notify.exe assocchanged\n");
        return 2;
    }
    return 0;
}
