#pragma once

// Error model: docs/design/modules.md §6.

#include <expected>
#include <string>

namespace pl {

// Failure domains callers branch on.
enum class ErrorKind {
    ConfigIo,
    ConfigValidation,
    SchemaVersion,
    ShellOperation,
    Launch,
    PinRequest,
    GuardRefusal,
    NotFound,
};

struct Error {
    ErrorKind kind{};
    long hr{};             // HRESULT / Win32 code; 0 when not OS-originated
    std::wstring context;  // technical detail for logs, never a user-facing message
};

template <class T>
using Result = std::expected<T, Error>;

}  // namespace pl
