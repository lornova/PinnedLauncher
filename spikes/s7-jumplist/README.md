# Spike S-7 scratch artifacts (throwaway)

Scratch code for spike S-7 (jump-list tasks on a proxy AUMID,
implementation-plan P0.2). **Not product code.** Protocol and results:
[docs/spikes/s7-jumplist.md](../../docs/spikes/s7-jumplist.md).

| File | Purpose |
|---|---|
| [Invoke-S7Protocol.ps1](Invoke-S7Protocol.ps1) | **Guided protocol runner** — automates every `ICustomDestinationList` call, the AppsFolder indexing poll (S-6 finding), the no-process check, and log polling with automatic expectation checks; states what to watch before each observable step; writes `results\*.json` |
| [S7Common.ps1](S7Common.ps1) | Shared paths + interop, dot-sourced by the other scripts: shortcut factory (S-4..S-6's), independent AUMID reader (gate G0), key=value log parsing |
| [New-S7Shortcuts.ps1](New-S7Shortcuts.ps1) | Test-article generator: AUMID-stamped `.lnk` targeting `s7taskecho.exe` + Start-menu entry (gate G0); idempotent |
| [Build-S7Binaries.ps1](Build-S7Binaries.ps1) | Compile the two tools below into `bin\` |
| [src/s7jumplist.cpp](src/s7jumplist.cpp) | Console tool around `ICustomDestinationList`: `commit` (3 tasks + separator), `commit2` (edited list — rename + drops), `delete` (`DeleteList`); one HRESULT per API step |
| [src/s7taskecho.cpp](src/s7taskecho.cpp) | Windowless task target: logs its argv to `out\s7-task-log.txt` — the Q2 oracle proving a clicked task invoked our exe with the stored arguments |
