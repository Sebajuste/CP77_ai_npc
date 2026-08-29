// Who is drivable right now: the shipped cast, the sheets loaded from disk, and whatever
// another mod has registered, arbitrated into one list keyed by contact id.
//
// The contract a provider implements is api\AiNpcContactProvider.reds. This file decides
// nothing about what a character IS; it decides which provider answers for an id, refuses a
// second claim on one, and hands out the lookups everything else reads.

module AiNpc

// A ScriptableSystem rather than a service because its lifetime is the game session:
// registrations are per-playthrough and must not leak across a save load. Providers are held
// by strong reference, or a caller that drops its own would see the contact vanish.
public class AiNpcContactRegistry extends ScriptableSystem {

    // What a sheet's `source` says when it came from the shipped cast rather than a file. Not
    // a path: it is read back to tell "mine, replaceable" from "somebody else's".
    private const let CAST_SOURCE: String = "built-in";

    private let m_providers: array<ref<AiNpcContactProvider>>;
    private let m_castLoaded: Bool = false;
    private let m_configLoaded: Bool = false;
    private let m_configLoading: Bool = false;

    private func OnAttach() -> Void {
        this.EnsureCastLoaded();
        this.EnsureConfigLoaded();
    }

    public static func Get(game: GameInstance) -> ref<AiNpcContactRegistry> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcContactRegistry>()) as AiNpcContactRegistry;
    }

    /// Registration ///

    // Refuses anonymous providers and duplicate ids. Returning false rather than
    // overwriting is deliberate: two mods fighting over one contact id is a conflict the
    // authors have to resolve, and silently letting the last one win would make the
    // winner depend on load order.
    public func Register(provider: ref<AiNpcContactProvider>) -> Bool {
        if !IsDefined(provider) {
            return false;
        }

        let contactId = provider.GetContactId();
        if Equals(StrLen(contactId), 0) {
            FTLogError("[ai_npc]: contact provider refused: empty contact id.");
            return false;
        }

        let existing = this.Find(contactId);
        if IsDefined(existing) {
            FTLogError(s"[ai_npc]: contact provider refused: '\(contactId)' is already registered.");
            return false;
        }

        ArrayPush(this.m_providers, provider);
        AiNpcLog(s"Registered contact provider '\(contactId)' (\(provider.GetDisplayName())).");
        return true;
    }

    public func Unregister(contactId: String) -> Bool {
        let i = 0;
        let count = ArraySize(this.m_providers);
        while i < count {
            if Equals(this.m_providers[i].GetContactId(), contactId) {
                ArrayErase(this.m_providers, i);
                AiNpcLog(s"Unregistered contact provider '\(contactId)'.");
                return true;
            }
            i += 1;
        }
        return false;
    }

    /// Lookup ///

    // Whatever its availability: callers that care ask IsAvailable themselves, and a bio is
    // still wanted for a contact that is temporarily busy.
    public func Find(contactId: String) -> ref<AiNpcContactProvider> {
        if Equals(StrLen(contactId), 0) {
            return null;
        }

        // Lazily, rather than trusting OnAttach to have run: the phone UI can be built before
        // or after the system attaches. Both flags are set before any Register call, so the
        // recursion through Find terminates at once.
        this.EnsureCastLoaded();
        this.EnsureConfigLoaded();

        let i = 0;
        let count = ArraySize(this.m_providers);
        while i < count {
            if Equals(this.m_providers[i].GetContactId(), contactId) {
                return this.m_providers[i];
            }
            i += 1;
        }
        return null;
    }

    public func IsRegistered(contactId: String) -> Bool {
        return IsDefined(this.Find(contactId));
    }

    // The form to prefer, with AllAvailableContactIds written on top of it: a caller holding
    // ids has to hand each back to Find, a linear scan per contact. The phone's contact pass
    // did that once per redraw, which is why this method exists.
    //
    // IsAvailable is asked once per provider, and a provider is free to answer it by
    // consulting its own mod, so every avoided call is somebody else's work avoided too.
    public func AllAvailableProviders() -> array<ref<AiNpcContactProvider>> {
        this.EnsureCastLoaded();
        this.EnsureConfigLoaded();

        let result: array<ref<AiNpcContactProvider>>;
        let i = 0;
        let count = ArraySize(this.m_providers);
        while i < count {
            if this.m_providers[i].IsAvailable() {
                ArrayPush(result, this.m_providers[i]);
            }
            i += 1;
        }
        return result;
    }

    public func AllAvailableContactIds() -> array<String> {
        let providers = this.AllAvailableProviders();
        let result: array<String>;
        let i = 0;
        let count = ArraySize(providers);
        while i < count {
            ArrayPush(result, providers[i].GetContactId());
            i += 1;
        }
        return result;
    }

    public func CountProviders() -> Int32 {
        return ArraySize(this.m_providers);
    }

    /// Sheet-backed providers ///

    // The shipped cast, registered as providers. Runs once per session and cannot fail: the
    // sheets are compiled in, so a missing RedFileSystem or a malformed character file costs
    // a player their overrides and never the characters themselves.
    public func EnsureCastLoaded() -> Void {
        if this.m_castLoaded {
            return;
        }
        this.m_castLoaded = true;

        let cast = AiNpcBuiltinCast();
        let i = 0;
        let count = ArraySize(cast);
        while i < count {
            cast[i].source = this.CAST_SOURCE;
            this.Register(AiNpcDefContactProvider.Create(cast[i]));
            AiNpcRegisterSheetActions(cast[i]);
            i += 1;
        }
    }

    // Character files, applied over the cast, once the config service has read the disk --
    // deferred, not skipped, when it has not.
    //
    // A file naming a shipped character replaces its provider rather than being refused as a
    // duplicate: the loader has already merged the file onto a copy of that sheet. Only a
    // provider this registry built from the cast is displaced; a script provider another mod
    // registered for the same id keeps the contact.
    public func EnsureConfigLoaded() -> Void {
        // Two flags: m_configLoading breaks the re-entrancy through Register -> Find ->
        // EnsureConfigLoaded, and m_configLoaded latches only on an actual load, so a lookup
        // arriving before the storage is open defers instead of caching an empty registry.
        if this.m_configLoaded || this.m_configLoading {
            return;
        }

        let config = AiNpcConfigService.Get();
        if !IsDefined(config) {
            return;
        }

        let defs = config.GetCharacterDefs();
        if !config.IsLoaded() {
            return;
        }

        this.m_configLoading = true;
        this.EnsureCastLoaded();

        let i = 0;
        let count = ArraySize(defs);
        while i < count {
            if this.IsFromCast(defs[i].contactId) {
                this.Unregister(defs[i].contactId);
            }
            this.Register(AiNpcDefContactProvider.Create(defs[i]));
            AiNpcRegisterSheetActions(defs[i]);
            i += 1;
        }
        this.m_configLoading = false;
        this.m_configLoaded = true;

        AiNpcLog(s"Contact registry ready: \(this.CountProviders()) contact(s).");
    }

    // Whether this id is held by a provider this registry built from the cast, as opposed to
    // one another mod registered.
    private func IsFromCast(contactId: String) -> Bool {
        let existing = this.Find(contactId) as AiNpcDefContactProvider;
        return IsDefined(existing) && Equals(existing.GetDefinition().source, this.CAST_SOURCE);
    }
}

