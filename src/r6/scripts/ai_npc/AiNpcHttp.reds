module AiNpc

import Codeware.*
import RedData.Json.*
import RedHttpClient.*
import RedFileSystem.*


public class AiNpcHttpSystem extends ScriptableSystem {
  private let m_callbackSystem: wref<CallbackSystem>;
  private let isGenerating: Bool = false;

  // The generation in flight: who it is for, where it was sent, and the one repair it is
  // allowed. AiNpcGeneration holds the invariant this file rests on -- a request is addressed
  // once and never re-asks who is selected.
  private let m_generation: ref<AiNpcGeneration>;

  // Armed and disarmed by ToggleIsGenerating, the one site. AiNpcWatchdog silences a stale
  // timer.
  private let m_watchdog: ref<AiNpcWatchdog>;

  // Counted up on every send. Only the CLI transport reads them: an HTTP answer comes back
  // through the callback object it was sent with, so a stale one cannot arrive.
  //
  // Two counters, because the repair is a second request inside one turn whose answer
  // re-enters elsewhere: a shared counter would let a late chat answer pass for a repair.
  private let m_chatSerial: Int32 = 0;
  private let m_repairSerial: Int32 = 0;

  // What the request in flight is costing -- see AiNpcRequestLog. Its own field rather than
  // something hung on the turn: a repair replaces this record and keeps the turn, and a record
  // that survived it would report the reply's size against the retry's cost.
  private let m_record: ref<AiNpcRequestRecord>;

  // The slot the request in flight was sent on, held for the same reason the record is: the
  // watchdog that has to name a deadline runs long after the send, and a lane waits on one
  // request at a time.
  private let m_slot: ref<AiNpcSlot>;

  /// Lifecycle ///

  private func OnAttach() {
    this.m_watchdog = new AiNpcWatchdog();
    this.m_generation = AiNpcGeneration.Idle();
    this.m_record = AiNpcRequestRecord.Idle();
    this.m_callbackSystem = GameInstance.GetCallbackSystem();
    this.m_callbackSystem.RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
  }

  private func OnDetach() {
    this.m_callbackSystem.UnregisterCallback(n"Session/Ready", this, n"OnSessionReady");
    this.m_callbackSystem = null;
  }

