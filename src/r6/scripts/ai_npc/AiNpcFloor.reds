// The exclusive turn on one conversation.
//
// A mod running its own scripted exchange used to suspend a contact by answering false from
// the provider's IsAvailable, which conflated two questions:
//
//     "is this contact reachable in the fiction at all"    a property of the CHARACTER
//     "is somebody mid-scene with them right now"          a property of the THREAD
//
// The first belongs to whoever declared the contact. The second is the floor, and it had to be
// separated because two mods could both answer false to IsAvailable without either learning
// the other had: the second one's scene was talked over the moment the first released.
//
// While the floor is held, only the holder's GetScriptedReply is consulted, no prompt is
// built, and no other mod may seed a message -- splicing a line into the middle of somebody's
// scene is the incoherence being prevented.
//
// A LEASE, NOT A LOCK: a mod that crashes, or is uninstalled mid-scene, must not hold a
// character for the rest of the playthrough. Every claim carries an expiry, evaluated LAZILY
// on read -- never on a DelayCallback, which does not survive a save load and would leave the
// lease immortal exactly when the game was reloaded to escape it.
//
// The clock is engine time, not game time: a scene is measured in the seconds a player spends
// typing, and Night City's clock runs some sixty times faster.

module AiNpc

public class AiNpcFloorLease {
    public let contactId: String;
    public let holderId: String;
    public let expiresAt: Float;
}

public class AiNpcFloorRegistry extends ScriptableSystem {

    private let m_leases: array<ref<AiNpcFloorLease>>;

    // Breaks the re-entry through Holder -> expire -> broadcast -> TakeFloor -> Holder. The
    // lease is erased before anything is published, so the inner Holder finds nothing anyway;
    // this only stops a second expiry sweep running inside the first.
    private let m_expiring: Bool = false;

    public static func Get(game: GameInstance) -> ref<AiNpcFloorRegistry> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcFloorRegistry>()) as AiNpcFloorRegistry;
    }

    public func Take(contactId: String, holderId: String, maxSeconds: Float) -> Bool {
        if Equals(StrLen(contactId), 0) || Equals(StrLen(holderId), 0) {
            return false;
        }

        let current = this.Holder(contactId);
        if NotEquals(StrLen(current), 0) {
            // Re-taking your own floor extends it rather than failing, so a mod renewing
            // during a long scene does not have to release first and risk losing it.
            if Equals(current, holderId) {
                let index = this.IndexOf(contactId);
                this.m_leases[index].expiresAt = AiNpcLeaseEndsAt(this.Now(), maxSeconds);
                return true;
            }
            return false;
        }

        let lease = new AiNpcFloorLease();
        lease.contactId = contactId;
        lease.holderId = holderId;
        lease.expiresAt = AiNpcLeaseEndsAt(this.Now(), maxSeconds);
        ArrayPush(this.m_leases, lease);

        AiNpcLog(s"'\(holderId)' holds the floor on '\(contactId)'.");
        AiNpcPublishFloorChanged(contactId, holderId, "", false);
        return true;
    }

    // False when this holder did not have it, which is not an error: it is the honest answer
    // to releasing twice, or to releasing after the lease already lapsed.
    public func Release(contactId: String, holderId: String) -> Bool {
        let index = this.IndexOf(contactId);
        if index < 0 || NotEquals(this.m_leases[index].holderId, holderId) {
            return false;
        }

        ArrayErase(this.m_leases, index);
        AiNpcLog(s"'\(holderId)' released the floor on '\(contactId)'.");
        this.AnnounceRelease(contactId, holderId, false);
        return true;
    }

    // Who holds it, or "" when it is free. Expires a lapsed lease on the way past, which is
    // the whole mechanism: nothing else ever needs to sweep.
    public func Holder(contactId: String) -> String {
        let index = this.IndexOf(contactId);
        if index < 0 {
            return "";
        }

        if !AiNpcLeaseHasExpired(this.m_leases[index].expiresAt, this.Now()) {
            return this.m_leases[index].holderId;
        }

        let holderId = this.m_leases[index].holderId;
        ArrayErase(this.m_leases, index);

        if !this.m_expiring {
            this.m_expiring = true;
            FTLogError(s"[ai_npc]: the floor held by '\(holderId)' on '\(contactId)' expired. Whatever scene it was running has stopped without releasing it.");
            this.AnnounceRelease(contactId, holderId, true);
            this.m_expiring = false;
        }
        return "";
    }

    // Everything one mod holds. Part of withdrawing from the session in one call.
    public func ReleaseAllFor(holderPrefix: String) -> Void {
        let i = ArraySize(this.m_leases) - 1;
        while i >= 0 {
            if StrBeginsWith(this.m_leases[i].holderId, holderPrefix) {
                let contactId = this.m_leases[i].contactId;
                let holderId = this.m_leases[i].holderId;
                ArrayErase(this.m_leases, i);
                this.AnnounceRelease(contactId, holderId, false);
            }
            i -= 1;
        }
    }

    /// Internals ///

    // Told, then offered. The listeners learn what happened; the extensions get their defined
    // moment to claim what was just freed, in id order, so which one gets it is the same on
    // every machine and every replay.
    private func AnnounceRelease(contactId: String, previousHolderId: String, expired: Bool) -> Void {
        AiNpcPublishFloorChanged(contactId, "", previousHolderId, expired);
        AiNpcOfferFloor(contactId);

        // LAST, after the extensions have had their defined moment to claim what was freed. An
        // unprompted message waiting on this thread must not cut in front of a scene that was
        // about to start: whoever takes the floor inside OnFloorAvailable holds it again by the
        // time the drain runs, and the queued reason simply keeps waiting.
        AiNpcRequestSpeechDrain();
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(GetGameInstance()));
    }

    private func IndexOf(contactId: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_leases);
        while i < count {
            if Equals(this.m_leases[i].contactId, contactId) {
                return i;
            }
            i += 1;
        }
        return -1;
    }
}

