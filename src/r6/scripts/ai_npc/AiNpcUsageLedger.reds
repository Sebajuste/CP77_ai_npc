// What a day of requests cost, and the rules that read it.
//
// A free provider meters tokens by the day, so the cap has to be written in a unit the mod
// does not naturally have: a calendar day, shared by every save, character and branch, because
// the provider counts one key and does not care which playthrough spent it.
//
// Redscript has no real clock -- GameTime is inside the fiction and GetSimTime is since the
// session started. The one real date reachable is the `Date` header every HTTP response
// carries, in UTC, written by the machine that also resets the quota, so the two roll over
// together. Hence the rule: nothing is refused until a response has said what day it is, so
// the first request of a session always goes through.
//
// Everything here takes its inputs as arguments -- no storage, no settings, no game -- so what
// can be wrong is asserted offline. AiNpcUsageService does the reaching.

module AiNpc

import RedData.Json.*

/// The tally ///

// One day's spending. `day` is the day the totals belong to, empty on a ledger nothing has
// charged.
//
// `estimated` is the part of `total` no provider measured, kept apart because a day made of
// estimates and one made of measurements are worth different amounts of trust.
//
// `warned` latches the line the player is told before the day runs out. In the ledger rather
// than the service, so it is persisted: otherwise every launch re-announces a threshold
// crossed days ago.
public class AiNpcUsageLedger {
    public let day: String = "";
    public let total: Int32 = 0;
    public let estimated: Int32 = 0;
    public let warned: Bool = false;

    // Parallel arrays, since redscript has no map. Read through LaneTotal; the lanes are the
    // ones AiNpcRequestLog names.
    public let lanes: array<String>;
    public let laneTotals: array<Int32>;

    // Moves the ledger onto `day`, purging it when that differs from the one it holds. True
    // when something was purged, which is the only visible sign that a new day began. One
    // function for tomorrow and for three weeks later: a ledger is about today or about a day
    // that is over, and there is no third case.
    public func RollTo(day: String) -> Bool {
        if Equals(StrLen(day), 0) || Equals(this.day, day) {
            return false;
        }

        let purged = NotEquals(StrLen(this.day), 0);
        this.day = day;
        this.total = 0;
        this.estimated = 0;
        this.warned = false;
        ArrayClear(this.lanes);
        ArrayClear(this.laneTotals);
        return purged;
    }

    // The lane is carried so the file can say which half of the mod spent the day: the thinking
    // lane compacts behind the player's back, and an unsplittable total would hide that.
    public func Add(lane: String, charge: ref<AiNpcCharge>) -> Void {
        if !IsDefined(charge) || charge.tokens <= 0 {
            return;
        }

        // A record with no lane is an answer that arrived with nothing waiting for it. It cost
        // what it cost, so it is charged under a name: a blank key in the file would read as a
        // bug rather than as the rare thing it is.
        let key = Equals(StrLen(lane), 0) ? "unattributed" : lane;

        this.total += charge.tokens;
        if charge.estimated {
            this.estimated += charge.tokens;
        }

        let i = 0;
        let count = ArraySize(this.lanes);
        while i < count {
            if Equals(this.lanes[i], key) {
                this.laneTotals[i] += charge.tokens;
                return;
            }
            i += 1;
        }

        ArrayPush(this.lanes, key);
        ArrayPush(this.laneTotals, charge.tokens);
    }

    public func LaneTotal(lane: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.lanes);
        while i < count {
            if Equals(this.lanes[i], lane) {
                return this.laneTotals[i];
            }
            i += 1;
        }
        return 0;
    }
}

/// What a request is charged ///

// One request's cost, and whether anybody measured it.
public class AiNpcCharge {
    public let tokens: Int32 = 0;
    public let estimated: Bool = false;
}

