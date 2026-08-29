// The daily tally, kept on disk and answered to the lanes.
//
// The rules are all next door, in AiNpcUsageLedger.reds, over plain values. What is here is
// the reaching: the file, the day the network last confirmed, and the one question the rest
// of the mod asks before it spends anything.
//
// A service, not a ScriptableSystem: a system is created when a save loads and dies with it,
// while the provider meters ONE key and does not care which playthrough spent it. usage.json
// lives in a RedFileSystem storage, which is not part of a savegame either, so one day's
// spending covers every save, every character and every branch.
//
// When the ceiling is met, everything stops: the reply the player is waiting for, the repair
// retry, and the memory compaction that runs behind their back. A cap that leaves one lane
// open is not a cap, and the lane it would leave open is the invisible one. There is no
// exemption for any provider, the local bridge included -- someone running a local model
// leaves the cap switched off, which is the default anyway.
//
// The one request never refused is the connection test in Mod Settings. It is counted like
// everything else, but it is the diagnostic a player runs to find out why nothing works.

module AiNpc

import RedFileSystem.*
import RedData.Json.*

public class AiNpcUsageService extends ScriptableService {

    private const let USAGE_FILE: String = "usage.json";

    private let m_ledger: ref<AiNpcUsageLedger>;
    private let m_loaded: Bool = false;

    // The last day a provider actually stated, this session. Empty until the first answer
    // lands, and that emptiness is load-bearing -- see AiNpcUsageAllows.
    //
    // Deliberately NOT persisted. A day read from the file would be a day nobody confirmed
    // since the game started, which is exactly the guess this design refuses to make.
    private let m_confirmedDay: String = "";

    // Latched by the charge that crosses four fifths of the budget, taken by the speaking
    // lane and delivered after the character's reply. See TakeWarning.
    private let m_warningDue: Bool = false;

    // Empty on purpose, and not removable. GetService returns what exists rather than
    // creating it, so a service that declares no callback is one nothing has any reason to
    // build. Same shape as AiNpcStorageService and AiNpcConfigService.
    //
    // It does NOT load the tally: service initialisation order is not guaranteed and the
    // storage may not be open yet, which is why EnsureLoaded is lazy.
    private cb func OnInitialize() {}

    public static func Get() -> ref<AiNpcUsageService> {
        return GameInstance.GetScriptableServiceContainer().GetService(NameOf<AiNpcUsageService>()) as AiNpcUsageService;
    }

    /// The question ///

    // Whether a request may be sent. Asked by all three lanes before they build anything.
    public func HasBudgetLeft() -> Bool {
        this.EnsureLoaded();
        return AiNpcUsageAllows(this.m_ledger, this.m_confirmedDay,
            AiNpcDailyLimitEnabled(), AiNpcDailyTokenBudget());
    }

    // What today has cost so far, for the request line and for anyone reading the log.
    public func DayTotal() -> Int32 {
        this.EnsureLoaded();
        return this.m_ledger.total;
    }

    /// The answer ///

    // One answered request, charged to the day it belongs to.
    //
    // `dateHeader` is the response's `Date` header, verbatim. It arrives here rather than
    // being parsed at the call site because the parse and the roll-over are one act: the day
    // it names is both what the tally is now about and what the next refusal will be measured
    // against.
    //
    // Charged whatever the status was. A refusal that cost tokens still cost them, and a 429
    // that cost none charges nothing -- the provider's own numbers decide, not the outcome.
    public func Charge(lane: String, charge: ref<AiNpcCharge>, dateHeader: String) -> Void {
        this.EnsureLoaded();

        let day = AiNpcUsageDayFromHttpDate(dateHeader);
        if NotEquals(StrLen(day), 0) {
            this.m_confirmedDay = day;
            if this.m_ledger.RollTo(day) {
                AiNpcLog(s"A new day: the token tally starts again from zero (\(day)).");
            }
        }

        if !IsDefined(charge) || charge.tokens <= 0 {
            return;
        }

        let before = this.m_ledger.total;
        this.m_ledger.Add(lane, charge);

        let budget = AiNpcDailyTokenBudget();
        if AiNpcDailyLimitEnabled()
                && AiNpcUsageWarningDue(before, this.m_ledger.total, budget, this.m_ledger.warned) {
            this.m_ledger.warned = true;
            this.m_warningDue = true;
        }

        this.Save();
    }

    // Whether the player is owed the warning line, asked once and answered once.
    //
    // Taken by the speaking lane at delivery time: the threshold is usually crossed by a
    // request the player is waiting on, and a line arriving while the character was still
    // typing would land before the message it belongs after. A threshold crossed by the
    // thinking lane surfaces at the next reply instead.
    public func TakeWarning() -> Bool {
        if !this.m_warningDue {
            return false;
        }
        this.m_warningDue = false;
        return true;
    }

    /// The file ///

    private func EnsureLoaded() -> Void {
        if this.m_loaded {
            return;
        }

        // Marked loaded first and unconditionally: a storage that is not up yet must leave
        // this service with an empty tally that still answers, not with a null it retries
        // reading on every request.
        this.m_loaded = true;
        this.m_ledger = new AiNpcUsageLedger();

        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            return;
        }
        if NotEquals(storage.Exists(this.USAGE_FILE), FileSystemStatus.True) {
            return;
        }

        let file = storage.GetFile(this.USAGE_FILE);
        if !IsDefined(file) {
            return;
        }

        let json = file.ReadAsJson();
        if !IsDefined(json) || json.IsUndefined() || !json.IsObject() {
            return;
        }

        this.m_ledger = AiNpcUsageFromJson(json as JsonObject);
        AiNpcLog(s"Token tally loaded: \(this.m_ledger.total) on \(this.m_ledger.day).");
    }

    // Written on every charge rather than at some end that may never come: a game closed from
    // the desktop, a crash, a session with no clean shutdown -- all ordinary, and all would
    // otherwise hand the player back a day they had already spent.
    private func Save() -> Void {
        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            return;
        }
        let file = storage.GetFile(this.USAGE_FILE);
        if !IsDefined(file) {
            return;
        }
        file.WriteJson(AiNpcUsageToJson(this.m_ledger), "    ");
    }

}
