#pragma once

// Q-6 seam over config I/O: docs/design/config-schema.md; docs/design/modules.md §3.

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

#include "Domain.h"
#include "Error.h"

namespace pl {

// One flagged problem from a load (config-schema §7.2). Flagged entries are
// addressed by array position; raw preservation of flagged/unknown content is
// the store's internal state, carried into the next write.
struct ConfigDiagnostic {
    std::size_t position{};  // index in the launchers array
    std::wstring slug;       // empty when the entry has no usable slug
    std::wstring detail;     // technical detail; the UI maps kinds to localized text
};

struct ConfigLoadResult {
    ConfigDocument document;  // settings + the valid entries
    std::vector<ConfigDiagnostic> diagnostics;
};

struct IConfigStore {
    virtual ~IConfigStore() = default;

    virtual Result<ConfigLoadResult> Load() = 0;
    virtual Result<void> Replace(const ConfigDocument& document) = 0;
    // Atomic read-modify-write of a single entry (config-schema §5.3).
    virtual Result<void> UpdateEntry(std::wstring_view slug,
                                     const std::function<void(LauncherEntry&)>& mutate) = 0;
};

}  // namespace pl