// The provider's own total first, then its two halves added up, and only then an estimate from
// the characters sent at the measured ratio of 3.81 characters per token.
//
// The estimate departs from AiNpcRequestLog's rule that absence is never zero, and does so
// deliberately: a ceiling that charges nothing when the provider says nothing is a switch
// anyone can turn off by picking the right backend. The tally charges a guess and marks it as
// one, so both readers stay honest about which number they are looking at.
func AiNpcMeasureCharge(usage: ref<AiNpcUsage>, chars: Int32) -> ref<AiNpcCharge> {
    let charge = new AiNpcCharge();

    if IsDefined(usage) && usage.known {
        if usage.totalTokens != AiNpcTokensUnknown() {
            charge.tokens = usage.totalTokens;
            return charge;
        }

        let halves = 0;
        if usage.promptTokens != AiNpcTokensUnknown() {
            halves += usage.promptTokens;
        }
        if usage.completionTokens != AiNpcTokensUnknown() {
            halves += usage.completionTokens;
        }
        if halves > 0 {
            charge.tokens = halves;
            return charge;
        }
    }

    charge.tokens = AiNpcEstimateTokens(chars);
    charge.estimated = true;
    return charge;
}

// Integer arithmetic at the measured ratio: 3.81 characters per token is 100 characters per
// 381 hundredths. Rounded rather than truncated, so nothing can be charged zero.
func AiNpcEstimateTokens(chars: Int32) -> Int32 {
    if chars <= 0 {
        return 0;
    }
    return (chars * 100 + 190) / 381;
}

/// The rules ///

// A request is refused when the recorded day is the day the provider last said it was and its
// total has reached the budget. Everything else lets it through:
//
//   the cap is off          the default
//   no day confirmed yet    nothing has come back this session, so there is no date to check
//                           against. The request goes and its own `Date` header settles it
//   a different day         the stored total belongs to a day that is over
//
// Refusing on a date the mod cannot check is worse: a player who comes back the next day would
// be locked out with no symptom they could act on.
func AiNpcUsageAllows(ledger: ref<AiNpcUsageLedger>, confirmedDay: String,
        enabled: Bool, budget: Int32) -> Bool {
    if !enabled || budget <= 0 || !IsDefined(ledger) {
        return true;
    }
    if Equals(StrLen(confirmedDay), 0) || NotEquals(ledger.day, confirmedDay) {
        return true;
    }
    return ledger.total < budget;
}

// Four fifths of the day. Without it the ceiling is discovered mid-conversation, which reads as
// a character who stopped answering.
func AiNpcUsageWarnAt(budget: Int32) -> Int32 {
    return budget * 4 / 5;
}

// Only on the charge that crosses the threshold, and once per day: `warned` is persisted with
// the tally, so a relaunch does not re-announce it.
func AiNpcUsageWarningDue(before: Int32, after: Int32, budget: Int32, warned: Bool) -> Bool {
    if warned || budget <= 0 {
        return false;
    }
    let threshold = AiNpcUsageWarnAt(budget);
    return before < threshold && after >= threshold;
}

// The slider's value in tokens, clamped to the range the menu advertises: a value persisted
// under an older range, or edited by hand in the ini, must not set a ceiling the menu never
// offered. The menu is in thousands because a step of 1 across 200000 is not usable.
func AiNpcClampDailyBudget(thousands: Int32) -> Int32 {
    let value = thousands;
    if value < 10 {
        value = 10;
    }
    if value > 1000 {
        value = 1000;
    }
    return value * 1000;
}

func AiNpcDefaultDailyBudgetThousands() -> Int32 {
    return 200;
}

/// The day, read off the wire ///

