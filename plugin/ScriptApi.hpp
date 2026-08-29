#pragma once

#include <string>

#include <RED4ext/Api/v1/PluginHandle.hpp>

namespace RED4ext::v1
{
struct Sdk;
} // namespace RED4ext::v1

namespace ainpc::script
{
// Called once from the plugin's Load. Registers the RTTI surface, starts the worker thread,
// and installs the game-thread tick that delivers answers back to redscript.
void Start(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk, const std::wstring& aPluginDirectory,
           void* aJob);

// Called from Unload. Stops the worker and abandons whatever it was holding: a reply nobody
// can be told about is not worth waiting for while the game is closing.
void Stop();
} // namespace ainpc::script
