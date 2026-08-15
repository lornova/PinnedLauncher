// PinnedLauncher spike S-9 — THROWAWAY scratch code, not product code.
// Real windowed target: shows one top-level window whose title comes from
// the command line (default "S9 pin test"), so its running taskbar button
// carries EXACTLY the pin's display name — the collision under test. The
// runner closes it gracefully (CloseMainWindow -> WM_CLOSE).
#include <windows.h>
#include <string>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, PWSTR cmdLine, int)
{
    std::wstring title = cmdLine ? cmdLine : L"";
    const size_t a = title.find_first_not_of(L" \t\"");
    const size_t b = title.find_last_not_of(L" \t\"");
    title = (a == std::wstring::npos) ? L"" : title.substr(a, b - a + 1);
    if (title.empty()) title = L"S9 pin test";

    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = L"S9TargetWindow";
    RegisterClassW(&wc);

    HWND hwnd = CreateWindowExW(0, wc.lpszClassName, title.c_str(),
                                WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                                420, 220, nullptr, nullptr, hInst, nullptr);
    if (!hwnd) return 1;
    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}
