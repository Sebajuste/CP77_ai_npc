// The two passes instructed by the command table: the repair, and the action selection.
//
// Both are handed the vocabulary and nothing else -- no persona, no world, no tier. None of
// them decides whether a command fires.
//
// An empty table means this contact was never given a command, so a bracket in its reply is
// prose. Ready() is false there, and both lanes stop before they spend: repairing prose
// against an empty rulebook replaces a good reply with a worse one.

module AiNpc

class AiNpcPassCommands extends AiNpcPassBuilder {
    let contactId: String;

    private let m_vocabulary: String;
    private let m_rendered: Bool;

    // Rendered once and kept: the lane asks for it before it decides to send, and
    // AiNpcPassSend asks again on the way out.
    func Instruction() -> String {
        if !this.m_rendered {
            this.m_vocabulary = AiNpcActionVocabularyFor(this.contactId, this.Recipe());
            this.m_rendered = true;
        }
        return this.m_vocabulary;
    }

    func Ready() -> Bool {
        return NotEquals(StrLen(this.Instruction()), 0);
    }
}

// The bracket that was written, offered back for correction.
class AiNpcPassRepair extends AiNpcPassCommands {
    let tag: String;

    static func Of(contactId: String, tag: String) -> ref<AiNpcPassRepair> {
        let self = new AiNpcPassRepair();
        self.contactId = contactId;
        self.tag = tag;
        return self;
    }

    func Pass() -> String {
        return AiNpcLaneRepair();
    }

    func Ask() -> String {
        return AiNpcRepairAsk(this.tag);
    }
}

// The thread plus the reply just written, ending on a question rather than on the handover:
// this pass reads what was written instead of continuing it.
class AiNpcPassActions extends AiNpcPassCommands {
    let npcName: String;
    let transcript: String;
    let reply: String;

    static func Of(contactId: String, npcName: String, transcript: String,
                   reply: String) -> ref<AiNpcPassActions> {
        let self = new AiNpcPassActions();
        self.contactId = contactId;
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
