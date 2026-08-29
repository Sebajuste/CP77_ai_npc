// Provider name to backend, and the named error when there is no match.
//
// The names are a contract with redscript, not labels: AiNpcProviderName in AiNpcLlm.reds
// produces exactly these strings and AiNpcTests asserts them. Renaming one is a change on
// both sides in the same commit, and its failure mode is a lane that stops working with a
// message that names the cause -- which is the best a rename can hope for.

#include "Registry.hpp"

#include "ClaudeCli.hpp"
#include "CodexCli.hpp"

namespace ainpc
{
namespace
{
const ClaudeCli& Claude()
{
    static const ClaudeCli backend;
    return backend;
}

const CodexCli& Codex()
{
    static const CodexCli backend;
    return backend;
}
} // namespace

const ITransport* Find(const std::string& aProviderName)
{
    if (aProviderName == "ClaudeCli")
    {
        return &Claude();
    }
    if (aProviderName == "CodexCli")
    {
        return &Codex();
    }

    return nullptr;
}

std::string ExplainUnknown(const std::string& aProviderName)
{
    if (aProviderName.empty())
    {
        return "no provider was named - this is a bug in the mod, please report it";
    }
    return "'" + aProviderName + "' is not a provider this build knows - choose another one in Mod Settings";
}
} // namespace ainpc
