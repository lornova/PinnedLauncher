// PinnedLauncher spike S-7 — THROWAWAY scratch code, not product code.
// Windowless jump-list task target: appends one key=value line with its
// command-line arguments to out\s7-task-log.txt and exits — the Q2 oracle
// proving a clicked task invoked our exe with the stored arguments. Task
// args are single-token by design (alpha/beta/gamma/alpha2) so the
// key=value log line stays parseable.
#include <windows.h>
#include <cstdio>
#include <fstream>
#include <string>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR cmdLine, int)
{
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring dir(path);
    dir = dir.substr(0, dir.find_last_of(L'\\'));
    const std::wstring log = dir + L"\\..\\out\\s7-task-log.txt";

    // Trim and narrow the args (ASCII single-token by design; '-' if empty,
    // which would indicate the pin itself was clicked, not a task).
    std::wstring args = cmdLine ? cmdLine : L"";
    const size_t a = args.find_first_not_of(L" \t");
    const size_t b = args.find_last_not_of(L" \t");
    args = (a == std::wstring::npos) ? L"" : args.substr(a, b - a + 1);
    char narrow[256] = "-";
    if (!args.empty())
        WideCharToMultiByte(CP_UTF8, 0, args.c_str(), -1, narrow, sizeof(narrow), nullptr, nullptr);

    SYSTEMTIME st{};
    GetLocalTime(&st);
    char line[512];
    sprintf_s(line, "ts=%04u-%02u-%02uT%02u:%02u:%02u pid=%lu exe=s7taskecho args=%s\n",
              st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
              GetCurrentProcessId(), narrow);
    std::ofstream(log.c_str(), std::ios::app) << line;
    return 0;
}
