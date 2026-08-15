# Spike S-8 scratch artifacts (throwaway)

Scratch code for spike S-8 (`TaskbarManager` pin-API evaluation,
implementation-plan P0.2). **Not product code.** Protocol and results:
[docs/spikes/s8-pinapi.md](../../docs/spikes/s8-pinapi.md).

| File | Purpose |
|---|---|
| [Invoke-S8Protocol.ps1](Invoke-S8Protocol.ps1) | **Guided protocol runner** — automates the hygiene sweep, the windowless support/LAF probes, the three pin routes via `s8pin.exe`, and the S-4 + S-9 equivalence checks on any pin that lands; human steps shrink to answering the consent dialogs and a few visual confirmations; writes `results\*.json` |
| [S8Common.ps1](S8Common.ps1) | Shared paths + interop, dot-sourced by the other scripts: shortcut factory (S-4..S-9's), independent AUMID reader (gate G0 + sweep + equivalence), parsers for `s9uia` element lines and `s8pin` fact lines |
| [New-S8Shortcuts.ps1](New-S8Shortcuts.ps1) | Test-article generator: AUMID-stamped `.lnk` (targets charmap — a real, harmless target for the click-equivalence step) + Start-menu entry (gate G0) |
| [Build-S8Binaries.ps1](Build-S8Binaries.ps1) | Compile the tool below into `bin\` |
| [src/s8pin.cpp](src/s8pin.cpp) | C++/WinRT host for the unpackaged-caller evaluation: sets the process-explicit AUMID first, then one subcommand per route — `probe` (marker interface, `IsPinningAllowed`, LAF registry probe + `TryUnlockFeature`), `pin-current`, `pin-entry`, `pin-tile` — printing parseable `s8 key="value"` lines |

Reused from earlier spikes: `..\s9-uiaoracle\bin\s9uia.exe` (the UIA oracle)
and `..\s4-pinflow\bin\s4unpin.exe` (programmatic unpin).
