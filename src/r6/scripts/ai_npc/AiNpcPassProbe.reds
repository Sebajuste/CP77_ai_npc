// The test pass: two sentences, sent on the slot the reply is written on.
//
// It carries no contact and no recipe worth reading. What it proves is the transport, the
// credentials and the model -- and it must prove them on the slot the player will actually
// speak on, which is AiNpcPassSlotNameIn's business, not this one's.

module AiNpc

class AiNpcPassProbe extends AiNpcPassBuilder {
    static func Of() -> ref<AiNpcPassProbe> {
        return new AiNpcPassProbe();
    }

    func Pass() -> String {
        return AiNpcLaneTest();
    }

    func Instruction() -> String {
        return "You are a connection test. Answer with a single word.";
    }

    func Ask() -> String {
        return "Reply with the single word OK.";
    }
}
