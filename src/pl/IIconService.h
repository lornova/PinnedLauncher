#pragma once

// Q-6 seam over icon generation: docs/design/modules.md §3; stable-path rule
// in docs/design/config-schema.md §6.

#include <cstdint>
#include <filesystem>
#include <span>
#include <string_view>

#include "Domain.h"
#include "Error.h"

namespace pl {

struct IIconService {
    virtual ~IIconService() = default;

    // Composes and writes icons\<slug>.ico in place; the path never changes (S-5).
    virtual Result<std::filesystem::path> EnsureIcon(const LauncherEntry& entry) = 0;
    virtual Result<std::filesystem::path> Preview(const LauncherEntry& entry,
                                                  std::span<const std::uint32_t> sizes) = 0;
    virtual Result<void> Delete(std::wstring_view slug) = 0;
};

}  // namespace pl
