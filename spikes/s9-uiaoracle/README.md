# Spike S-9 scratch artifacts (throwaway)

Scratch code for spike S-9 (UIA test oracle + test-environment hygiene,
implementation-plan P0.2). **Not product code.** Protocol and results:
[docs/spikes/s9-uiaoracle.md](../../docs/spikes/s9-uiaoracle.md).

| File | Purpose |
|---|---|
| [Invoke-S9Protocol.ps1](Invoke-S9Protocol.ps1) | **Guided protocol runner** — automates the hygiene sweep, UIA dumps with parsed baseline comparisons, the same-named-target launch/close, and the programmatic teardown; human steps shrink to the pin gesture + two visual confirmations; writes `results\*.json` |
| [S9Common.ps1](S9Common.ps1) | Shared paths + interop, dot-sourced by the other scripts: shortcut factory (S-4..S-7's), independent AUMID reader (gate G0 + sweep), UIA element-line parser |
| [New-S9Shortcuts.ps1](New-S9Shortcuts.ps1) | Test-article generator: AUMID-stamped `.lnk` (display name == target window title — the collision; targets charmap, never clicked, to avoid S-3's flavor-A merge) + Start-menu entry (gate G0) |
| [Build-S9Binaries.ps1](Build-S9Binaries.ps1) | Compile the two tools below into `bin\` |
| [src/s9uia.cpp](src/s9uia.cpp) | Console UIA walker (`IUIAutomation` — the same API the ADR-0009 harness helper will use): dumps taskbar elements as parseable `key="value"` lines, optional substring filter |
| [src/s9target.cpp](src/s9target.cpp) | Real windowed app with a command-line-controlled title — its running button carries exactly the pin's display name |
