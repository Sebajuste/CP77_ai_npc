// The quest-fact bridge: how a mod that has never heard of ai_npc makes a character react.
//
// Every other way in needs the other side to opt in -- a characters.<mod>.json file, or a
// provider compiled against `module AiNpc` -- which leaves out the content that would benefit
// most: the quest mods already installed, whose authors have no reason to know this exists.
//
// Quest facts are the one channel both sides already speak. A quest graph cannot call
// redscript and redscript cannot add a node to a baked graph, but both read and write the
// FactsDB, so a watch declared in a JSON file turns "their fact changed" into "the character
// is told something happened", in that mod's own words.
//
// What arrives is CONTEXT, never a line of dialogue: the event is seeded for the named
// contacts (AiNpcSetPendingContext) and each reacts in its own voice the next time
// V texts it, so an event raised while the phone is away waits for the player instead of
// being spoken into an empty room.
//
// The split with the rest:
//   AiNpcConfig.reds        reads and validates facts.*.json  -> array<AiNpcFactWatch>
//   AiNpcFactEvent.reds     what the character is actually told (pure, like its siblings)
//   here                    when it is told: listeners, thresholds, acknowledgements

module AiNpc

/// The rule ///

// Whether a fact reaching `current` is news.
//
// A watch fires on the CROSSING, not on the value: a fact already past the threshold has
// nothing new to say, however many times it is written again. `atLeast: 3` fires on the third
// and stays quiet on the fortieth, and a mod that rewrites its facts on every load does not
// make a character bring the same news up forever.
//
// The pair to it is the baseline: a watch starts from what the fact ALREADY reads when the
// session opens, so a quest completed three saves ago is not news either.
func AiNpcFactCrossed(previous: Int32, current: Int32, atLeast: Int32) -> Bool {
    return current >= atLeast && previous < atLeast;
}

/// One live watch ///

// A watch is its own listener object, forced by the engine rather than chosen: QuestsSystem
// addresses a listener by (fact, object, method) and hands the callback nothing but the new
// value, so one object for every watch would receive "7" with no way to ask which fact said
// it.
public class AiNpcFactWatcher extends IScriptable {
    public let watch: ref<AiNpcFactWatch>;
    public let bridge: wref<AiNpcFactBridge>;
    public let fact: CName;
    public let listenerId: Uint32;

    // What the fact read when this watch was registered, then what it read last time it
    // spoke. Session-scoped on purpose -- see AiNpcFactCrossed.
    public let previous: Int32;

    private cb func OnFactChanged(value: Int32) {
        let before = this.previous;
        // Written before the decision and on every path: a watch that forgets to move its
        // baseline fires on every subsequent write of the same value.
        this.previous = value;

        if IsDefined(this.bridge) && AiNpcFactCrossed(before, value, this.watch.atLeast) {
            this.bridge.OnWatchFired(this.watch, value);
        }
    }
}

// One acknowledgement still owed. See AiNpcFactBridge.NotifyReply for what it means.
public class AiNpcFactAck {
    public let contactId: String;
    public let fact: CName;
}

/// The bridge ///

public class AiNpcFactBridge extends ScriptableSystem {

    // Set to 1 at every session start, so a quest graph can offer a texting-based path only
    // where there is something to text. It is a capability flag, not a liveness one: facts
    // live in the savegame and nothing clears this if the mod is later removed, so gate a
    // branch on it -- never a loop waiting for it to drop.
    private const let PRESENCE_FACT: CName = n"ai_npc_installed";

    private let m_watchers: array<ref<AiNpcFactWatcher>>;
    private let m_awaiting: array<ref<AiNpcFactAck>>;

