#pragma once

// Q-6 seam over jump-list publication: docs/design/modules.md §3;
// task content in architecture §4.1.

#include <string_view>

#include "Domain.h"
#include "Error.h"

namespace pl {

struct IJumpListPublisher {
    virtual ~IJumpListPublisher() = default;

    virtual Result<void> Commit(const LauncherEntry& entry) = 0;
    virtual Result<void> Delete(std::wstring_view aumid) = 0;
};

}  // namespace pl
