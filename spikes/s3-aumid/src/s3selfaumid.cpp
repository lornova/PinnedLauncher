// PinnedLauncher spike S-3 — THROWAWAY scratch code, not product code.
// A plain Win32 exe that sets its own explicit AUMID before creating its window:
// target class (b) of implementation-plan P0.1.
#include <windows.h>
#include <shobjidl_core.h>

namespace
{
    constexpr wchar_t kAumid[] = L"PinnedLauncher.S3.SelfMarker";
    constexpr wchar_t kText[] =
        L"S-3 self-AUMID test app\n"
        L"Explicit process AUMID: PinnedLauncher.S3.SelfMarker";

    LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
    {
        switch (msg)
        {
        case WM_PAINT:
        {
            PAINTSTRUCT ps;
            const HDC dc = BeginPaint(hwnd, &ps);
            RECT rc;
            GetClientRect(hwnd, &rc);
            InflateRect(&rc, -16, -16);
            DrawTextW(dc, kText, -1, &rc, DT_CENTER | DT_WORDBREAK);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(hwnd, msg, wp, lp);
        }
    }
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCmd)
{
    // Must precede any UI so the taskbar sees the explicit identity.
    (void)SetCurrentProcessExplicitAppUserModelID(kAumid);

    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.lpszClassName = L"PinnedLauncherS3SelfAumid";
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassW(&wc);

    const HWND hwnd = CreateWindowExW(
        0, wc.lpszClassName, L"S-3 SelfAUMID", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 520, 240, nullptr, nullptr, instance, nullptr);
    if (hwnd == nullptr)
        return 1;
    ShowWindow(hwnd, showCmd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return static_cast<int>(msg.wParam);
}
