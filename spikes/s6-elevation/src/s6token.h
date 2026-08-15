// PinnedLauncher spike S-6 — THROWAWAY scratch code, not product code.
// Shared token-inspection and logging helpers for s6proxy.exe / s6target.exe.
// Both tools append one key=value line per run to their log under out\ — the
// runner parses these lines as the spike's automated oracle (protocol §4).
#pragma once
#include <windows.h>
#include <cstdio>
#include <fstream>
#include <string>

struct TokenFacts
{
    bool elevated = false;                                // TokenElevation
    TOKEN_ELEVATION_TYPE type = TokenElevationTypeDefault; // TokenElevationType
    DWORD integrityRid = 0;                                // TokenIntegrityLevel
};

inline TokenFacts QueryTokenFacts()
{
    TokenFacts f;
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
        return f;

    DWORD cb = 0;
    TOKEN_ELEVATION elev{};
    if (GetTokenInformation(tok, TokenElevation, &elev, sizeof(elev), &cb))
        f.elevated = elev.TokenIsElevated != 0;

    TOKEN_ELEVATION_TYPE type{};
    if (GetTokenInformation(tok, TokenElevationType, &type, sizeof(type), &cb))
        f.type = type;

    BYTE buf[sizeof(TOKEN_MANDATORY_LABEL) + SECURITY_MAX_SID_SIZE]{};
    if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof(buf), &cb))
    {
        auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf);
        const DWORD count = *GetSidSubAuthorityCount(label->Label.Sid);
        f.integrityRid = *GetSidSubAuthority(label->Label.Sid, count - 1);
    }
    CloseHandle(tok);
    return f;
}

inline const char* ElevTypeName(TOKEN_ELEVATION_TYPE t)
{
    switch (t)
    {
    case TokenElevationTypeDefault: return "Default";
    case TokenElevationTypeFull:    return "Full";
    case TokenElevationTypeLimited: return "Limited";
    }
    return "Unknown";
}

inline const char* IntegrityName(DWORD rid)
{
    if (rid >= SECURITY_MANDATORY_SYSTEM_RID) return "System";
    if (rid >= SECURITY_MANDATORY_HIGH_RID)   return "High";
    if (rid >= SECURITY_MANDATORY_MEDIUM_RID) return "Medium";
    if (rid >= SECURITY_MANDATORY_LOW_RID)    return "Low";
    return "Untrusted";
}

// Directory containing the running executable (paths are resolved from here,
// never from the CWD — an elevated start lands in System32).
inline std::wstring ExeDir()
{
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring s(path);
    const size_t slash = s.find_last_of(L'\\');
    return slash == std::wstring::npos ? s : s.substr(0, slash);
}

inline void AppendLog(const std::wstring& logPath, const char* exe,
                      const TokenFacts& f, const char* action, unsigned long detail)
{
    SYSTEMTIME st{};
    GetLocalTime(&st);
    char line[256];
    sprintf_s(line,
        "ts=%04u-%02u-%02uT%02u:%02u:%02u pid=%lu exe=%s elevated=%d type=%s "
        "integrity=%s rid=0x%04lX action=%s detail=%lu\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
        GetCurrentProcessId(), exe, f.elevated ? 1 : 0, ElevTypeName(f.type),
        IntegrityName(f.integrityRid), f.integrityRid, action, detail);
    std::ofstream(logPath.c_str(), std::ios::app) << line;
}
