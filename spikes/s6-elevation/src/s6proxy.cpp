// PinnedLauncher spike S-6 — THROWAWAY scratch code, not product code.
// Windowless proxy exercising UC-6's elevation semantics:
//   - started at medium IL: read the target from out\s6config.txt (the
//     config-derived command) and apply the runas verb to it, so the UAC
//     prompt names the resolved target;
//   - started elevated (Ctrl+Shift+click, jump-list run-as-admin, RunAs
//     verb): the confused-deputy guard — refuse and explain BEFORE the
//     config file is even opened.
// Every decision appends one line to out\s6-proxy-log.txt (runner oracle).
// Exit codes: 0 launched · 1 UAC cancelled · 2 config missing · 3 refused
// (elevated start) · 4 other ShellExecuteEx failure.
#include "s6token.h"
#include <shellapi.h>

// First line of the config file (UTF-8, optional BOM), trimmed.
static std::wstring ReadConfigTarget(const std::wstring& cfgPath)
{
    HANDLE h = CreateFileW(cfgPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, 0, nullptr);
    if (h == INVALID_HANDLE_VALUE)
        return L"";
    char buf[2048];
    DWORD read = 0;
    ReadFile(h, buf, sizeof(buf) - 1, &read, nullptr);
    CloseHandle(h);
    buf[read] = '\0';

    char* p = buf;
    if (read >= 3 && static_cast<unsigned char>(p[0]) == 0xEF &&
        static_cast<unsigned char>(p[1]) == 0xBB &&
        static_cast<unsigned char>(p[2]) == 0xBF)
        p += 3;
    if (char* nl = strpbrk(p, "\r\n"))
        *nl = '\0';
    for (size_t len = strlen(p); len > 0 && (p[len - 1] == ' ' || p[len - 1] == '\t'); --len)
        p[len - 1] = '\0';
    if (*p == '\0')
        return L"";

    wchar_t wide[1024];
    const int n = MultiByteToWideChar(CP_UTF8, 0, p, -1, wide, 1024);
    return n > 0 ? std::wstring(wide) : L"";
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    const std::wstring out = ExeDir() + L"\\..\\out";
    const std::wstring log = out + L"\\s6-proxy-log.txt";

    // Guard first: the decision is made before any config-derived data is read.
    const TokenFacts facts = QueryTokenFacts();
    if (facts.elevated)
    {
        AppendLog(log, "s6proxy", facts, "REFUSED", 0);
        MessageBoxW(nullptr,
            L"This launcher was started elevated (for example via "
            L"Ctrl+Shift+click on the pin).\n\n"
            L"For security, the proxy never runs config-defined commands while "
            L"elevated. Use the launcher's own 'Run as administrator' option "
            L"instead: it elevates the target program directly, and the UAC "
            L"prompt names that program.",
            L"PinnedLauncher S6 spike - elevated start refused",
            MB_OK | MB_ICONERROR);
        return 3;
    }

    const std::wstring target = ReadConfigTarget(out + L"\\s6config.txt");
    if (target.empty())
    {
        AppendLog(log, "s6proxy", facts, "NOCONFIG", 0);
        return 2;
    }

    (void)CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOASYNC; // the launch must complete before this process exits
    sei.lpVerb = L"runas";        // elevation applied to the RESOLVED TARGET (UC-6)
    sei.lpFile = target.c_str();
    sei.nShow = SW_SHOWNORMAL;
    const BOOL ok = ShellExecuteExW(&sei);
    const DWORD err = ok ? 0 : GetLastError();

    CoUninitialize();

    if (ok)
    {
        AppendLog(log, "s6proxy", facts, "LAUNCHED", 0);
        return 0;
    }
    if (err == ERROR_CANCELLED)
    {
        // The user declined the UAC prompt: exit silently, no error UI (Q1).
        AppendLog(log, "s6proxy", facts, "CANCELLED", err);
        return 1;
    }
    AppendLog(log, "s6proxy", facts, "ERROR", err);
    return 4;
}
