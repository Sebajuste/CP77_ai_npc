// The action pass: one request per reply, asking a model what the character just did.
//
// It exists so the dialogue model can stop being asked two things at once. In Dedicated mode
// the <commands> block leaves the conversation prompt entirely -- the character writes prose
// and nothing else -- and this lane reads that prose against the command table afterwards.
// Embedded mode is the other half of the switch and the default: the block stays in the
// conversation, the reply carries its own brackets, and this system never sends anything.
//
// ITS OWN SYSTEM, and that is not tidiness. AiNpcHttpSystem holds one m_record and one
// watchdog; the repair survives sharing them only because it is strictly sequential inside a
// turn. This pass runs AFTER the reply has been delivered, which is the moment the player is
// free to send the next message -- and that message would overwrite the record this one is
// still waiting on, charging its tokens to the wrong lane.
//
// Silent on failure, like the thinking lane and for the same reason: nothing the player is
// looking at depends on it. A selection that does not come back is an action that does not
// fire, which is what Embedded mode does on a model that forgets the bracket.

module AiNpc

import RedHttpClient.*
import RedData.Json.*

public class AiNpcActionService extends ScriptableSystem {

    private let m_contact: String;
    private let m_serial: Int32 = 0;
    private let m_watchdog: ref<AiNpcWatchdog>;
    private let m_record: ref<AiNpcRequestRecord>;

    private func OnAttach() -> Void {
        this.m_watchdog = new AiNpcWatchdog();
        this.m_record = AiNpcRequestRecord.Idle();
    }

    public static func Get() -> ref<AiNpcActionService> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcActionService>()) as AiNpcActionService;
    }

    /// The send ///

    // Called once per delivered reply, from the speaking lane. Every refusal below is logged
    // and none of them reaches the player: the message they are reading is already correct,
    // and what is at stake is whether a command fires behind it.
    public func Examine(contactId: String, reply: String) -> Void {
        if !AiNpcActionsAreDedicated() {
            return;
        }
        if Equals(StrLen(contactId), 0) || Equals(StrLen(reply), 0) {
            return;
        }

        // A per-turn pass that cannot be refused spends the day's budget on work the player
        // never sees. Refused BEFORE the vocabulary is built, so a spent day costs nothing.
        if !AiNpcHasTokenBudgetLeft() {
            AiNpcLog(s"No action selection for '\(contactId)': the day's token budget is spent.");
            return;
        }

        // One in flight at a time. A reply that arrives while another selection is running is
        // a turn that goes unexamined -- said out loud, because the symptom otherwise is a
        // command that simply did not fire.
        if this.m_watchdog.IsWaiting() {
            AiNpcLog(s"An action selection is still in flight; the reply for '\(contactId)' is not examined.");
            return;
        }

        let npcName = AiNpcGetCharacterName(contactId);
        let window = AiNpcHistoryTrim(AiNpcStoredMessages(contactId), AiNpcActionSelectorWindow());
        let builder = AiNpcPassActions.Of(contactId, npcName,
            AiNpcHistoryTranscript(window, npcName), reply);

        // No table means no command this contact may run: the recipe dropped the block, or
        // nothing is offered here. Nothing to select from, and nothing to pay for.
        if !builder.Ready() {
            return;
        }

        let provider = AiNpcProviderSetting();
        if NotEquals(StrLen(AiNpcLlmCredentialIssue(provider)), 0) {
            return;
        }

        this.m_contact = contactId;
        this.m_serial += 1;
        let request = AiNpcPassSend(builder, provider, contactId, this, n"OnActionResponse",
            AiNpcCliRequestId(AiNpcCliLaneActions(), this.m_serial));
        if !IsDefined(request) {
            AiNpcLog(s"The action selection for '\(contactId)' was refused by the transport.");
            return;
        }
        this.m_record = request.record;

        // The slot stays a local: nothing below the deadline reads it again, and a field would
        // outlive the request it describes.
        AiNpcArmTimeout(AiNpcActionTimeoutCallback.Create(this.m_watchdog.Arm()),
            AiNpcLlmRequestTimeout(provider, request.slot));
    }

    /// The answer ///

    private cb func OnActionResponse(response: ref<HttpResponse>) {
        this.HandleActionReply(AiNpcReply.FromHttp(response));
    }

    public func OnCliActionReply(serial: Int32, reply: ref<AiNpcReply>) -> Void {
        if NotEquals(serial, this.m_serial) {
            AiNpcLog(s"An action selection arrived after its turn (serial \(serial)); dropped.");
            return;
        }
        this.HandleActionReply(reply);
    }

    private func HandleActionReply(reply: ref<AiNpcReply>) -> Void {
        if !this.m_watchdog.IsWaiting() {
            AiNpcLog("An action selection arrived with nothing waiting for it; dropped.");
            return;
        }
        this.m_watchdog.Disarm();

        // Above every branch: an abandoned selection still spent its tokens.
        this.m_record.Answered(reply);

        let root = reply.Root();
        if !reply.IsOk() || !IsDefined(root) {
            // The provider's own sentence, because one of them is actionable: a slot that
            // switches the draft off is refused outright by an endpoint that requires it, and
            // "HTTP 400" alone would leave a player with a pass that does nothing and no word
            // saying which key to remove.
            let detail = AiNpcExtractApiError(root);
            if NotEquals(StrLen(detail), 0) {
                detail = ": " + detail;
            }
            AiNpcLog(s"The action selection for '\(this.m_contact)' failed (HTTP \(reply.StatusCode()))\(detail); nothing fires.");
            return;
        }
        if AiNpcReplyWasTruncated(root) {
            AiNpcLog("The action selection was cut off by the output budget (max_tokens); nothing fires.");
            return;
        }

        let tag = AiNpcActionSelectorTag(AiNpcExtractChatText(root));
        if Equals(StrLen(tag), 0) {
            return;
        }

        // Through the ordinary dispatcher, against the same table the vocabulary was rendered
        // from: this lane decides WHEN a command is looked for, never which ones exist or who
        // may run one. The text it returns is thrown away -- the message was delivered before
        // this request was sent, and rewriting it now would edit a bubble the player has read.
        let outcome = AiNpcApplyActions(this.m_contact, tag);
        if ArraySize(outcome.unknown) > 0 {
            AiNpcLog(s"The action selection answered \(tag), which names no command this contact offers.");
            return;
        }
        if ArraySize(outcome.fumbled) > 0 {
            // No repair pass here: a call whose entire output is one line has nothing to
            // repair, and asking twice would double the cost of every turn.
            AiNpcLog(s"The action selection answered \(tag) with the wrong number of fields; nothing fires.");
            return;
        }
        AiNpcLog(s"The action selection ran \(tag) for '\(this.m_contact)'.");
    }

    // Abandoned like any other silent lane: nothing was delivered, nothing is undone, and the
    // next reply gets its own selection.
    public func OnWaitTimedOut(waitId: Int32) -> Void {
        if !this.m_watchdog.IsCurrent(waitId) {
            return;
        }
        this.m_watchdog.Disarm();
        this.m_record.Answered(AiNpcReply.Nothing());
        AiNpcLog(s"The action selection for '\(this.m_contact)' never came back; nothing fires.");
    }
}
