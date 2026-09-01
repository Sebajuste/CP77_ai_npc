// What an answer is, once the transport is out of the way.
//
// One transport now -- ai_npc.dll, for every provider -- and exactly ONE handler per lane that
// reads an answer. This type is what made that possible while there were two: an answer typed
// on `HttpResponse` would have forced every caller to be an HTTP caller. RedHttpClient is gone
// and the seam stays, because what it separates is the lane from the wire, not one wire from
// another.
//
// Three facts, and not one more: a status code, a parsed body, and the day the answer was
// dated. That is everything the lanes, the failure messages and the token ledger read from a
// response.
//
// A value, not a class hierarchy: an answer from the CLI and one from OpenRouter differ in
// how they were obtained and in nothing else. Pure, so the offline suite can build one
// without a session.

module AiNpc

import RedData.Json.*

public class AiNpcReply {
    private let m_status: Int32;
    private let m_text: String;
    private let m_root: ref<JsonObject>;
    private let m_date: String;

    /// The two factories ///

    // The plugin's answer. `body` is OpenAI-shaped JSON, `status` plays the part of the HTTP
    // status code, and `date` is the machine clock in Date-header format -- see
    // AiNpcCliRequest for why the plugin has to supply that last one.
    public static func FromCli(status: Int32, body: String, date: String) -> ref<AiNpcReply> {
        return AiNpcReply.Of(status, body, date);
    }

    // The empty answer, for a send that never happened. Status 0, nothing to parse: the same
    // thing a request that never left the client comes back as, and it is treated identically
    // downstream rather than needing a branch of its own.
    public static func Nothing() -> ref<AiNpcReply> {
        return AiNpcReply.Of(0, "", "");
    }

    private static func Of(status: Int32, text: String, date: String) -> ref<AiNpcReply> {
        let self = new AiNpcReply();
        self.m_status = status;
        self.m_text = text;
        self.m_date = date;

        // Parsed once, here, rather than at each reader. ParseJson is asked nothing when
        // there is nothing to ask it about, so an empty body is a null root and not a
        // parser complaint in the log.
        if NotEquals(StrLen(text), 0) {
            self.m_root = AiNpcAsJsonObject(ParseJson(text));
        }
        return self;
    }

    /// What a lane reads ///

    public func StatusCode() -> Int32 {
        return this.m_status;
    }

    // 200 and nothing else. The lanes used to compare against HttpStatus.OK, which is the
    // same test through a type that only one of the two transports has.
    public func IsOk() -> Bool {
        return Equals(this.m_status, 200);
    }

    // Null when the body was absent or was not a JSON object -- both of which are ordinary
    // and both of which the lanes already answer for.
    public func Root() -> ref<JsonObject> {
        return this.m_root;
    }

    // The day this answer belongs to, for the token ledger. Empty is allowed and means "do
    // not roll the day"; see AiNpcUsageService.Charge.
    public func Date() -> String {
        return this.m_date;
    }

    // The raw body, for the debug dump only. Everything that makes a decision reads Root().
    public func Text() -> String {
        return this.m_text;
    }
}
