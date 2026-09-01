// The menu, and only the menu: the ten answers Mod Settings binds to.
//
// A class of its own because these fields ARE a surface. Mod Settings finds them by scanning
// RTTI and persists them under this class's qualified name, so they are read and written by
// something outside the mod -- and welding that surface to the phone chat's model made a
// 900-line service that answers for the phone also answer for the daily token budget.
//
// A ScriptableService and not a system, which is the lifetime the fields already had and must
// keep: an accessor here answers before a save is loaded, and AiNpcUtilities depends on it.
// The compaction lane and the config loader both run before the first session, and a budget
// reading zero because the menu had not attached would refuse a request against a ceiling
// nobody set.
//
// NOTHING READS THESE FIELDS DIRECTLY, this mod included. AiNpcUtilities names each question
// and answers it with the field's own default while the service is not up; tools\lint.ps1
// keeps it that way. The fields give the menu somewhere to write; the accessors are what makes
// the not-yet case impossible to get wrong at a call site.
//
// THE CLASS NAME IS THE STORAGE KEY. Mod Settings persists to mod_settings\user.ini under
// [AiNpc.<class>], so renaming this class silently returns every player to the defaults. Moved
// off AiNpcSystem before 1.0.0 for that reason alone: after a release the section name is a
// compatibility promise, and this is the last moment the move costs one re-entry instead of
// everybody's.

module AiNpc

public class AiNpcSettingsService extends ScriptableService {

    // Registered here rather than at a spawn: the menu exists before a save is loaded, and the
    // previous home did this inside a per-spawn initialisation -- so the listener was attached
    // again on every load, and not at all until the player had spawned once.
    private cb func OnInitialize() {
        ModSettings.RegisterListenerToClass(this);
    }