// "Sat, 23 Aug 2026 15:42:58 GMT" -> "2026-08-23", empty when the header is missing or not in
// that shape. Only IMF-fixdate is read, which RFC 9110 requires and every measured backend
// sends; the two obsolete formats are not parsed, because a date the mod cannot read confirms
// no day and the cap keeps applying, where a wrong day silently purges a real total.
//
// The time is dropped, so there is no timezone arithmetic to get wrong: the provider's UTC day
// is the day its quota resets on.
func AiNpcUsageDayFromHttpDate(header: String) -> String {
    let parts = StrSplit(header, " ");
    if ArraySize(parts) < 4 {
        return "";
    }

    // "Sat," "23" "Aug" "2026" ...
    let month = AiNpcUsageMonthNumber(parts[2]);
    if month <= 0 {
        return "";
    }

    let day = StringToInt(parts[1]);
    if day <= 0 || day > 31 {
        return "";
    }

    let year = StringToInt(parts[3]);
    if year < 2000 || year > 2999 {
        return "";
    }

    return s"\(year)-\(AiNpcTwoDigits(month))-\(AiNpcTwoDigits(day))";
}

// 0 for anything that is not one of the twelve, so an unparseable header reports itself instead
// of producing a plausible wrong date.
func AiNpcUsageMonthNumber(name: String) -> Int32 {
    if Equals(name, "Jan") { return 1; }
    if Equals(name, "Feb") { return 2; }
    if Equals(name, "Mar") { return 3; }
    if Equals(name, "Apr") { return 4; }
    if Equals(name, "May") { return 5; }
    if Equals(name, "Jun") { return 6; }
    if Equals(name, "Jul") { return 7; }
    if Equals(name, "Aug") { return 8; }
    if Equals(name, "Sep") { return 9; }
    if Equals(name, "Oct") { return 10; }
    if Equals(name, "Nov") { return 11; }
    if Equals(name, "Dec") { return 12; }
    return 0;
}

// Zero-padded, so the day string sorts the way it reads and two ledgers compare as text.
func AiNpcTwoDigits(value: Int32) -> String {
    if value < 10 {
        return s"0\(value)";
    }
    return s"\(value)";
}

/// The file ///

// usage.json. A flat object plus one array of lanes, because the file is meant to be opened
// and read by whoever is wondering where their day went.
func AiNpcUsageToJson(ledger: ref<AiNpcUsageLedger>) -> ref<JsonObject> {
    let root = new JsonObject();
    if !IsDefined(ledger) {
        return root;
    }

    root.SetKeyString("day", ledger.day);
    root.SetKeyInt64("total", Cast<Int64>(ledger.total));
    root.SetKeyInt64("estimated", Cast<Int64>(ledger.estimated));
    root.SetKeyBool("warned", ledger.warned);

    let lanes = new JsonArray();
    let i = 0;
    let count = ArraySize(ledger.lanes);
    while i < count {
        let entry = new JsonObject();
        entry.SetKeyString("lane", ledger.lanes[i]);
        entry.SetKeyInt64("tokens", Cast<Int64>(ledger.laneTotals[i]));
        lanes.AddItem(entry);
        i += 1;
    }
    root.SetKey("lanes", lanes);
    return root;
}

// A missing or malformed file reads as an empty ledger rather than a failure: that costs one
// day counted from zero, where refusing to send would take the mod down over its bookkeeping.
func AiNpcUsageFromJson(root: ref<JsonObject>) -> ref<AiNpcUsageLedger> {
    let ledger = new AiNpcUsageLedger();
    if !IsDefined(root) {
        return ledger;
    }

    ledger.day = AiNpcJsonString(root, "day");
    ledger.total = AiNpcJsonInt(root, "total", 0);
    ledger.estimated = AiNpcJsonInt(root, "estimated", 0);
    if root.HasKey("warned") {
        ledger.warned = root.GetKeyBool("warned");
    }

    let lanes = AiNpcJsonArrayAt(root, "lanes");
    if !IsDefined(lanes) {
        return ledger;
    }

    let i: Uint32 = 0u;
    let count = lanes.GetSize();
    while i < count {
        let entry = AiNpcJsonItemObject(lanes, i);
        if IsDefined(entry) {
            let lane = AiNpcJsonString(entry, "lane");
            if NotEquals(StrLen(lane), 0) {
                ArrayPush(ledger.lanes, lane);
                ArrayPush(ledger.laneTotals, AiNpcJsonInt(entry, "tokens", 0));
            }
        }
        i += 1u;
    }
    return ledger;
}
