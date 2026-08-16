#pragma once

// Domain model: docs/design/config-schema.md §3-§5, docs/design/modules.md §2.
// Field semantics, presence rules, and validation live in config-schema.md;
// unknown-key preservation is the config store's DOM-level concern, not this
// model's.

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace pl {

enum class TargetKind { Exe, Packaged, Document, Folder, Url };
enum class WindowState { Normal, Minimized, Maximized };
enum class LifecycleState {
    AwaitingPin,
    Active,
    AwaitingRepin,
    PendingRemoval,
    Removing,
    Removed,
};
enum class RemovalKind { Normal, Uninstall };
enum class RemovalOrigin { AwaitingPin, Active, AwaitingRepin };
enum class PinFlowMode { ApiFirst, ApiOnly, Manual };
enum class BadgeCorner { TopLeft, TopRight, BottomLeft, BottomRight };

struct TargetDescriptor {
    TargetKind kind{};
    std::filesystem::path path;  // exe / document / folder kinds
    std::wstring aumid;          // packaged kind: the target's own AUMID
    std::wstring url;            // url kind
};

struct LauncherEntry {
    std::wstring slug;  // immutable identity (docs/design/aumid-scheme.md §3)
    std::wstring displayName;
    TargetDescriptor target;
    std::wstring arguments;
    std::filesystem::path workingDirectory;
    bool elevate{false};
    // Absent is distinct from an explicit Normal: absent inherits a .lnk
    // target's stored show state (config-schema §5.1), Normal overrides it.
    std::optional<WindowState> windowState;
    std::filesystem::path iconOverride;
    std::optional<bool> badge;  // unset = inherit Settings::badgeDefault
    std::wstring aumid;         // generated, stored (config-schema §5)
    std::filesystem::path proxyLnkPath;
    LifecycleState state{LifecycleState::AwaitingPin};
    std::optional<RemovalOrigin> removalOrigin;  // present iff state is a removal state
    std::optional<RemovalKind> removalKind;      // same presence rule
};

struct Settings {
    PinFlowMode pinFlowMode{PinFlowMode::ApiFirst};
    bool badgeDefault{true};
    BadgeCorner badgeCorner{BadgeCorner::BottomLeft};
    std::wstring language;  // empty = follow Windows; BCP-47 otherwise
};

struct ConfigDocument {
    int schemaVersion{1};
    Settings settings;
    std::vector<LauncherEntry> launchers;
};

}  // namespace pl