    public static func Get() -> ref<AiNpcSettingsService> {
        return GameInstance.GetScriptableServiceContainer().GetService(NameOf<AiNpcSettingsService>()) as AiNpcSettingsService;
    }

    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "1")
    // The CLI lanes are named for what they are for, because this dropdown is the one route
    // into them the installer cannot gate. The warning says the plans assume ordinary
    // individual use; it does not say the licence forbids it, which would be false -- an end
    // user may sign in to the unmodified binary ai_npc.dll drives. See docs\DISTRIBUTION.md.
    @runtimeProperty("ModSettings.displayName", "Model")
    @runtimeProperty("ModSettings.description", "Which AI service generates the replies. OpenRouter is the supported way to play; the streamed entry is the same service and the same key, read as it is written so a voice can start speaking sooner. The two CLI lanes are for mod authors testing their own work: playing through a coding-agent subscription is outside what those plans are sold for, and the provider may limit or suspend your account without warning.")
    @runtimeProperty("ModSettings.displayValues.OpenRouter", "OpenRouter (API key) - supported")
    @runtimeProperty("ModSettings.displayValues.ClaudeCli", "Claude CLI - mod authors only")
    @runtimeProperty("ModSettings.displayValues.CodexCli", "Codex CLI - mod authors only")
    public let aiModel: AiNpcProvider = AiNpcProvider.OpenRouter;

    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Conversation Type")
    @runtimeProperty("ModSettings.description", "How explicit the replies may get.")
    @runtimeProperty("ModSettings.displayValues.Normal", "Normal (Safe for Work)")
    @runtimeProperty("ModSettings.displayValues.NSFW", "NSFW (Romance/Intimacy)")
    @runtimeProperty("ModSettings.displayValues.NSFW_Hard", "NSFW Hard (Explicit/Uncensored)")
    public let conversationType: AiNpcConversationType = AiNpcConversationType.Normal;

    // Whether a command nobody could read is worth a second request. A model that drops the
    // verb -- "[ACTION:KABUKI_SF:2200:1000:1]" -- writes something no parser can route, and
    // the bracket reaches the player's bubble. Measured on gpt-oss-120b: twice in nine tries.
    //
    // Off by default because a repair is a second billed request. When on, it sends the
    // command vocabulary and the broken tag, not the conversation -- see
    // AiNpcHttpSystem.RepairPostRequest.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "1")
    // Named for what the player buys -- a retry, billed like any other request -- not for the
    // repair that follows it.
    @runtimeProperty("ModSettings.displayName", "Retry Broken Commands")
    // No example tag in the description: tools/lint.ps1 checks that the commands named in any
    // prompt literal are ones the parser accepts, and a specimen is indistinguishable from a
    // command the mod really offers.
    @runtimeProperty("ModSettings.description", "Some replies end on a command the game cannot read, which the player sees as a raw bracketed command in the message. Sends one short extra request asking the character to write that command again. The message itself is kept as written.")
    public let retryActions: Bool = false;

    // Above "Retry Broken Commands" in effect, not in the list: Dedicated makes that setting
    // moot, because a reply written without the command vocabulary has no bracket to fumble.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Command Handling")
    @runtimeProperty("ModSettings.description", "How a character's actions reach the game. Embedded is how the mod has always worked: the list of commands is part of the conversation, the character writes one inside its reply, and the mod takes it out again before you read the message. Dedicated sends a second, much smaller request after each reply, which sees only the commands and the last few messages -- so the character writes plainly and never has to remember a syntax. It costs one extra request per reply and nothing has been measured about it yet.")
    @runtimeProperty("ModSettings.displayValues.Embedded", "Embedded in the conversation (default)")
    @runtimeProperty("ModSettings.displayValues.Dedicated", "Dedicated request per reply")
    public let actionMode: AiNpcActionMode = AiNpcActionMode.Embedded;

    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Enable Logs")
    @runtimeProperty("ModSettings.description", "Writes this mod's activity to the CET console, including one line per request with its size and what the provider says it cost. No conversation text is written. Errors are logged either way.")
    public let logging: Bool = false;

    // The second message a failure sends -- provider, url and cause -- shown in the chat.
    // Separate from "Enable Logs": that one decides whether AiNpcLog reaches the CET console,
    // this one whether the cause is put in front of the player, and turning on console
    // logging should not start writing into V's phone.
    //
    // It also gates the full request and response dumps, which carry the whole prompt and the
    // player's own words. Enable Logs writes metadata only, safe to paste into a bug report.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Debug Mode")
    @runtimeProperty("ModSettings.description", "When a reply fails, adds a second chat message naming the provider, url and error. Also dumps each request and reply in full to the log, which then contains the conversation.")
    public let debugMode: Bool = false;

    // Its own category because it costs something on every message: the memory block sits
    // after the cacheable prefix, so every fact in it is paid for at every turn.
    //
    // Off is not "no memory" but the pre-memory behaviour -- the window is hard-trimmed to the
    // last twenty turns. Nothing is destroyed either way: the setting decides what goes in the
    // prompt, never what is stored. Long version in docs\MEMORY.md.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "Memory")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Remember Conversations")
    @runtimeProperty("ModSettings.description", "Characters remember a conversation beyond its last few messages. Off keeps only the last 20 turns.")
    public let memoryEnabled: Bool = true;

    // The two directions are not symmetric: raising it costs tokens from now on, lowering it
    // evicts the facts that no longer fit at the next compaction. The description states the
    // forgetting only -- a warning about the harmless direction makes the real one easier to
    // skip. Bounds and default are measured in AiNpcMemoryMaxFacts.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "Memory")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Facts Remembered")
    @runtimeProperty("ModSettings.description", "How many facts a character keeps in mind. Lowering it makes them forget the oldest ones.")
    @runtimeProperty("ModSettings.step", "4")
    @runtimeProperty("ModSettings.min", "8")
    @runtimeProperty("ModSettings.max", "40")
    @runtimeProperty("ModSettings.dependency", "memoryEnabled")
    public let memoryFacts: Int32 = 20;

    // Off by default: a cap the player did not ask for turns into a character who stops
    // answering for a reason nothing on screen explains. See docs\TOKEN_BUDGET.md.
    //
    // "Day" is the provider's UTC day, read from the Date header of its answers -- the clock
    // its quota resets on, and the only real one redscript can reach. The tally lives in
    // r6\storages\AiNpc\usage.json, outside the savegame, so it covers every save at once.
    // Every request counts against it whatever the backend.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "Budget")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Daily Token Limit")
    @runtimeProperty("ModSettings.description", "Stops sending once the day's tokens are spent, and says so in the chat. Off means no limit. The count covers every save and resets on the provider's own day.")
    public let dailyLimitEnabled: Bool = false;

    // In thousands: Mod Settings expresses Int32, and a step of 1 across 200000 is not a
    // usable slider. 200 is the free tier measured on Groq, about 40 messages a day. The
    // bounds are the range AiNpcClampDailyBudget enforces; if they drift, the menu is lying.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "Budget")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Tokens Per Day (thousands)")
    @runtimeProperty("ModSettings.description", "How many thousand tokens a day the mod may spend. One message costs about 5000, so 200 is roughly 40 messages.")
    @runtimeProperty("ModSettings.step", "10")
    @runtimeProperty("ModSettings.min", "10")
    @runtimeProperty("ModSettings.max", "1000")
    @runtimeProperty("ModSettings.dependency", "dailyLimitEnabled")
    public let dailyTokens: Int32 = 200;

    // In Budget because that is the question it is: an unprompted message spends a request the
    // player never typed, counted against the ceiling above like any other.
    //
    // On by default. Off would make the feature invisible on every install, and the author of
    // the mod using it would collect "your mod does nothing" reports for a switch buried in
    // somebody else's menu. Nothing reaches this setting unless a third-party mod asks.
    @runtimeProperty("ModSettings.mod", "AI NPC")
    @runtimeProperty("ModSettings.category", "Budget")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Characters May Write First")
    @runtimeProperty("ModSettings.description", "Lets other installed mods have a character text you unprompted, for a reason they give. Off means characters only ever answer.")
    public let unpromptedEnabled: Bool = true;
}
