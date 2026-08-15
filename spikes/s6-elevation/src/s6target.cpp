// PinnedLauncher spike S-6 — THROWAWAY scratch code, not product code.
// Self-reporting elevation target: logs its own token facts (the automated
// oracle proving the runas launch really elevated it), then holds a message
// box open so the taskbar button can be observed (own button, not merged
// into the pin — the S-3 invariant under elevation). Unsigned on purpose:
// the UAC prompt must show this file's name with the unknown-publisher
// banner (Q1 naming check).
#include "s6token.h"

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    const std::wstring log = ExeDir() + L"\\..\\out\\s6-target-log.txt";

    const TokenFacts facts = QueryTokenFacts();
    AppendLog(log, "s6target", facts, "RUNNING", 0);

    wchar_t msg[512];
    swprintf_s(msg,
        L"S6 target running.\n\n"
        L"elevated = %d\nelevation type = %hs\nintegrity = %hs (0x%04lX)\n\n"
        L"Check the taskbar now (this box should have its OWN button, separate "
        L"from the pin), then press OK to exit.",
        facts.elevated ? 1 : 0, ElevTypeName(facts.type),
        IntegrityName(facts.integrityRid), facts.integrityRid);
    MessageBoxW(nullptr, msg, L"S6 target", MB_OK | MB_ICONINFORMATION);
    return 0;
}
