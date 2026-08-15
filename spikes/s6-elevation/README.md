# Spike S-6 scratch artifacts (throwaway)

Scratch code for spike S-6 (elevation semantics + confused-deputy guard,
implementation-plan P0.2). **Not product code.** Protocol and results:
[docs/spikes/s6-elevation.md](../../docs/spikes/s6-elevation.md).

| File | Purpose |
|---|---|
| [Invoke-S6Protocol.ps1](Invoke-S6Protocol.ps1) | **Guided protocol runner** — automates builds, config swaps, log polling with automatic expectation checks, and the programmatic-RunAs guard scenario; states what to watch before each observable step; writes `results\*.json` |
| [S6Common.ps1](S6Common.ps1) | Shared paths + interop, dot-sourced by the other scripts: shortcut factory (S-4/S-5's, icon handling dropped), independent AUMID reader (gate G0), config writer, key=value log parsing |
| [New-S6Shortcuts.ps1](New-S6Shortcuts.ps1) | Test-article generator: config file pointing at `s6target.exe` + AUMID-stamped `.lnk` targeting `s6proxy.exe` + Start-menu entry (gate G0); idempotent, resets state for re-runs |
| [Build-S6Binaries.ps1](Build-S6Binaries.ps1) | Compile the two tools below into `bin\` (`/SUBSYSTEM:WINDOWS`) |
| [src/s6token.h](src/s6token.h) | Shared token inspection (`TokenElevation`, `TokenElevationType`, integrity level) + one-line key=value logging — the runner's automated oracle |
| [src/s6proxy.cpp](src/s6proxy.cpp) | Windowless proxy: guard first (refuses if elevated, **before** the config is opened), else `runas` on the config-resolved target; logs every decision. Exit codes: 0 launched · 1 cancelled · 2 no config · 3 refused · 4 error |
| [src/s6target.cpp](src/s6target.cpp) | Self-reporting target: logs its own token facts (proves the elevation really happened), holds a message box open for taskbar-button observation; unsigned on purpose (UAC naming check) |
