// PinnedLauncher spike S-7 — THROWAWAY scratch code, not product code.
// Console tool around ICustomDestinationList for a given AUMID, exercising
// the product's publisher lifecycle (architecture §4.1):
//   s7jumplist.exe commit  <AUMID> <taskExe>  — initial list: "S7 Alpha task"
//       (args alpha), "S7 Beta task" (beta), separator, "S7 Gamma task" (gamma)
//   s7jumplist.exe commit2 <AUMID> <taskExe>  — edited list: "S7 Alpha task v2"
//       (alpha2), "S7 Gamma task" (gamma) — rename + drops, the edit path
//   s7jumplist.exe delete  <AUMID>            — DeleteList, the removal path
// One HRESULT printed per API step (s4-tool style); exit 0 iff all succeeded.
#include <initguid.h>
#include <windows.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <cstdio>

static void P(const char* what, HRESULT hr)
{
    printf("%-28s hr=0x%08lX\n", what, static_cast<unsigned long>(hr));
}

static HRESULT SetTitle(IShellLinkW* link, PCWSTR title)
{
    IPropertyStore* store = nullptr;
    HRESULT hr = link->QueryInterface(IID_PPV_ARGS(&store));
    if (FAILED(hr)) return hr;
    PROPVARIANT pv;
    hr = InitPropVariantFromString(title, &pv);
    if (SUCCEEDED(hr))
    {
        hr = store->SetValue(PKEY_Title, pv);
        PropVariantClear(&pv);
    }
    if (SUCCEEDED(hr)) hr = store->Commit();
    store->Release();
    return hr;
}

static HRESULT MakeTask(PCWSTR exe, PCWSTR args, PCWSTR title, IShellLinkW** out)
{
    *out = nullptr;
    IShellLinkW* link = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&link));
    if (FAILED(hr)) return hr;
    link->SetPath(exe);
    link->SetArguments(args); // arguments are mandatory for jump-list tasks
    hr = SetTitle(link, title);
    if (SUCCEEDED(hr)) *out = link; else link->Release();
    return hr;
}

static HRESULT MakeSeparator(IShellLinkW** out)
{
    *out = nullptr;
    IShellLinkW* link = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&link));
    if (FAILED(hr)) return hr;
    IPropertyStore* store = nullptr;
    hr = link->QueryInterface(IID_PPV_ARGS(&store));
    if (SUCCEEDED(hr))
    {
        PROPVARIANT pv;
        hr = InitPropVariantFromBoolean(TRUE, &pv);
        if (SUCCEEDED(hr))
        {
            hr = store->SetValue(PKEY_AppUserModel_IsDestListSeparator, pv);
            PropVariantClear(&pv);
        }
        if (SUCCEEDED(hr)) hr = store->Commit();
        store->Release();
    }
    if (SUCCEEDED(hr)) *out = link; else link->Release();
    return hr;
}

static int Commit(PCWSTR aumid, PCWSTR taskExe, bool edited)
{
    ICustomDestinationList* cdl = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_DestinationList, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&cdl));
    P("CoCreateInstance(CDL)", hr);
    if (FAILED(hr)) return 1;

    hr = cdl->SetAppID(aumid);
    P("SetAppID", hr);

    UINT minSlots = 0;
    IObjectArray* removed = nullptr;
    if (SUCCEEDED(hr))
    {
        hr = cdl->BeginList(&minSlots, IID_PPV_ARGS(&removed));
        P("BeginList", hr);
        if (removed) removed->Release();
    }

    IObjectCollection* coll = nullptr;
    if (SUCCEEDED(hr))
    {
        hr = CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&coll));
        P("CoCreateInstance(collection)", hr);
    }

    if (SUCCEEDED(hr))
    {
        IShellLinkW* item = nullptr;
        if (!edited)
        {
            if (SUCCEEDED(hr) && SUCCEEDED(hr = MakeTask(taskExe, L"alpha", L"S7 Alpha task", &item)))
                { coll->AddObject(item); item->Release(); }
            P("MakeTask(Alpha)", hr);
            if (SUCCEEDED(hr) && SUCCEEDED(hr = MakeTask(taskExe, L"beta", L"S7 Beta task", &item)))
                { coll->AddObject(item); item->Release(); }
            P("MakeTask(Beta)", hr);
            if (SUCCEEDED(hr) && SUCCEEDED(hr = MakeSeparator(&item)))
                { coll->AddObject(item); item->Release(); }
            P("MakeSeparator", hr);
            if (SUCCEEDED(hr) && SUCCEEDED(hr = MakeTask(taskExe, L"gamma", L"S7 Gamma task", &item)))
                { coll->AddObject(item); item->Release(); }
            P("MakeTask(Gamma)", hr);
        }
        else
        {
            if (SUCCEEDED(hr) && SUCCEEDED(hr = MakeTask(taskExe, L"alpha2", L"S7 Alpha task v2", &item)))
                { coll->AddObject(item); item->Release(); }
            P("MakeTask(Alpha v2)", hr);
            if (SUCCEEDED(hr) && SUCCEEDED(hr = MakeTask(taskExe, L"gamma", L"S7 Gamma task", &item)))
                { coll->AddObject(item); item->Release(); }
            P("MakeTask(Gamma)", hr);
        }
    }

    IObjectArray* arr = nullptr;
    if (SUCCEEDED(hr))
    {
        hr = coll->QueryInterface(IID_PPV_ARGS(&arr));
        P("QI(IObjectArray)", hr);
    }
    if (SUCCEEDED(hr))
    {
        hr = cdl->AddUserTasks(arr);
        P("AddUserTasks", hr);
    }
    if (SUCCEEDED(hr))
    {
        hr = cdl->CommitList();
        P("CommitList", hr);
    }

    if (arr) arr->Release();
    if (coll) coll->Release();
    cdl->Release();
    return SUCCEEDED(hr) ? 0 : 1;
}

static int Delete(PCWSTR aumid)
{
    ICustomDestinationList* cdl = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_DestinationList, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&cdl));
    P("CoCreateInstance(CDL)", hr);
    if (FAILED(hr)) return 1;
    hr = cdl->DeleteList(aumid);
    P("DeleteList", hr);
    cdl->Release();
    return SUCCEEDED(hr) ? 0 : 1;
}

int wmain(int argc, wchar_t** argv)
{
    if (argc < 3)
    {
        printf("usage: s7jumplist.exe commit|commit2 <AUMID> <taskExe>\n"
               "       s7jumplist.exe delete <AUMID>\n");
        return 2;
    }
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    P("CoInitializeEx", hr);
    if (FAILED(hr)) return 1;

    int rc = 2;
    if (wcscmp(argv[1], L"commit") == 0 && argc >= 4)       rc = Commit(argv[2], argv[3], false);
    else if (wcscmp(argv[1], L"commit2") == 0 && argc >= 4) rc = Commit(argv[2], argv[3], true);
    else if (wcscmp(argv[1], L"delete") == 0)               rc = Delete(argv[2]);
    else printf("unknown or incomplete command\n");

    CoUninitialize();
    return rc;
}
