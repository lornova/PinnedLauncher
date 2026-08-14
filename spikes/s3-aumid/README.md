# Spike S-3 scratch artifacts (throwaway)

Scratch code for spike S-3 (implementation-plan P0.1). **Not product code** — kept
only until S-3's outcome is recorded. Protocol, matrix snapshot, and result tables:
[docs/spikes/s3-aumid.md](../../docs/spikes/s3-aumid.md).

| File | Purpose |
|---|---|
| [Build-S3Binaries.ps1](Build-S3Binaries.ps1) | Compile the two scratch exes below into `bin\` (needs a VS C++ toolchain) |
| [src/s3proxy.cpp](src/s3proxy.cpp) | Windowless flavor-B proxy: `s3proxy.exe <target>` ShellExecutes the target and exits |
| [src/s3selfaumid.cpp](src/s3selfaumid.cpp) | Plain Win32 window app that sets its own explicit AUMID (`PinnedLauncher.S3.SelfMarker`) |
| [New-S3Shortcuts.ps1](New-S3Shortcuts.ps1) | Generates the six test `.lnk` (AUMID via `IPropertyStore`, read-back gate G0) and installs Start-menu entries; `-VerifyPins` re-reads the AUMIDs of the live taskbar pin copies (gate G1) |
| [Get-TaskbarIdentity.ps1](Get-TaskbarIdentity.ps1) | Secondary oracle: per-window process image, window-store AUMID, packaged AUMID |
| [Remove-S3Artifacts.ps1](Remove-S3Artifacts.ps1) | Teardown (after manual unpinning) |