/// Public API ///
// Free functions so a third-party mod never has to reach into a container by name.

public func AiNpcGetContactRegistry() -> ref<AiNpcContactRegistry> {
    return AiNpcContactRegistry.Get(GetGameInstance());
}

// Safe at any point after the player exists; the phone picks the contact up the next time
// its list is built.
public func AiNpcRegisterContact(provider: ref<AiNpcContactProvider>) -> Bool {
    let registry = AiNpcGetContactRegistry();
    if !IsDefined(registry) {
        return false;
    }
    return registry.Register(provider);
}

public func AiNpcUnregisterContact(contactId: String) -> Bool {
    let registry = AiNpcGetContactRegistry();
    if !IsDefined(registry) {
        return false;
    }
    return registry.Unregister(contactId);
}

func AiNpcFindContact(contactId: String) -> ref<AiNpcContactProvider> {
    let registry = AiNpcGetContactRegistry();
    if !IsDefined(registry) {
        return null;
    }
    return registry.Find(contactId);
}

// The provider backing the character currently selected, or null for a plain built-in.
public func AiNpcCurrentProvider() -> ref<AiNpcContactProvider> {
    let system = GetAiNpcSystem();
    if !IsDefined(system) {
        return null;
    }
    return AiNpcFindContact(AiNpcCurrentContactId());
}

// Section overrides for one contact. Every prompt getter consults this first, which is the
// one place the three-level chain is implemented. Takes the contact rather than reading the
// selection: a prompt is built for a contact, not necessarily the one on screen.
//
// Never null. A contact with nothing to override reads as an object whose every field is
// empty, which is what "no override" means since "" already says "no opinion". Two
// representations forced every caller to guard, and one that guarded only half crashed the
// prompt build for the contacts that configure nothing -- almost all of them.
//
// The source keeps its nullable contract: GetPromptOverrides is a public API another mod
// implements, where null is the documented way to say "no opinion".
func AiNpcPromptOverridesFor(contactId: String) -> ref<AiNpcPromptOverrides> {
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        let over = provider.GetPromptOverrides();
        if IsDefined(over) {
            return over;
        }
    }
    return new AiNpcPromptOverrides();
}

/// Contact hashes ///

// A stable Int32 derived from a contact id, for mods that also register the contact with
// Phone Extension Framework, which identifies contacts by hash.
//
// Neither property is cryptographic: the same id must give the same hash in every session,
// since one that changed across a save load would detach the thread from its history, and
// two ids must not collide. Arithmetic only -- no bitwise ops, no overflow -- because
// redscript's overflow semantics are not worth relying on for something byte-stable.
//
// Values land in [1000000000, 1008000009], which does not prove no vanilla journal hash sits
// there: a mod must still verify its contact shadows no real one. Register() guards only
// against collisions between registered providers.
public func AiNpcContactHash(contactId: String) -> Int32 {
    let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.";
    let modulus = 8000009;
    let hash = 7;

    let length = StrLen(contactId);
    let i = 0;
    while i < length {
        let char = StrLeft(StrRight(contactId, length - i), 1);
        // Unknown characters map to 0 rather than being skipped, so "a?b" and "ab" differ.
        let code = StrFindFirst(alphabet, char) + 1;
        hash = (hash * 131 + code) % modulus;
        i += 1;
    }

    return 1000000000 + hash;
}
