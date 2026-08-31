// The thinking pass: what a character keeps of the turns that just left the window.
//
// The instruction asks for a CHRONICLE exactly when the body carries an ARCHIVE to build one
// from, so the two halves are decided once, here, and the lane reads that decision back rather
// than taking it a second time.

module AiNpc

class AiNpcPassCompaction extends AiNpcPassBuilder {
    let base: ref<AiNpcMemory>;
    let npcName: String;
    let transcript: String;
    let folding: Bool;
    let exact: Bool;

    static func Of(base: ref<AiNpcMemory>, npcName: String,
                   transcript: String) -> ref<AiNpcPassCompaction> {
        let self = new AiNpcPassCompaction();
        self.base = base;
        self.npcName = npcName;
        self.transcript = transcript;
        self.folding = AiNpcMemoryShouldFold(base);
        self.exact = AiNpcMemoryChronicleExact();
        return self;
    }

    func Pass() -> String {
        return AiNpcLaneThinking();
    }

    func Instruction() -> String {
        return AiNpcMemoryInstruction(this.folding);
    }

    func Ask() -> String {
        return AiNpcMemoryRequestBody(this.base, this.npcName, AiNpcGenderFact(),
            this.transcript, this.exact);
    }
}
