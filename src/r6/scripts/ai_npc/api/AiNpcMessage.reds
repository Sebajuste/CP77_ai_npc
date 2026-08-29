// One stored line of a conversation, and who wrote it.
//
// In api\ because AiNpcReadConversation hands an array of these back: a consumer reads the
// fields, so the record is part of the contract even though nothing outside builds one. The
// operations over it -- append, trim, undo, transcript -- are the pure model in
// AiNpcHistory.reds, which is where they stay.

module AiNpc

public class AiNpcMessage {
    public let fromPlayer: Bool;
    public let text: String;

    // Absolute in-game seconds. 0 means unknown -- what every message written before this
    // field reads back as -- and must be treated as "no answer", never as midnight of day
    // zero. Absolute rather than the "3:45pm" the prompt shows: a formatted clock cannot be
    // subtracted, so it says when a message was sent but never how long ago.
    public let gameTimeSeconds: Int32;
}
