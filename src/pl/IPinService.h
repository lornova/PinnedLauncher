#pragma once

// Q-6 seam over pin lifecycle: docs/design/modules.md §3, §7 (watch contracts);
// pin-flow semantics management-window §5.3; S-4/S-8/S-9 evidence.

#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "Domain.h"
#include "Error.h"

namespace pl {

// What the shell's pinned copy shows (its retained property store, S-9);
// consumed by the UC-8 promotion comparison and the stale-residue check.
struct PinnedCopyInfo {
    std::wstring displayName;
    std::filesystem::path iconPath;
};

enum class PinApiAvailability { Available, Unavailable };
enum class PinRequestOutcome { Pinned, AlreadyPinned, Denied, Unavailable, Failed };

// RAII watch token: destroying it unsubscribes (modules.md §7).
struct WatchSubscription {
    virtual ~WatchSubscription() = default;
};

struct IPinService {
    virtual ~IPinService() = default;

    virtual Result<bool> IsPinPresent(std::wstring_view aumid) = 0;
    // Presence alone never promotes a state; compare these properties (UC-8).
    virtual Result<PinnedCopyInfo> ReadPinnedCopy(std::wstring_view aumid) = 0;
    virtual Result<void> Unpin(const LauncherEntry& entry) = 0;
    [[nodiscard]] virtual std::unique_ptr<WatchSubscription> Watch(
        std::function<void()> onChange) = 0;
    virtual PinApiAvailability ProbeApiAvailability() = 0;
    virtual Result<PinRequestOutcome> RequestPin(std::wstring_view slug) = 0;
};

}  // namespace pl