  /// Game events ///

  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    let isPreGame = event.IsPreGame();
    if !isPreGame {
      return;
    }
  }

  // The contact is a parameter, not a lookup: this is the one place a generation is addressed,
  // and everything downstream reads the generation rather than asking again.
  public func TriggerPostRequest(contactId: String, playerMessage: String) {
    if Equals(StrLen(contactId), 0) {
      AiNpcLog("Refused to generate a reply for an empty contact id.");
      return;
    }

    // Before the generation is addressed, because addressing it is what would overwrite the
    // turn already in flight and hand its answer to the wrong message.
    let busy = this.BusyRefusal();
    if NotEquals(StrLen(busy), 0) {
      AiNpcLog(s"Refused to generate a reply for '\(contactId)': \(busy).");
      return;
    }

    // Addressing the generation and refilling its repair budget are one act, so neither can
    // happen without the other.
    this.m_generation = AiNpcGeneration.ForPlayer(contactId, playerMessage);

    // Asked before a prompt is built, so a contact that answers for itself costs no tokens,
    // needs no API key and cannot be argued out of character.
    if this.TryScriptedReply(contactId, playerMessage) {
      return;
    }

    this.ChatPostRequest();
  }

  // The character writes first, because a mod stated a reason for her to.
  //
  // Every refusal below is answered on the ticket and nowhere else: nobody is watching a
  // screen for this. AiNpcClientWantsToSay already checked what it could without the lane;
  // what is left here depends on state only this system holds.
  //
  // The scripted-reply path is not consulted: GetScriptedReply asks what a contact answers to
  // a message, and there is no message. It is overridden by third-party mods, so it cannot be
  // widened without unhooking every override. Such a contact has CharacterWrote for this.
  public func TriggerUnpromptedRequest(contactId: String, modId: String, reason: String,
                                       ticket: Int32, opt intent: String, opt expiresAt: Float) -> Void {
    // The three obstructions that clear themselves, and the only ones a window can wait out.
    // Each is refused outright when the caller said now or never, and queued when it named a
    // window; that choice is the whole of what `expiresAt` decides.
    //
    // The player's setting is not among them: AiNpcClientWantsToSay answers it before a ticket
    // is issued, since nothing about it changes while the session runs.
    let now = AiNpcSpeechNow();
    let queue = AiNpcGetSpeechQueue();

    if !AiNpcMayWriteTo(contactId, modId) {
      this.HoldOrRefuse(contactId, modId, reason, intent, ticket, expiresAt,
        s"'\(AiNpcFloorHolder(contactId))' holds the floor");
      return;
    }

    let busy = this.BusyRefusal();
    if NotEquals(StrLen(busy), 0) {
      this.HoldOrRefuse(contactId, modId, reason, intent, ticket, expiresAt, busy);
      return;
    }

    // One minute of play between two unprompted messages on one contact. Not a schedule --
    // when a character has something to say stays the mod's question -- but a ceiling on how
    // fast a trigger that fires in a loop can spend the player's quota.
    if IsDefined(queue) && !queue.MaySpeakAt(contactId, now) {
      this.HoldOrRefuse(contactId, modId, reason, intent, ticket, expiresAt,
        s"'\(contactId)' wrote first less than \(Cast<Int32>(AiNpcSpeechDebounce())) seconds ago");
      return;
    }

    // Marked before the send: the debounce protects the quota, and a request that leaves has
    // spent one whether or not an answer comes back.
    if IsDefined(queue) {
      queue.MarkSpoken(contactId, now);
    }

    this.m_generation = AiNpcGeneration.ForMod(contactId, modId, reason, ticket, intent);
    AiNpcLog(s"'\(modId)' asked '\(contactId)' to write first. The reason it gave: \(reason)");
    if NotEquals(StrLen(intent), 0) {
      // Logged apart from the reason: they answer different questions, and showing one as the
      // other sends an author looking at the wrong string.
      AiNpcLog(s"... and what she is after while writing it: \(intent)");
    }
    this.ChatPostRequest();
  }

  // One generation per lane, asked here rather than by each caller: the player's surfaces grey
  // their own send control and a mod has no control to grey, so neither of them owns this rule.
  //
  // A sentence rather than a flag, because the two callers report it to different audiences
  // and must not phrase the same refusal two ways. Empty means the lane is free.
  private func BusyRefusal() -> String {
    if this.isGenerating {
      return "a generation is already running";
    }
    return "";
  }

  // One place decides what a temporary refusal means, so a fourth obstruction cannot be the
  // one that forgot to honour the window.
  private func HoldOrRefuse(contactId: String, modId: String, reason: String, intent: String,
                            ticket: Int32, expiresAt: Float, detail: String) -> Void {
    if expiresAt > 0.0 {
      AiNpcQueueSpeech(modId, contactId, reason, intent, ticket, expiresAt);
      return;
    }
    AiNpcResolveClientTicket(ticket, AiNpcTicketFailed(), detail);
  }

  // True when the message is dealt with and no request should be sent. The delivery takes the
  // same path a generated reply does -- typing indicator, delay, HandleMessage -- so a
  // scripted answer is a response that arrived instantly, not a second pipeline to drift.
  private func TryScriptedReply(contactId: String, playerMessage: String) -> Bool {
    // Two sources, resolved in AiNpcResolveScriptedReply: the extension holding the floor, if
    // any, then the contact's own provider.
    let reply = AiNpcResolveScriptedReply(contactId, playerMessage);
    if Equals(StrLen(reply), 0) {
      return false;       // no opinion: let the model answer
    }

    // Silence. V's message is still recorded by the caller, so the conversation keeps an
    // unanswered line. Generation never starts, so the input stays enabled and nobody watches
    // a typing indicator for someone who will not write back.
    if AiNpcIsSilentReply(reply) {
      AiNpcLog(s"'\(contactId)' answers nothing to this message (scripted silence).");
      return true;
    }

    AiNpcLog(s"'\(contactId)' answered from its own script; no request sent.");
    this.ToggleIsGenerating(true);
    this.DelayedTyping();
    this.DelayedScriptedMessage(contactId, reply);
    return true;
  }

  // One send for every chat-shaped backend: url, headers and body shape are AiNpcLlm's, the
  // same answers the thinking lane gets. What is left here belongs to this lane -- capturing
  // the contact, reporting the failure to the player, and the generating state.
  private func ChatPostRequest() {
    // Before the url, the credentials and the prompt, because everything below costs
    // something. Here rather than in TriggerPostRequest so a contact that answers for itself
    // keeps answering: a scripted reply sends nothing for a budget to refuse.
    if !this.RefuseIfBudgetSpent() {
      return;
    }

    let provider = AiNpcProviderSetting();

    // Above the guard: the failure log names the turn's url, so it is set even on the paths
    // that never reach AsyncHttpClient.
    this.m_generation.SendingTo(AiNpcLlmChatUrl(provider));

    let issue = AiNpcLlmCredentialIssue(provider);
    if NotEquals(StrLen(issue), 0) {
      // Through HandleRequestFailure like every other failure: the operator line reaches the
      // bubble, and the technical instruction goes to the log via FTLogError, which unlike
      // AiNpcLog does not depend on a setting being on.
      this.HandleRequestFailure(issue);
      return;
    }

    // Consumed here, not inside the builder: building a prompt must have no side effect, and
    // spending a mod's seeded context is an act.
    let builder = AiNpcPassConversation.Of(this.m_generation.Contact(),
      AiNpcTakePendingContext(this.m_generation.Contact()),
      this.m_generation.Intent(),
      this.m_generation.Ask(),
      this.m_generation.SpeaksFirst());

    // One send for both transports, and this lane is not told which one runs. Naming the CLI
    // type in one file limits the blast radius of a plugin that failed to load.
    this.m_chatSerial += 1;
    let request = AiNpcPassSend(builder, provider, this.m_generation.Contact(), this,
      n"OnOpenAIResponse", AiNpcCliRequestId(AiNpcCliLaneChat(), this.m_chatSerial));
    if !IsDefined(request) {
      // Refused before anything left, reported through the single failure exit so the
      // indicator comes down and the input is released.
      this.HandleRequestFailure("the transport refused the request - is ai_npc.dll installed?");
      return;
    }

    // Both outlive the send: the deadline is armed below, and the cost is charged when the
    // answer lands.
    this.m_slot = request.slot;
    this.m_record = request.record;
    this.ToggleIsGenerating(true);
  }

  // No logic, so an answer cannot be handled one way here and another from the plugin.
  private cb func OnOpenAIResponse(response: ref<HttpResponse>) {
    this.HandleChatReply(AiNpcReply.FromHttp(response));
  }

  // Called from AiNpcCliDeliver. A request that timed out was never cancelled: the process is
  // still running and will deliver when it finishes, by which time the player has been told
  // nobody answered. The serial stops that stale reply landing in the thread.
  public func OnCliChatReply(serial: Int32, reply: ref<AiNpcReply>) -> Void {
    if NotEquals(serial, this.m_chatSerial) {
      AiNpcLog(s"A CLI reply arrived after its turn (serial \(serial)); dropped.");
      return;
    }
    this.HandleChatReply(reply);
  }

  private func HandleChatReply(reply: ref<AiNpcReply>) -> Void {
    if !this.m_watchdog.IsWaiting() {
      AiNpcLog("A chat answer arrived with nothing waiting for it; dropped.");
      return;
    }

    let root = reply.Root();

    // Above every branch, refusals included: a 429 costs no tokens and is the moment the
    // daily cap was reached.
    this.m_record.Answered(reply);

    if !reply.IsOk() {
      this.HandleRequestFailure(this.DescribeReplyFailure(reply));
      return;
    }

    if !IsDefined(root) {
      this.HandleRequestFailure("the reply could not be parsed");
      return;
    }

    if AiNpcDebugEnabled() {
      AiNpcLog("== Chat POST Response ==");
      AiNpcLog(s"\(root.ToString("\t"))");
    }

    let text = AiNpcExtractChatText(root);
    if Equals(StrLen(text), 0) {
      // A 200 can still carry an error body, or a choice with empty content.
      let detail = AiNpcExtractApiError(root);
      if Equals(StrLen(detail), 0) {
        detail = "the character had nothing to say";
      }
      this.HandleRequestFailure(detail);
      return;
    }

    // Delivered, and named. A truncated reply is worth reading -- it is the message minus its
    // end -- but the end is where an [ACTION:...] command sits, so a turn that agreed to
    // something and then does nothing has its explanation here rather than nowhere.
    if AiNpcReplyWasTruncated(root) {
      AiNpcLog(s"The reply for '\(this.m_generation.Contact())' was cut off by the output budget (max_tokens on slot '\(AiNpcSlotNameOf(this.m_slot))'). Any command it was about to write is gone; the text is delivered as far as it got.");
    }

    // What remains is pacing, not network. Left armed, a reply that arrived late in its own
    // budget would be cut short by its own timer during the delay below.
    this.m_watchdog.Disarm();

    this.DelayedTyping();
    this.DelayedMessage(this.m_generation.Contact(), text);
  }

  // An error carried in the body wins, then the bare status code -- except at status 0, where
  // there is no response to quote and the url is the only evidence left.
  private func DescribeReplyFailure(reply: ref<AiNpcReply>) -> String {
    let detail = AiNpcExtractApiError(reply.Root());
    if Equals(StrLen(detail), 0) {
      detail = s"HTTP \(reply.StatusCode())";
    }
    if Equals(reply.StatusCode(), 0) {
      detail = AiNpcDescribeTransportFailure(this.m_generation.Url(), detail);
    }
    return detail;
  }

  // A wait that ran out of clock. Public because a DelayCallback is the only thing that can
  // reach it. It reports through HandleRequestFailure: a provider that never answers and one
  // that answers "no" are the same event downstream. All it adds is the sentence naming
  // silence as the cause, since there is no response to quote.
  public func OnWaitTimedOut(waitId: Int32) {
    if !this.m_watchdog.IsCurrent(waitId) {
      return;
    }
    let seconds = Cast<Int32>(AiNpcLlmRequestTimeout(AiNpcProviderSetting(), this.m_slot));
    this.HandleRequestFailure(s"no answer within \(seconds)s - the request was dropped or the provider never replied");
  }

  // True when the request may go ahead. When it may not, the phone company says why -- the
  // shape a failure takes, minus the failure: no url to name, no provider to blame, and
  // nothing went wrong.
  //
  // Listeners are told first, as in HandleRequestFailure: a mod waiting on an answer has to
  // learn it is not coming before the operator line lands.
  private func RefuseIfBudgetSpent() -> Bool {
    if AiNpcHasTokenBudgetLeft() {
      return true;
    }

    let usage = AiNpcUsageService.Get();
    let spent = IsDefined(usage) ? usage.DayTotal() : 0;
    AiNpcLog(s"No request sent: the daily token budget is spent (\(spent)/\(AiNpcDailyTokenBudget())).");

    AiNpcPublishReplyFailed(this.m_generation.Contact(), "the daily token budget is spent");

    // The phone company speaks only to somebody waiting for an answer. A generation a mod
    // asked for has nobody at the screen, so the refusal goes back on its ticket.
    if this.m_generation.SpeaksFirst() {
      AiNpcResolveClientTicket(this.m_generation.Ticket(), AiNpcTicketFailed(),
        "the daily token budget is spent");
    } else {
      this.HandleMessage(this.m_generation.Contact(), AiNpcBudgetSpentMessage(), true);
    }
    return false;
  }

  // The line before the ceiling, at four fifths of the day. Delivered after the character's
  // reply rather than when the threshold is crossed: that moment is usually inside a request
  // the player is waiting on, and the notice would land before the message it belongs after.
  //
  // Not through HandleMessage: that path parses action tags, wakes the thinking lane and
  // offers the fact bridge a turn, none of which should run twice for one reply.
  private func DeliverBudgetWarning(contactId: String) {
    let usage = AiNpcUsageService.Get();
    if !IsDefined(usage) || !usage.TakeWarning() {
      return;
    }

    let text = AiNpcBudgetWarningMessage();
    AiNpcDeliverOrNotify(contactId, text);
    AiNpcAppendMessage(contactId, text, false, "", true);
  }

  // Single exit for every failed request: an early return that skips the typing indicator
  // leaves "... is typing" on screen forever with no message.
  //
  // With Debug Mode on the player gets the carrier line then the technical one; with it off,
  // only the carrier line.
  private func HandleRequestFailure(detail: String) {
    // FTLogError, not AiNpcLog: "Enable Logs" is off by default, and a lost Mod Settings value
    // turns it off behind the player's back. Since the bubble is diegetic this is the only
    // place a cause is stated, so it is conditional on nothing.
    let provider = AiNpcProviderName(AiNpcProviderSetting());
    FTLogError(s"[ai_npc]: request failed (provider \(provider), url \(this.m_generation.Url())): \(detail)");
    AiNpcLog(s"Request failed: \(detail)");
    this.ToggleTypingIndicator(false);
    this.ToggleIsGenerating(false);

    // Told here, at the single exit, so a mod learns it once whatever the cause. After the
    // state teardown, because a listener may answer by sending and `isGenerating` would refuse
    // it silently; before the carrier line, because that is the causal order.
    AiNpcPublishReplyFailed(this.m_generation.Contact(), detail);

    // Who is told depends on who asked, with the same `detail` either way. Nobody is at the
    // screen for a generation a mod asked for, so an operator line would arrive out of nowhere
    // and come back in the next prompt as something that was said.
    if this.m_generation.SpeaksFirst() {
      AiNpcResolveClientTicket(this.m_generation.Ticket(), AiNpcTicketFailed(), detail);
      return;
    }

    // The carrier line, always, and `detail` never enters it: the two messages stay distinct,
    // one in fiction and one not, rather than one line that is half of each.
    this.HandleMessage(this.m_generation.Contact(), AiNpcCarrierMessage(), true);

    // The cause, second and only on request. Not through HandleMessage: a url filed as
    // something the contact wrote would come back in the next prompt as dialogue.
    if AiNpcDebugEnabled() {
      AiNpcDeliverOrNotify(this.m_generation.Contact(),
        AiNpcDiagnosticMessage(provider, this.m_generation.Url(), detail));
    }
  }

  /// Callbacks ///
  // contactId is the one captured at send time, not the selection now: this runs after the
  // round trip plus a delay, and the player may have opened somebody else. Actions and the
  // history write are scoped to it; only the rendering asks who is currently open.
  // `carrier` marks the one text delivered here that the contact did not write: the operator
  // line a failed request ends on. It takes the same path, but anything that means "the
  // character answered" has to tell the two apart.
  // `authored` marks a line a mod wrote for a character that answers from its own script. It
  // never reached a model, so nothing about it is worth a second request.
  private func HandleMessage(contactId: String, text: String, opt carrier: Bool, opt authored: Bool) {
    let processedText = text;

    // In Dedicated mode the reply was written without the command vocabulary, so a bracket in
    // it would be prose -- the same rule a recipe that drops <commands> already follows. The
    // selection happens after delivery instead, in a request of its own.
    if !AiNpcActionsAreDedicated() {
      // Every command in one pass, against the same table the prompt was rendered from. What
      // comes back says which brackets were run, which name a real command the model fumbled,
      // and which name nothing at all -- three cases the caller has to treat differently.
      let outcome = AiNpcApplyActions(contactId, text);
      processedText = outcome.text;

      // A fumbled command is worth a second, tiny request; an invented one usually is not, but
      // both are offered in that order and the pass decides. Never for a carrier line, which
      // this mod wrote rather than a model.
      let candidates = outcome.RepairCandidates();
      if !carrier && this.TryRepairActions(contactId, processedText, candidates) {
        return;
      }

      // The repair could not run -- the day's budget is spent, the credentials have stopped
      // working, the player turned it off. A command that EXISTS still must not reach the
      // player: they would read an unclosable bracket while the prose around it says the thing
      // happened. A tag naming no command stays, because the load report names those and hiding
      // one here would hide the report.
      processedText = AiNpcStripActionTags(processedText, outcome.fumbled);
    }

    // The dots come down on every path, before the delivery decision: the generation has ended
    // whatever happens to the text next.
    this.ToggleTypingIndicator(false);

    // Where it goes is AiNpcNotification's question: a special case for the phone here is what
    // would make a request lane know what a widget is.
    AiNpcDeliverOrNotify(contactId, processedText);

    // After the delivery and BEFORE the history write, which is not an accident: the ask this
    // pass builds quotes the reply itself, and a thread that already held it would show the
    // model the same line twice. The player is not waiting on any of it -- the message is on
    // screen, and what is at stake is whether a command fires behind it.
    if !carrier && !authored {
      let actions = AiNpcActionService.Get();
      if IsDefined(actions) {
        actions.Examine(contactId, processedText);
      }
    }

    // Filed under the contact either way, since the history keeps the gap where a reply
    // failed, but marked so a listener can tell the operator apart from the person. The action
    // repair and the fact bridge refuse a carrier line outright; this line belongs in the
    // thread, so it is labelled instead.
    AiNpcAppendMessage(contactId, processedText, false, "", carrier);
    this.ToggleIsGenerating(false);

    // A mod that asked her to write first learns here, not at the send: what it asked for was
    // a message in the thread. Resolved on the generation's ticket rather than the record,
    // because a repair replaces the record and re-enters here with the corrected text.
    if this.m_generation.SpeaksFirst() {
      AiNpcResolveClientTicket(this.m_generation.Ticket(), AiNpcTicketDone(), "");
    }

    // The one point where "a turn completed for this contact" is a fact rather than a guess.
    // Costs an array size check when nothing is owed.
    let bridge = AiNpcFactBridge.Get();
    if !carrier && IsDefined(bridge) {
      bridge.NotifyReply(contactId);
    }

    // The thinking lane's one turn: the reply is on screen, the history is written, and
    // nothing the player waits for depends on what happens next.
    let memory = AiNpcMemoryService.Get();
    if IsDefined(memory) {
      memory.NotifyTurnComplete(contactId);
    }

    // Last: the warning is about the day rather than this reply, so it belongs at the bottom
    // of what the player is reading.
    this.DeliverBudgetWarning(contactId);
  }

  private func DelayedTyping() {
    let delaySystem = GameInstance.GetDelaySystem(GetGameInstance());
    let delay = RandRangeF(2.0, 4.0);
    let isAffectedByTimeDilation: Bool = false;

    delaySystem.DelayCallback(AiNpcTypingDelayCallback.Create(), delay, isAffectedByTimeDilation);
  }

  // The contact rides on the callback rather than being looked up when it fires: this is the
  // window in which the player is most likely to open somebody else.
  private func DelayedMessage(contactId: String, text: String) {
    let delaySystem = GameInstance.GetDelaySystem(GetGameInstance());
    let delay = RandRangeF(5.0, 9.0);
    let isAffectedByTimeDilation: Bool = false;

    delaySystem.DelayCallback(AiNpcMessageDelayCallback.Create(contactId, text), delay, isAffectedByTimeDilation);
  }

  // Same delivery, different beat: a person takes an unpredictable five to nine seconds, an
  // automated correspondent always the same. The regularity is the tell, and the player
  // noticing it is the point of a scripted contact.
  private func DelayedScriptedMessage(contactId: String, text: String) {
    // Authored, so it is delivered and filed like any other line and examined by nothing: a
    // contact that answers from its own script never reaches a model, and a selector run on its
    // words would be a request the mod pays for on a conversation it generated none of.
    let delaySystem = GameInstance.GetDelaySystem(GetGameInstance());
    let isAffectedByTimeDilation: Bool = false;

    delaySystem.DelayCallback(AiNpcMessageDelayCallback.CreateAuthored(contactId, text), AiNpcScriptedReplyDelay(), isAffectedByTimeDilation);
  }

  // Addressed with the turn's contact: by the time the dots are due, "who is selected" is a
  // question about a different screen.
  public func ToggleTypingIndicator(value: Bool) {
    AiNpcPublishTyping(this.m_generation.Contact(), value);
  }

  public func GetIsGenerating() -> Bool {
    return this.isGenerating;
  }

  // Asks the model once to rewrite a command that came back unroutable. True means the reply
  // is deferred, not dropped: OnRepairResponse re-enters HandleMessage with the corrected
  // text, and the typing indicator stays up so the pause reads as the character still writing.
  //
  // Whether a repair is owed is AiNpcRepair's decision, and the four conditions are handed to
  // it rather than read by it, which is what makes them assertable offline.
  // The vocabulary handed to the repair is the contact's REAL one, rendered from the same
  // table the first prompt used. It used to be the world-mechanics section, which by then
  // described the eddie transfer and nothing else -- so a fumbled rendezvous command was
  // judged against a rulebook that did not contain it, and the model was asked to correct a
  // word it had never been shown.
  private func TryRepairActions(contactId: String, text: String, candidates: array<String>) -> Bool {
    // Built before the claim, because the claim is made against the vocabulary this pass would
    // send: the builder is the one place that renders it, and the tag it aims at comes out of
    // the claim itself.
    let builder = AiNpcPassRepair.Of(contactId, "");
    let provider = AiNpcProviderSetting();
    let tag = this.m_generation.Repair().Claim(text, candidates, builder.Instruction(),
      AiNpcRetryActionsEnabled(),
      Equals(StrLen(AiNpcLlmCredentialIssue(provider)), 0),
      AiNpcHasTokenBudgetLeft());

    if Equals(StrLen(tag), 0) {
      return false;
    }
    builder.tag = tag;

    // False means not deferred, and the caller delivers the reply as written: it is already in
    // hand and only one bracket is wrong, so a transport that was not there must not cost the
    // player the message.
    return this.RepairPostRequest(builder, provider);
  }

  // The send, and only the send. What goes in the two messages is the builder's.
  private func RepairPostRequest(builder: ref<AiNpcPassRepair>, provider: AiNpcProvider) -> Bool {
    this.m_generation.SendingTo(AiNpcLlmChatUrl(provider));

    this.m_repairSerial += 1;
    let request = AiNpcPassSend(builder, provider, this.m_generation.Contact(), this,
      n"OnRepairResponse", AiNpcCliRequestId(AiNpcCliLaneRepair(), this.m_repairSerial));
    if !IsDefined(request) {
      AiNpcLog(s"Repair for \(builder.tag) could not be sent; delivering as written.");
      return false;
    }
    this.m_slot = request.slot;
    this.m_record = request.record;

    // Re-arms the watchdog, which the first answer disarmed: without it the lane would sit in
    // its generating state for good if the repair never came back, send button greyed.
    this.ToggleIsGenerating(true);
    this.ToggleTypingIndicator(true);
    AiNpcLog(s"Repair sent for \(builder.tag).");
    return true;
  }

  // Every failure here has the same answer: deliver what was already in hand. The reply reads
  // correctly apart from one bracket, so nothing below branches on the outcome -- an empty
  // correction is a valid one.
  private cb func OnRepairResponse(response: ref<HttpResponse>) {
    this.HandleRepairReply(AiNpcReply.FromHttp(response));
  }

  public func OnCliRepairReply(serial: Int32, reply: ref<AiNpcReply>) -> Void {
    if NotEquals(serial, this.m_repairSerial) {
      AiNpcLog(s"A CLI repair arrived after its turn (serial \(serial)); dropped.");
      return;
    }
    this.HandleRepairReply(reply);
  }

  private func HandleRepairReply(reply: ref<AiNpcReply>) -> Void {
    if !this.m_watchdog.IsWaiting() {
      AiNpcLog("A repair answer arrived with nothing waiting for it; dropped.");
      return;
    }

    let corrected = "";
    let root = reply.Root();

    // Recorded whatever happens to the correction: the retry is the one request the player can
    // switch off, so its cost is the number that decides the setting.
    this.m_record.Answered(reply);

    if reply.IsOk() && IsDefined(root) {
      if AiNpcReplyWasTruncated(root) {
        AiNpcLog("The repair was cut off by the output budget (max_tokens); delivering as written.");
      }
      corrected = AiNpcFirstActionTag(AiNpcExtractChatText(root));
    } else {
      AiNpcLog(s"Repair failed (status \(reply.StatusCode())); delivering as written.");
    }

    // Back through the ordinary path, because a corrected tag still has to be dispatched by
    // whoever owns it. The budget is latched until the next player message.
    this.HandleMessage(this.m_generation.Contact(), this.m_generation.Repair().Merge(corrected));
  }

  // The one place the watchdog is armed and disarmed, because `isGenerating` is the lane's
  // wait: binding the clock to it makes an unclocked wait unwritable, so a send added later
  // cannot forget to arm one.
  public func ToggleIsGenerating(value: Bool) {
    if value {
      AiNpcArmTimeout(AiNpcSpeakingTimeoutCallback.Create(this.m_watchdog.Arm()),
        AiNpcLlmRequestTimeout(AiNpcProviderSetting(), this.m_slot));
    } else {
      this.m_watchdog.Disarm();
    }

    this.isGenerating = value;

    // One of the two moments a queued reason becomes sendable; the other is a floor released.
    // Armed rather than run: starting the next generation here would replace the object the
    // lines below are still reading.
    if !value {
      AiNpcRequestSpeechDrain();
    }

    // Every surface greys its own send control: a second message sent into a generation in
    // flight is refused silently further down, which reads as a dead button. The lane states
    // the fact and paints nothing -- a widget reached from here is null whenever a reply lands
    // with the chat closed.
    AiNpcPublishGenerating(value);
  }

}


