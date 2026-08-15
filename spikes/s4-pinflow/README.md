# Spike S-4 scratch artifacts (throwaway)

Scratch code for spike S-4 (pin/unpin lifecycle, implementation-plan P0.2).
**Not product code.** Protocol and results:
[docs/spikes/s4-pinflow.md](../../docs/spikes/s4-pinflow.md).

| File | Purpose |
|---|---|
| [Invoke-S4Protocol.ps1](Invoke-S4Protocol.ps1) | **Guided protocol runner** — automates measurements, pauses per human gesture, writes `results\*.json` |
| [Build-S4Binaries.ps1](Build-S4Binaries.ps1) | Compile the two console tools below into `bin\` |
| [src/s4unpin.cpp](src/s4unpin.cpp) | `s4unpin.exe <lnk path>` — `IStartMenuPinnedList::RemoveFromList` probe (programmatic unpin, UC-3) |
| [src/s4select.cpp](src/s4select.cpp) | `s4select.exe <AUMID or path>` — `SHOpenFolderAndSelectItems` deep-link probe for the pin guide |
| [New-S4Shortcuts.ps1](New-S4Shortcuts.ps1) | Generates the two S4 test `.lnk` (AUMID-stamped, gate G0) + Start-menu entries |
| [Watch-PinFolder.ps1](Watch-PinFolder.ps1) | Live timestamped watcher on `User Pinned\TaskBar` (run in its own terminal) |
| [Get-TaskbandPins.ps1](Get-TaskbandPins.ps1) | Snapshot comparison: pin-folder heuristic vs Taskband `Favorites` registry blob |
