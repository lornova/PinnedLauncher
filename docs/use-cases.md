# Use cases

## Actors

| Actor | Description |
|---|---|
| **User** | The person operating the desktop. Single-user, per-user installation; no admin rights assumed. |
| **Windows shell** | `explorer.exe`: owns the taskbar, notification area, DPI/theme/monitor events. The launcher must coexist with it and react to its lifecycle (crashes, restarts, updates). |
| **Target application** | Any launchable item: Win32 `.exe`, shortcut `.lnk`, packaged/Store app (AUMID), document, folder, or URL. |

## Primary use cases

### UC-1 — Add a launcher
The user adds a target in the management window via one or more of:
- drag-and-drop of an `.exe`/`.lnk`/document onto the window,
- a file picker,
- a picker over installed apps (Start menu entries, including packaged apps).

The launcher is created as a taskbar pin showing the **target's own icon and name**,
with a small **launcher badge** in a corner of the icon (like the shortcut-arrow
overlay) marking it as a launcher rather than a normally pinned app (the user completes
a one-time "Pin to taskbar", see UC-1a). A new launcher can also be started from any
existing launcher's right-click menu (UC-7 → *Add a new launcher…*).

### UC-1a — Pin a launcher (one-time)
No documented API silently pins another app, so the app generates the proxy shortcut
and guides the user through a single native *Pin to taskbar* per launcher (spike S-8
evaluates whether `TaskbarManager`'s consent-gated request APIs can replace the
gesture). Thereafter the pin behaves like any other.

### UC-2 — Launch a target (the core use case)
Single left-click on a launcher icon starts the target exactly as the Start menu would
(correct working directory, AUMID activation for packaged apps, elevation prompt if the
target requires it).

**Invariant:** the launcher pin never changes into, merges with, or gets replaced by
the running application's taskbar button. The running app shows up as its own separate
taskbar button (distinct AUMID); the pin is unaffected.

