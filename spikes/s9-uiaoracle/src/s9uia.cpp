// PinnedLauncher spike S-9 — THROWAWAY scratch code, not product code.
// Console UIA walker over the primary taskbar (Shell_TrayWnd), using the
// same native COM API (IUIAutomation) the ADR-0009 harness helper will use.
// Dumps every descendant element that has a Name or AutomationId as one
// key="value" line; an optional argument filters by case-insensitive
// substring matched against Name OR AutomationId.
//   s9uia.exe             — dump all named/identified taskbar elements
//   s9uia.exe "S9 pin"    — dump only matching elements
// Output line (quotes inside values are replaced by apostrophes so the
// runner's regex parser stays trivial):
//   element controlType=50000 name="..." automationId="..." className="..."
//           state=0x1100010 offscreen=0 rect=l,t,r,b
#include <windows.h>
#include <uiautomation.h>
#include <cstdio>
#include <string>

static std::wstring FromBstr(BSTR b)
{
    std::wstring s = b ? b : L"";
    if (b) SysFreeString(b);
    for (auto& c : s) if (c == L'"') c = L'\'';
    return s;
}

static std::wstring Lower(std::wstring s)
{
    for (auto& c : s) c = towlower(c);
    return s;
}

int wmain(int argc, wchar_t** argv)
{
    const std::wstring filter = (argc > 1) ? Lower(argv[1]) : L"";

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) { printf("CoInitializeEx hr=0x%08lX\n", (unsigned long)hr); return 1; }

    int exitCode = 1;
    IUIAutomation* ua = nullptr;
    IUIAutomationElement* root = nullptr;
    IUIAutomationElement* tray = nullptr;
    IUIAutomationCondition* trayCond = nullptr;
    IUIAutomationCondition* trueCond = nullptr;
    IUIAutomationElementArray* all = nullptr;

    hr = CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                          __uuidof(IUIAutomation), reinterpret_cast<void**>(&ua));
    printf("CoCreateInstance(UIA)      hr=0x%08lX\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) hr = ua->GetRootElement(&root);
    if (SUCCEEDED(hr))
    {
        VARIANT v;
        v.vt = VT_BSTR;
        v.bstrVal = SysAllocString(L"Shell_TrayWnd");
        hr = ua->CreatePropertyCondition(UIA_ClassNamePropertyId, v, &trayCond);
        VariantClear(&v);
    }
    if (SUCCEEDED(hr)) hr = root->FindFirst(TreeScope_Children, trayCond, &tray);
    printf("FindFirst(Shell_TrayWnd)   hr=0x%08lX%s\n", (unsigned long)hr,
           (SUCCEEDED(hr) && !tray) ? " (NOT FOUND)" : "");
    if (SUCCEEDED(hr) && tray)
    {
        hr = ua->CreateTrueCondition(&trueCond);
        if (SUCCEEDED(hr)) hr = tray->FindAll(TreeScope_Descendants, trueCond, &all);
        printf("FindAll(descendants)       hr=0x%08lX\n", (unsigned long)hr);
    }

    if (SUCCEEDED(hr) && all)
    {
        int total = 0, printed = 0;
        all->get_Length(&total);
        for (int i = 0; i < total; ++i)
        {
            IUIAutomationElement* el = nullptr;
            if (FAILED(all->GetElement(i, &el)) || !el) continue;

            BSTR b = nullptr;
            el->get_CurrentName(&b);
            const std::wstring name = FromBstr(b);
            b = nullptr;
            el->get_CurrentAutomationId(&b);
            const std::wstring autoId = FromBstr(b);

            const bool hasIdentity = !name.empty() || !autoId.empty();
            const bool matches = filter.empty() ||
                Lower(name).find(filter) != std::wstring::npos ||
                Lower(autoId).find(filter) != std::wstring::npos;
            if (hasIdentity && matches)
            {
                b = nullptr;
                el->get_CurrentClassName(&b);
                const std::wstring cls = FromBstr(b);
                CONTROLTYPEID ct = 0;
                el->get_CurrentControlType(&ct);
                BOOL off = FALSE;
                el->get_CurrentIsOffscreen(&off);
                RECT rc{};
                el->get_CurrentBoundingRectangle(&rc);
                long state = 0;
                VARIANT sv;
                VariantInit(&sv);
                if (SUCCEEDED(el->GetCurrentPropertyValue(UIA_LegacyIAccessibleStatePropertyId, &sv))
                    && (sv.vt == VT_I4 || sv.vt == VT_UI4))
                    state = sv.lVal;
                VariantClear(&sv);

                printf("element controlType=%d name=\"%ls\" automationId=\"%ls\" "
                       "className=\"%ls\" state=0x%lX offscreen=%d rect=%ld,%ld,%ld,%ld\n",
                       ct, name.c_str(), autoId.c_str(), cls.c_str(),
                       state, off ? 1 : 0, rc.left, rc.top, rc.right, rc.bottom);
                ++printed;
            }
            el->Release();
        }
        printf("summary total=%d printed=%d\n", total, printed);
        exitCode = 0;
    }

    if (all) all->Release();
    if (trueCond) trueCond->Release();
    if (tray) tray->Release();
    if (trayCond) trayCond->Release();
    if (root) root->Release();
    if (ua) ua->Release();
    CoUninitialize();
    return exitCode;
}
