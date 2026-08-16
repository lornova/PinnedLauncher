#pragma once

// Q-6 seam over the process token: the ADR-0011 guard predicate input
// (refuse iff Full); placement rules in docs/design/cli.md §5.

#include "Error.h"

namespace pl {

enum class TokenElevation { Default, Limited, Full };

struct ITokenInfo {
    virtual ~ITokenInfo() = default;

    // Callers treat a failed query as Full (fail closed, cli.md §5): no error
    // path may bypass the guard.
    virtual Result<TokenElevation> QueryElevationType() const = 0;
};

}  // namespace pl
