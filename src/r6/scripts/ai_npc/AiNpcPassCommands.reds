// The two passes instructed by the command table: the repair, and the action selection.
//
// Both are handed the vocabulary and the conduct rubric, and nothing else -- no persona, no
// world, no tier. None of those decides whether a command fires.
//
// The rubric is <interactions> at its "commands" source, which is the same block a
// conversation renders and the same lane a mod contributes to. It is what says NONE, because
// a call whose whole output is one line needs a word for "nothing happened" -- and saying it
// here rather than in the ask keeps one rubric per prompt asking for the output.
//
// An empty table means this contact was never given a command, so a bracket in its reply is
// prose. Ready() is false there, and both lanes stop before they spend: repairing prose
// against an empty rulebook replaces a good reply with a worse one.

module AiNpc

class AiNpcPassCommands extends AiNpcPassBuilder {
    let contactId: String;
    // The channel of the reply these commands are read from.
    let channel: AiNpcChannelId;

    private let m_vocabulary: String;
    private let m_rendered: Bool;

    // Rendered once and kept: the lane asks for it before it decides to send, and
    // AiNpcPassSend asks again on the way out.
    func Instruction() -> String {
        if !this.m_rendered {
            let recipe = this.Recipe();
            let ctx = AiNpcBuildContactContext(this.contactId, "", this.channel);
            let vocabulary = AiNpcActionVocabularyFor(this.contactId, recipe, ctx);
            // No vocabulary, no instruction: Ready() reads this, and a conduct rubric with no
            // commands under it would send a request about nothing.
            if NotEquals(StrLen(vocabulary), 0) {
                this.m_vocabulary = AiNpcRenderInteractions(this.contactId, recipe, ctx) + vocabulary;
            }
            this.m_rendered = true;
        }
        return this.m_vocabulary;
    }

    func Ready() -> Bool {
        return NotEquals(StrLen(this.Instruction()), 0);
    }
}

// The bracket that was written, offered back for correction.
//
// The tag is set after construction, and it has to be: the claim that produces it is made
// AGAINST the vocabulary this pass would send, so the builder exists before the tag it aims
// at. Ready() is what makes that order safe rather than merely observed -- an empty tag asks
// a model to correct a blank line.
class AiNpcPassRepair extends AiNpcPassCommands {
    let tag: String;

    static func Of(contactId: String, channel: AiNpcChannelId) -> ref<AiNpcPassRepair> {
        let self = new AiNpcPassRepair();
        self.contactId = contactId;
        self.channel = channel;
        return self;
    }

    func Pass() -> String {
        return AiNpcLaneRepair();
    }

    func Ask() -> String {
        return AiNpcRepairAsk(this.tag);
    }

    func Ready() -> Bool {
        return super.Ready() && NotEquals(StrLen(this.tag), 0);
    }
}

// The thread plus the reply just written, ending on a question rather than on the handover:
// this pass reads what was written instead of continuing it.
class AiNpcPassActions extends AiNpcPassCommands {
    let npcName: String;
    let transcript: String;
    let reply: String;

    static func Of(contactId: String, npcName: String, transcript: String,
                   reply: String, channel: AiNpcChannelId) -> ref<AiNpcPassActions> {
        let self = new AiNpcPassActions();
        self.contactId = contactId;
        self.channel = channel;
        self.npcName = npcName;
        self.transcript = transcript;
        self.reply = reply;
        return self;
    }

    func Pass() -> String {
        return AiNpcLaneActions();
    }

    func Ask() -> String {
        return AiNpcActionSelectorAsk(this.transcript, this.npcName, this.reply);
    }
}
