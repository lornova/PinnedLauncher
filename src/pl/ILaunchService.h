#pragma once

// Q-6 seam over target launch: docs/design/modules.md §3; semantics UC-6
// (normative) and docs/design/cli.md §3.1.

#include "Domain.h"
#include "Error.h"

namespace pl {

enum class ForceElevation { No, Yes };  // Yes = the --launch --elevated jump-list task

struct ILaunchService {
    virtual ~ILaunchService() = default;

    virtual Result<void> Launch(const LauncherEntry& entry, ForceElevation force) = 0;
    virtual Result<void> OpenLocation(const LauncherEntry& entry) = 0;
};

}  // namespace pl
