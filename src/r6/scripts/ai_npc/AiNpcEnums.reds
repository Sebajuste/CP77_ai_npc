// Every enum the mod declares, in one place.
//
// Together because their VALUES are a compatibility surface, and that is easy to forget when
// an enum sits at the bottom of the file that happens to use it. Mod Settings persists the
// integer, not the name, so inserting a member in the middle silently reassigns what a
// player already chose -- which is why Auto and External are numbered far away from the real
// members rather than appended. tools/lint.ps1 additionally checks that every member of an
// enum the settings menu exposes has a displayValue, since one without is simply blank in
// the menu.

module AiNpc

enum AiNpcConversationType {
    Normal = 0,
    NSFW = 1,
    NSFW_Hard = 2
}

// Read from the character the player created, never from a setting: the game already
// knows the answer, and a menu that can disagree with the body is a menu that can be wrong.
enum AiNpcGender {
    Male = 0,
    Female = 1
}

// Three lanes, and only the first speaks HTTP. Numbered contiguously: a hole would mean a
// persisted setting that reads as a provider nobody can select.
enum AiNpcProvider {
    OpenRouter = 0,
    ClaudeCli = 1,
    CodexCli = 2
}

// Where the choice of a command is made. Embedded is what the mod has always done and stays
// the default; Dedicated moves it to a request of its own -- see AiNpcActionService.
enum AiNpcActionMode {
    Embedded = 0,
    Dedicated = 1
}

enum AiNpcLanguage {
    English = 0,
    Spanish = 1,
    French = 2,
    German = 3,
    Italian = 4,
    Portuguese = 5,
    Russian = 6,
    Ukraine = 7
}
