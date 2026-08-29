// The whole native surface of ai_npc.dll. One class, one function, and that is deliberate.
//
// A `.reds` that declares a native class no loaded plugin registered does not fail
// gracefully. RED4ext validates the compiled script blob against the registered RTTI, after
// every plugin has loaded, and refuses:
//
//   [RED4ext] Script validation error: Missing native class 'RedHttpClient.HttpCallback'
//             at r6\scripts\RedHttpClient\RedHttpClient.reds:70
//
// One line per declared type, and the game does not start -- not the mod, the game. So this
// file is the one place where ai_npc can become the mod that blocks a player's install on a
// patch day, and every type declared here is one more line in that error. The risk is
// accepted for this version (see docs/ARCHITECTURE.md, "What the plugin costs on a patch day",
// which also records the file-based transport that removes it); being stingy here is what keeps
// it small.
//
// Which is why the reply does NOT come back through a registered callback type, the way
// RedHttpClient's HttpCallback does. That would be a second native class for no gain: the
// plugin calls the plain redscript function AiNpcCliDeliver instead. See AiNpcCliRequest.
//
// The RTTI name is module-qualified -- this registers as `AiNpc.AiNpcCli`. Verified rather
// than assumed: the string "RedHttpClient.AsyncHttpClient" is present verbatim in
// RedHttpClient.dll, and the validation error above prints the same qualified form.

module AiNpc

public native class AiNpcCli {
    // Starts one CLI generation. Returns immediately; the answer arrives at
    // AiNpcCliDeliver, on the game thread, carrying this same requestId.
    //
    // `provider` is the display name of the lane ("ClaudeCli", "CodexCli") -- the plugin
    // matches it and answers with a typed error when it does not, rather than picking a
    // default. A backend chosen silently would be indistinguishable from a working mod.
    //
    // `body` is the OpenAI-shaped chat/completions body, byte for byte what the HTTP lane
    // would have posted. The plugin splits the system and user messages itself, because
    // where the system block goes is a per-backend decision -- Claude has --system-prompt,
    // Codex has to fold it into the input -- and that decision settles the instruction
    // hierarchy the safe-for-work tier depends on. Pre-concatenating them in script would
    // move that decision into the wrong layer.
    //
    // False means the request was refused before anything was spawned, and nothing will be
    // delivered for this id.
    public static native func Send(provider: String, body: String, requestId: Int32) -> Bool;
}
