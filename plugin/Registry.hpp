#pragma once

#include <string>

#include "Transport.hpp"

namespace ainpc
{
// The backend script asked for, or null.
//
// NULL IS AN ANSWER, and it is the only correct one for a name this build does not know.
// The plugin never picks a default: a settings bug that silently ran the wrong backend would
// be indistinguishable from a working mod, and the player would be paying -- or not paying --
// for something other than what the menu says.
const ITransport* Find(const std::string& aProviderName);

// Why there is no backend for that name, phrased for the player rather than for a log.
std::string ExplainUnknown(const std::string& aProviderName);
} // namespace ainpc
