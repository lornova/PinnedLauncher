#pragma once

// Q-6 seam over the proxy .lnk + AUMID stamp: docs/design/modules.md §3;
// artifact naming in docs/design/aumid-scheme.md §4.

#include <filesystem>
#include <vector>

#include "Domain.h"
#include "Error.h"

namespace pl {

struct IShortcutManager {
    virtual ~IShortcutManager() = default;

    virtual Result<std::filesystem::path> WriteProxyShortcut(const LauncherEntry& entry) = 0;
    // Path form: a rename deletes the old .lnk, reconciliation cleans orphans.
    virtual Result<void> RemoveShortcut(const std::filesystem::path& lnkPath) = 0;
    // Every .lnk in our Start-menu folder: the reconciler's orphan scan.
    virtual Result<std::vector<std::filesystem::path>> ListProxyShortcuts() = 0;
};

}  // namespace pl
