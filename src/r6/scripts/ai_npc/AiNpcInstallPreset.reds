module AiNpc

// What the installer was told, carried into the game.
//
// This file is the FOMOD's only foothold in the mod. A Nexus installer can do exactly one
// thing -- decide which files are copied -- so a choice made in it has to be carried by a
// file, and this is that file: package.ps1 emits one variant of it per provider under
// presets\ in the archive, and the installer copies the chosen one over this default. Install
// manually, or through a mod manager that ignores the FOMOD, and the default below is what
// stays: no preset, nothing applied, the mod behaves exactly as it always has.
//
// It is a default, not a setting. AiNpcSetupSystem applies it once (see ApplyInstallPreset)
// and records that it did, so a player who changes provider afterwards is never overruled by
// their own installer choice from three weeks ago.
func AiNpcInstallPresetProvider() -> String {
    return "";
}

// The OpenRouter model to start on, or "" to leave the shipped default alone.
//
// Second question, same foothold. One provider covers three answers a player can only give at
// install time -- free, and two paid models an order of magnitude apart in price -- and the
// difference between them is a string in settings.json, not a code path.
//
// Named for its lane rather than left generic: OpenRouter is the only provider whose model the
// installer picks, the CLI lanes take theirs from an alias, and one function writing "the
// model" into whichever setting the provider happens to use is a mapping waiting to be wrong.
func AiNpcInstallPresetOpenRouterModel() -> String {
    return "";
}

// Whether characters may write first: "on", "off", or "" to leave the shipped default alone.
//
// It follows the model rather than the provider. A character writing first spends a request
// nobody asked for, and on a free model a request that is refused is not a cost but a silence:
// the popup never comes, and nothing anywhere says why. The setting is on by default because
// the feature would otherwise be invisible on every install -- that reasoning holds for a
// model that answers, and the free lane is the one place it does not.
//
// A string and not a Bool, so the three answers stay distinguishable. A preset that says
// nothing must not read as a preset that says "off".
func AiNpcInstallPresetUnprompted() -> String {
    return "";
}