    public static func Get() -> ref<AiNpcFactBridge> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(NameOf<AiNpcFactBridge>()) as AiNpcFactBridge;
    }

    /// Lifecycle ///

    // On player attach rather than on system attach: the FactsDB is restored with the save,
    // and a baseline read before that would be a baseline of the previous session's world.
    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
        this.Register(GameInstance.GetQuestsSystem(request.owner.GetGame()));
    }

    private func OnDetach() -> Void {
        let quests = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if IsDefined(quests) {
            let i = 0;
            let count = ArraySize(this.m_watchers);
            while i < count {
                quests.UnregisterListener(this.m_watchers[i].fact, this.m_watchers[i].listenerId);
                i += 1;
            }
        }
        ArrayClear(this.m_watchers);
        ArrayClear(this.m_awaiting);
    }

    private func Register(quests: ref<QuestsSystem>) -> Void {
        if !IsDefined(quests) || ArraySize(this.m_watchers) > 0 {
            return;
        }

        // Above the config guard: the presence flag says "the mod is here", which is true
        // whether or not anyone has declared a single watch.
        quests.SetFact(this.PRESENCE_FACT, 1);

        let config = AiNpcConfigService.Get();
        if !IsDefined(config) {
            return;
        }

        // The shipped cast's own beats, alongside the ones third parties declared. Building the
        // cast a second time costs eleven sheets, once, at player attach -- the alternative is a
        // second path into the contact registry for one array read.
        let watches = AiNpcArcWatches();
        let declared = config.GetFactWatches();
        let d = 0;
        while d < ArraySize(declared) {
            ArrayPush(watches, declared[d]);
            d += 1;
        }

        let i = 0;
        let count = ArraySize(watches);
        while i < count {
            let watcher = new AiNpcFactWatcher();
            watcher.watch = watches[i];
            watcher.bridge = this;
            watcher.fact = StringToName(watches[i].fact);
            // The baseline. Reading it here, from the save that has just been restored, is
            // the whole of "only what happens while the player is here counts".
            watcher.previous = quests.GetFact(watcher.fact);
            watcher.listenerId = quests.RegisterListener(watcher.fact, watcher, n"OnFactChanged");

            // Held for the session, and not only to unregister it: the engine keeps a weak
            // hold on a listener target, so a watcher nobody references is a watch that
            // stops firing at the next collection.
            ArrayPush(this.m_watchers, watcher);
            i += 1;
        }

        if count > 0 {
            AiNpcLog(s"Fact bridge: watching \(count) quest fact(s).");
        }
    }

    /// Inbound: their fact, our character ///

    public func OnWatchFired(watch: ref<AiNpcFactWatch>, value: Int32) -> Void {
        // Read now, not at registration: the blocking fact is usually set during the very
        // stretch of play that ends with the fact being watched here.
        if NotEquals(watch.unlessFact, "") {
            let quests = GameInstance.GetQuestsSystem(GetGameInstance());
            if IsDefined(quests) && quests.GetFact(StringToName(watch.unlessFact)) > 0 {
                AiNpcLog(s"Fact '\(watch.fact)' reached \(value), held back: '\(watch.unlessFact)' is set.");
                return;
            }
        }

        // {value} carries the fact's own number into the sentence, which is what makes a
        // counter worth watching -- "you heard V has cleared {value} jobs for the Mox".
        // Everything else a character file may write is expanded too, per contact, so a
        // third-party line can say {they} or {npc} exactly like any other prompt text.
        let text = AiNpcReplaceAll(watch.event, "{value}", ToString(value));

        let i = 0;
        let count = ArraySize(watch.contacts);
        while i < count {
            let contactId = watch.contacts[i];

            // ATTRIBUTED TO THE FILE THAT DECLARED THE WATCH: the sentence belongs to whoever
            // wrote facts.<mod>.json, not to ai_npc. Filing it as ai_npc's own voice would put
            // two mods watching the same contact on one key, where the rule for one source
            // restating itself is REPLACE -- the second fact to fire would silently erase the
            // news from the first.
            let expanded = AiNpcExpandTemplateFor(contactId, text);

            // Two channels, and the difference is not how long the line lives. A remembered beat
            // goes to the memory block, which declares itself right against the character sheet;
            // a seeded one lands in <event>, which means "now" and can only add. Something that
            // HAPPENED has to be able to contradict a bio written before it happened.
            if watch.remembered {
                AiNpcRecordFact(contactId, expanded);
            } else {
                AiNpcSeedContext(contactId, AiNpcFactEventContext(expanded), watch.source);
            }
            this.Await(contactId, watch.ackFact);
            i += 1;
        }

        AiNpcLog(s"Fact '\(watch.fact)' reached \(value): \(count) contact(s) will hear about it.");
    }

    /// Outbound: our conversation, their quest ///

    private func Await(contactId: String, ackFact: String) -> Void {
        if Equals(StrLen(ackFact), 0) {
            return;
        }
        let ack = new AiNpcFactAck();
        ack.contactId = contactId;
        ack.fact = StringToName(ackFact);
        ArrayPush(this.m_awaiting, ack);
    }

    // A reply landed for this contact.
    //
    // Every acknowledgement waiting on it is set to 1, and every other one waiting on the SAME
    // fact is dropped: an event told to three people is acknowledged by the first of them who
    // answers, because the quest asked whether its news had reached somebody.
    //
    // The flag means "the contact has answered V at least once since being told" -- not "the
    // character mentioned it", which nothing here can know without reading the reply.
    public func NotifyReply(contactId: String) -> Void {
        // The ordinary case, and the reason this can sit on the delivery path: nothing is
        // ever owed, so a turn costs one array size check.
        if Equals(ArraySize(this.m_awaiting), 0) {
            return;
        }

        let quests = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if !IsDefined(quests) {
            return;
        }

        let settled: array<CName>;
        let i = 0;
        let count = ArraySize(this.m_awaiting);
        while i < count {
            if Equals(this.m_awaiting[i].contactId, contactId) && !ArrayContains(settled, this.m_awaiting[i].fact) {
                quests.SetFact(this.m_awaiting[i].fact, 1);
                ArrayPush(settled, this.m_awaiting[i].fact);
                AiNpcLog(s"Fact bridge: '\(contactId)' answered, setting \(this.m_awaiting[i].fact).");
            }
            i += 1;
        }

        if Equals(ArraySize(settled), 0) {
            return;
        }

        // Rebuilt rather than removed in place: dropping from an array while walking it is
        // how the entry after each removal gets skipped.
        let remaining: array<ref<AiNpcFactAck>>;
        i = 0;
        while i < count {
            if !ArrayContains(settled, this.m_awaiting[i].fact) {
                ArrayPush(remaining, this.m_awaiting[i]);
            }
            i += 1;
        }
        this.m_awaiting = remaining;
    }
}