### UC-3 — Remove a launcher
*Remove* in the management window performs the **unpin first**: programmatically via
[`IStartMenuPinnedList::RemoveFromList`](https://learn.microsoft.com/windows/win32/api/shobjidl/nf-shobjidl-istartmenupinnedlist-removefromlist)
— the documented API for unpinning an application-installed shortcut before deleting
it — **S-4-validated on Windows 11** (pass the Start-menu source `.lnk`; immediate,
isolated, persistent across Explorer restarts; returns S_FALSE on success, so check
`SUCCEEDED(hr)` — [spike report](spikes/s4-pinflow.md) §7). The guided user gesture
remains the fallback if the call fails. Only after the unpin is observed does it
delete the launcher's jump list
(`DeleteList`), proxy shortcut, generated icon and config entry — ordered to avoid
dead pins. If the unpin is deferred, the launcher is marked *pending removal* instead.
(During **full uninstall**, UC-13, the entry is not deleted but transitions to the
terminal `removed` tombstone until the final confirmation.) Unpinning natively without
the app leaves derived artifacts that the management window reconciles at its next
start. No effect on the target application.

### UC-4 — Reorder launchers
Native drag of the pins along the taskbar — the OS handles it; the user places launchers
exactly where they want among the pinned apps.

### UC-5 — Edit launcher properties
Per-launcher: display name, icon override, badge on/off, command-line arguments,
working directory, "run as administrator" flag, "run minimized/maximized" flag.
Reached from the pin's own right-click menu (UC-7 → *Change name or icon…*) or from the
management window. Name/icon changes regenerate the proxy artifacts; because updating
an **existing pin** has no documented API, the flow guides a quick unpin → re-pin
(architecture §4.2; spike S-5, 2026-08-15: no documented propagation mechanism
exists — the guided re-pin is the flow, not a fallback).

### UC-6 — Modified launch
On a launcher-only pin every unmodified click starts the shortcut.
- **Elevated launch** is a per-launcher feature (the run-as-administrator property,
  UC-5, and the jump-list *Run as administrator* task, UC-7; applicable target kinds
  only per the capability matrix). Implementation rule: the **medium-integrity proxy
  invokes the `runas` verb on the resolved target**, so the UAC prompt names the
  actual program being elevated — never the proxy. Verified in spike S-6
  (2026-08-15, [report](spikes/s6-elevation.md)): exactly one UAC prompt naming the
  resolved target (file name for an unsigned target, verified display name for a
  signed one), the target runs at high IL as its own taskbar button, and a declined
  prompt ends in a silent `ERROR_CANCELLED` exit — no error UI, no lingering button.
- The shell's native **Ctrl+Shift+click** on a pin elevates the pin's target — i.e.
  *the proxy itself*. An elevated generic proxy that then executes instructions read
  from user-writable config would be a **confused deputy** (a medium-integrity process
  could rewrite the config between click and UAC consent, running attacker-chosen code
  under a prompt that names our trusted proxy). This path is therefore **not
  supported**: a proxy that finds itself started elevated refuses to consume the
  config and explains how to use the supported elevation instead (behavior and
  detection verified in spike S-6, 2026-08-15: Ctrl+Shift+click, the jump list's own
  *run as administrator* on the entry name — which the shell does offer — and the
  programmatic `runas` verb all yield a full-token high-IL proxy, detected and
  refused before the config is read; [report](spikes/s6-elevation.md)).
- Middle-click / Shift+click are natively equivalent to a plain click on a
  launcher-only pin (they re-launch). Whether a launch yields a *new instance* is
  ultimately the target's decision — single-instance applications will refuse; the
  launcher requests a launch, it cannot guarantee an instance.

An optional **focus-or-launch** proxy behavior (find an existing target window before
launching) is a *Could* refinement, configurable per launcher (UC-10). This section is
the normative source for click semantics; [ui-reference.md](ui-reference.md) is
background only.

### UC-7 — Context menu on a launcher
Right-clicking the pin opens its **Jump List**, which carries launcher-specific tasks
(per-AUMID, available with no process running): *Change name or icon…* (UC-5), *Add a
new launcher…* (UC-1), *Remove this launcher* (UC-3) — always; *Open target's folder*
and *Run as administrator* only for target kinds where they apply (capability matrix,
management-window §5.2). The system entries (launch, *Unpin from taskbar*) remain
below, as on every pin. Mechanism verified in spike S-7 (2026-08-15,
[report](spikes/s7-jumplist.md)): tasks committed for the proxy AUMID before any
pin existed render above the system entries with no process of ours running,
invoke the target with their stored arguments, update on re-commit, and vanish on
`DeleteList`.

## Configuration & lifecycle use cases

### UC-8 — Persistent configuration
Launchers and settings survive logoff/reboot. The config file is the **single source
of truth**; icons, proxy shortcuts and jump lists are derived artifacts regenerated
from it (architecture §4). Export = copy the config file. Import = validated
regeneration: the app shows a **preview** of what will be created (targets, arguments,
elevation flags) before applying, offers replace or merge explicitly, validates paths,
and re-runs the pin guide for entries needing a pin — the pin gestures themselves
cannot be imported, the shell requires the user. In **replace** mode, existing
launchers absent from the imported file are shown in the preview as removals and go
through the standard removal flow (UC-3: unpin first, *pending removal* if deferred) —
never a silent config swap that strands live pins.

### UC-9 — Start with Windows (optional, post-1.0)
The pins work with **no process of ours running** — each is a shortcut that launches
its target, and even the optional focus-or-launch behavior (UC-6) runs in the
**per-click transient proxy**, not in a resident process. A background process exists
only for the optional post-1.0 tray icon (quick settings access); if that is ever
enabled it starts per-user at logon, silently.

### UC-10 — Global settings
Launcher-list management, default launch behavior (plain launch vs the optional
focus-or-launch, per-launcher overridable — UC-6), default badge. The **AUMID scheme
is fixed, not a setting** — changing it would orphan every existing pin and jump list.
Start-with-Windows applies only to the optional tray helper (F-11). Icon size,
spacing, alignment, theme and multi-monitor behavior are **native taskbar settings**
owned by Windows, not by this app.

### UC-11 — Survive shell and environment churn
Because the launchers are native pins, Windows keeps them correctly placed and rendered
across explorer restarts, DPI/scale changes, resolution and monitor changes, taskbar
auto-hide, and alignment changes — no work by this app. What must survive is our own
state: the config file and the proxy shortcuts (and their AUMIDs) stay valid so the pins
keep launching correctly.

### UC-12 — Multi-monitor
Whether pins appear on one taskbar or on every monitor follows the **native** Windows
taskbar multi-monitor setting; this app does not control it.

### UC-13 — Uninstall cleanly
Distribution is a zip, so the uninstall entry point is **in-app**: a *Remove all
launchers…* action walks every launcher through removal (UC-3 — programmatic or guided
unpins, `DeleteList` per AUMID, artifact deletion). Config and any autostart entry are
removed **only once every launcher has completed removal**; launchers whose unpin was
skipped stay *pending* with their config retained, and the closing summary lists them.
During uninstall, each completed launcher transitions to the terminal **`removed`
tombstone** (architecture §4) instead of being deleted from config; tombstones do not
appear in the main list (which therefore empties as removals complete) but are shown
in the **uninstall summary**. Guidance to delete the program folder appears only when
no launcher is in any non-`removed` state **and** the user explicitly confirms, in
that summary, that no launcher pins remain visible on the taskbar — the pinned-copy
watcher is advisory and a false "unpinned" must not be able to authorize the
irreversible step. The tombstoned config is deleted as the very last act, after that
confirmation, so an interrupted uninstall resumes instead of forgetting what was in
flight.

## Secondary / stretch use cases

### UC-14 — Keyboard access
Native pins are already keyboard-operable (e.g. Win+digit launches a pinned app) and
exposed to UI Automation by the shell. Our management window must itself be keyboard- and
screen-reader-accessible. An optional per-launcher global hotkey is a stretch feature.

### UC-15 — Launch groups
One click launches a defined set of targets (e.g. "dev session" = editor + terminal +
browser). Stretch goal; must not complicate the core model.

### UC-16 — Folder / document / URL targets
Launchers may point at folders (opens Explorer), documents (shell-open), or URLs
(default browser). The icon comes from the shell's icon for that item.