public class AiNpcMessageDelayCallback extends AiNpcSpeakingLaneCallback {
  public let contactId: String;
  public let text: String;
  // Whether a mod wrote this line instead of a model. Carried on the callback rather than
  // worked out on arrival: by the time the timer fires, nothing in the lane still knows where
  // the text came from.
  public let authored: Bool;

  protected func Run(lane: ref<AiNpcHttpSystem>) -> Void {
    lane.HandleMessage(this.contactId, this.text, false, this.authored);
  }

  public static func Create(contactId: String, text: String) -> ref<AiNpcMessageDelayCallback> {
    let self = new AiNpcMessageDelayCallback();
    self.contactId = contactId;
    self.text = text;
    return self;
  }

  public static func CreateAuthored(contactId: String, text: String) -> ref<AiNpcMessageDelayCallback> {
    let self = AiNpcMessageDelayCallback.Create(contactId, text);
    self.authored = true;
    return self;
  }
}

public class AiNpcTypingDelayCallback extends AiNpcSpeakingLaneCallback {

  protected func Run(lane: ref<AiNpcHttpSystem>) -> Void {
    lane.ToggleTypingIndicator(true);
  }

  public static func Create() -> ref<AiNpcTypingDelayCallback> {
    let self = new AiNpcTypingDelayCallback();

    return self;
  }
}