/// Access ///

func AiNpcGetFloorRegistry() -> ref<AiNpcFloorRegistry> {
    return AiNpcFloorRegistry.Get(GetGameInstance());
}

public func AiNpcTakeFloor(contactId: String, holderId: String, opt maxSeconds: Float) -> Bool {
    let registry = AiNpcGetFloorRegistry();
    return IsDefined(registry) && registry.Take(contactId, holderId, maxSeconds);
}

public func AiNpcReleaseFloor(contactId: String, holderId: String) -> Bool {
    let registry = AiNpcGetFloorRegistry();
    return IsDefined(registry) && registry.Release(contactId, holderId);
}

public func AiNpcFloorHolder(contactId: String) -> String {
    let registry = AiNpcGetFloorRegistry();
    if !IsDefined(registry) {
        return "";
    }
    return registry.Holder(contactId);
}

// Whether a write from this source may go into this thread right now.
//
// The gate every seeding path asks. A free thread lets everyone through; a held one lets only
// its holder's mod through, so a mod running a scene can still narrate inside it.
func AiNpcMayWriteTo(contactId: String, sourceId: String) -> Bool {
    let holder = AiNpcFloorHolder(contactId);
    if Equals(StrLen(holder), 0) {
        return true;
    }
    return Equals(holder, sourceId) || StrBeginsWith(holder, sourceId + ":");
}

/// Broadcast ///

func AiNpcPublishFloorChanged(contactId: String, holderId: String, previousHolderId: String, expired: Bool) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ev = new AiNpcFloorEvent();
    ev.contactId = contactId;
    ev.holderId = holderId;
    ev.previousHolderId = previousHolderId;
    ev.expired = expired;

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnFloorChanged(ev);
        }
        i += 1;
    }
}

// Offers the freed thread to every extension registered for it, in id order: whoever calls
// TakeFloor first inside its callback wins. Not "the longest waiting", which would make the
// outcome depend on when each mod happened to try -- attachment order again.
func AiNpcOfferFloor(contactId: String) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ctx = AiNpcBuildContactContext(contactId);
    let entries = registry.Extensions();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].ext.OnFloorAvailable(ctx);
        }
        i += 1;
    }
}

/// The scripted reply ///

// Who answers this message without a model, if anyone. Two sources, in this order:
//
//   1. the extension HOLDING THE FLOOR, if there is one. A scene in progress owns the reply.
//   2. the contact's own provider. A correspondent that is not a person in the fiction -- an
//      automated number, a bot, a menu -- is scripted whether or not anybody took a turn.
//
// Three answers, as in the provider protocol:
//
//     ""                       no opinion -- go to the model
//     AiNpcIsSilentReply(r)    handled, say nothing, start no generation
//     anything else            that text IS the reply
//
// A holder answering "" falls through to the provider rather than short-circuiting: "" means
// "I have nothing to say to this", and a scripted contact underneath is still scripted.
func AiNpcResolveScriptedReply(contactId: String, playerText: String) -> String {
    let holder = AiNpcFloorHolder(contactId);
    if NotEquals(StrLen(holder), 0) {
        let registry = AiNpcGetExtensionRegistry();
        if IsDefined(registry) {
            let ctx = AiNpcBuildContactContext(contactId, playerText);
            let entries = registry.Extensions();
            let i = 0;
            let count = ArraySize(entries);
            while i < count {
                if Equals(entries[i].fullId, holder) {
                    let reply = entries[i].ext.GetScriptedReply(ctx);
                    if NotEquals(StrLen(reply), 0) {
                        return reply;
                    }
                    i = count;
                } else {
                    i += 1;
                }
            }
        }
    }

    let provider = AiNpcProviderFor(contactId);
    if !IsDefined(provider) {
        return "";
    }
    return provider.GetScriptedReply(playerText);
}
