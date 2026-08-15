# Spike S-5 scratch artifacts (throwaway)

Scratch code for spike S-5 (pin-edit propagation, implementation-plan P0.2).
**Not product code.** Protocol and results:
[docs/spikes/s5-editprop.md](../../docs/spikes/s5-editprop.md).

| File | Purpose |
|---|---|
| [Invoke-S5Protocol.ps1](Invoke-S5Protocol.ps1) | **Guided protocol runner** — automates icon rewrites, notify rungs, and shortcut edits; states what to watch before each observable step; writes `results\*.json` |
| [S5Common.ps1](S5Common.ps1) | Shared paths + interop, dot-sourced by the other scripts: shortcut factory (S-4's), `IPersistFile`-based icon-location editor, dependency-free two-variant ICO writer |
| [New-S5Shortcuts.ps1](New-S5Shortcuts.ps1) | Test-article generator: variant-A badged icon at its stable path + AUMID-stamped `.lnk` + Start-menu entry (gate G0); idempotent, resets state for re-runs |
| [Build-S5Binaries.ps1](Build-S5Binaries.ps1) | Compile the console tool below into `bin\` |
| [src/s5notify.cpp](src/s5notify.cpp) | `s5notify.exe <verb> …` — exactly one `SHChangeNotify` per invocation (`updateitem`/`updatedir`/`renameitem`/`updateimage`/`assocchanged`), so the escalation ladder climbs one rung at a time |
