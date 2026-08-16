#pragma once

// Q-6 seam over shell:AppsFolder: docs/design/modules.md §3; picker source per
// the AppsFolder enumeration check; deep link and indexing poll per S-4/S-6.

#include <string>
#include <string_view>
#include <vector>

#include "Error.h"

namespace pl {

struct AppsFolderEntry {
    std::wstring displayName;
    std::wstring parseName;  // AUMID-shaped, or a raw path for some Win32 entries
    bool packaged{false};
};

struct IAppsFolder {
    virtual ~IAppsFolder() = default;

    virtual Result<std::vector<AppsFolderEntry>> Enumerate() = 0;
    virtual Result<bool> IsIndexed(std::wstring_view aumid) = 0;
    virtual Result<void> RevealInAppsView(std::wstring_view aumid) = 0;
};

}  // namespace pl
