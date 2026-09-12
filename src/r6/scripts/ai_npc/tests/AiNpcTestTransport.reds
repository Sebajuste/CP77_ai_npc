module AiNpc

import RedData.Json.*
import Codeware.*

// La requete et son retour : chien de garde, pannes, lecture des reponses, budget.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

func AiNpcTestJson(text: String) -> ref<JsonObject> {
    return AiNpcAsJsonObject(ParseJson(text));
}

func AiNpcTestResponseExtraction(t: ref<AiNpcTestRunner>) -> Void {
    let ok = AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":\"hey there\"}}]}");
    t.EqString("chat/happy path", AiNpcExtractChatText(ok), "hey there");

    // Regression: these all used to be unchecked casts. An error payload produced a null
    // at the first step and took the whole response callback down.
    t.EqString("chat/regression: error body instead of choices",
        AiNpcExtractChatText(AiNpcTestJson("{\"error\":{\"message\":\"rate limited\"}}")), "");
    t.EqString("chat/regression: empty choices array",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[]}")), "");
    t.EqString("chat/regression: choice without message",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"finish_reason\":\"stop\"}]}")), "");
    t.EqString("chat/regression: content is not a string",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":null}}]}")), "");
    t.EqString("chat/regression: choices is not an array",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":\"nope\"}")), "");
    t.EqString("chat/empty document", AiNpcExtractChatText(AiNpcTestJson("{}")), "");
    t.EqString("chat/null root", AiNpcExtractChatText(null), "");

    // Reasoning models. The reply is what lies outside the think spans -- see
    // AiNpcStripThinking for why an unclosed span swallows the rest of the text.
    t.EqString("think/span before the reply is removed",
        AiNpcStripThinking("<think>keep it short</think>Yeah. Garage, an hour."), "Yeah. Garage, an hour.");
    t.EqString("think/blank line left by the span goes with it",
        AiNpcStripThinking("<think>notes</think>\n\n  Yeah."), "Yeah.");
    t.EqString("think/text on both sides is kept",
        AiNpcStripThinking("Yeah. <think>notes</think>Garage."), "Yeah. Garage.");
    t.EqString("think/several spans", AiNpcStripThinking("<think>a</think>One. <think>b</think>Two."), "One. Two.");
    t.EqString("think/nothing but thinking", AiNpcStripThinking("<think>all of it</think>"), "");
    t.EqString("think/unclosed span swallows the rest", AiNpcStripThinking("Wait. <think>cut off here"), "Wait.");
    t.EqString("think/an ordinary reply is untouched", AiNpcStripThinking("Yeah, meet me there."), "Yeah, meet me there.");
    t.EqString("think/empty stays empty", AiNpcStripThinking(""), "");

    t.EqString("chat/thinking is stripped from the content",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":\"<think>short</think>Yeah.\"}}]}")), "Yeah.");

    // The costly case: content is empty and the whole turn went to another field. Read as
    // "nothing to say", this used to spend the player's tokens on a carrier message.
    t.EqString("chat/answer in reasoning when content is empty",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":\"\",\"reasoning\":\"On my way.\"}}]}")), "On my way.");
    t.EqString("chat/reasoning_content is read too",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"reasoning_content\":\"On my way.\"}}]}")), "On my way.");
    t.EqString("chat/content wins when both are present",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":\"Yeah.\",\"reasoning\":\"she asked\"}}]}")), "Yeah.");

    // A content field holding nothing but thinking is empty for this purpose, so it must
    // fall through to the other field exactly as an empty string does.
    t.EqString("chat/thinking-only content falls through",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":\"<think>x</think>\",\"reasoning\":\"Later.\"}}]}")), "Later.");

    // And with nothing anywhere it still degrades to "no text", which is what the caller
    // turns into a stated failure rather than a blank bubble.
    t.EqString("chat/thinking-only content and nothing else",
        AiNpcExtractChatText(AiNpcTestJson("{\"choices\":[{\"message\":{\"content\":\"<think>x</think>\"}}]}")), "");

    t.EqString("error/nested message",
        AiNpcExtractApiError(AiNpcTestJson("{\"error\":{\"message\":\"quota exceeded\"}}")), "quota exceeded");
    t.EqString("error/top-level message",
        AiNpcExtractApiError(AiNpcTestJson("{\"message\":\"no workers\"}")), "no workers");
    t.EqString("error/error as a string",
        AiNpcExtractApiError(AiNpcTestJson("{\"error\":\"bad request\"}")), "bad request");
    t.EqString("error/none present",
        AiNpcExtractApiError(AiNpcTestJson("{\"choices\":[]}")), "");
    t.EqString("error/null root", AiNpcExtractApiError(null), "");
}

/// Action tags ///

func AiNpcTestWatchdog(t: ref<AiNpcTestRunner>) -> Void {
    let watchdog = new AiNpcWatchdog();

    let first = watchdog.Arm();
    t.Check("watchdog/a live timer is answered", watchdog.IsCurrent(first));

    // The case the class exists for, and the one a boolean gets wrong: a request answers,
    // the next goes out, and the first one's timer -- which cannot be cancelled -- fires in
    // the middle of it. It must have nothing to say.
    watchdog.Disarm();
    let second = watchdog.Arm();
    t.Check("watchdog/a stale timer is ignored", !watchdog.IsCurrent(first));
    t.Check("watchdog/the timer that replaced it is answered", watchdog.IsCurrent(second));
    t.Check("watchdog/names are never reused", NotEquals(first, second));

    // After the wait ends nothing is answerable, so a timer arriving between the answer and
    // the next send finds no one to report to.
    watchdog.Disarm();
    t.Check("watchdog/nothing is current once the wait ended", !watchdog.IsCurrent(second));

    // Regression: an answer that arrives after its own timeout was handled as the current
    // one, on a lane that had already been given to another character. IsCurrent cannot
    // catch it -- the late answer carries no timer name -- so the reply handlers ask this
    // instead, and it has to distinguish "waiting" from "a name no timer happens to hold".
    let third = new AiNpcWatchdog();
    t.Check("watchdog/nothing is waiting before the first send", !third.IsWaiting());
    third.Arm();
    t.Check("watchdog/a sent request is waiting", third.IsWaiting());
    third.Disarm();
    t.Check("watchdog/an answered request is not", !third.IsWaiting());
    third.Arm();
    third.Arm();
    third.Disarm();
    t.Check("watchdog/and one disarm ends the wait whatever was armed before", !third.IsWaiting());

    // Every backend must get a real budget: a zero here would disarm the whole mechanism
    // silently, by timing every request out on the frame it was sent.
    t.Check("timeout/openrouter has a budget", AiNpcLlmRequestTimeout(AiNpcProvider.OpenRouter, null) > 0.0);
    t.Check("timeout/claude cli has a budget", AiNpcLlmRequestTimeout(AiNpcProvider.ClaudeCli, null) > 0.0);
    t.Check("timeout/codex cli has a budget", AiNpcLlmRequestTimeout(AiNpcProvider.CodexCli, null) > 0.0);

    // Every lane runs in the plugin, which keeps each lane's own clock; this is only the
    // backstop for a plugin that never answers, so no lane gets a shorter one.
    t.Check("timeout/every plugin lane gets the same backstop",
        Equals(AiNpcLlmRequestTimeout(AiNpcProvider.ClaudeCli, null), AiNpcLlmRequestTimeout(AiNpcProvider.OpenRouter, null)));
    t.Check("timeout/both cli lanes agree",
        Equals(AiNpcLlmRequestTimeout(AiNpcProvider.ClaudeCli, null), AiNpcLlmRequestTimeout(AiNpcProvider.CodexCli, null)));

    // Which transport carries which provider, asked in one place and read by AiNpcSendChat.
    // Getting this wrong is not a compile error: it is a request posted to "cli://claude".
    t.Check("transport/openrouter is not a cli lane", !AiNpcProviderIsCli(AiNpcProvider.OpenRouter));
    t.Check("transport/claude is a cli lane", AiNpcProviderIsCli(AiNpcProvider.ClaudeCli));
    t.Check("transport/codex is a cli lane", AiNpcProviderIsCli(AiNpcProvider.CodexCli));

    // Toutes les voies passent par le plugin depuis que RedHttpClient a ete retire. La question
    // « est-ce une voie CLI » reste, elle, un decoupage different : ce qui en depend est
    // l'espace de noms des modeles et l'absence de cle, pas le transport.
    t.Check("transport/openrouter runs in the plugin",
        AiNpcProviderIsNative(AiNpcProvider.OpenRouter));
    t.Check("transport/and so do the cli lanes",
        AiNpcProviderIsNative(AiNpcProvider.ClaudeCli));

}

// The debug-mode second message. Pure, so what is covered here is the whole of it except
// the Mod Settings gate, which is one call at the failure site.
//
// What matters is that the three things a bug report needs survive the formatting: which
// provider was in force, which url was attempted, and what went wrong. The transport advice
// above is worthless if it is the part that gets dropped on the way to the player.

// The debug-mode second message. Pure, so what is covered here is the whole of it except
// the Mod Settings gate, which is one call at the failure site.
//
// What matters is that the three things a bug report needs survive the formatting: which
// provider was in force, which url was attempted, and what went wrong. The transport advice
// above is worthless if it is the part that gets dropped on the way to the player.
func AiNpcTestDiagnosticMessage(t: ref<AiNpcTestRunner>) -> Void {
    let detail = AiNpcDescribeTransportFailure("https://openrouter.ai/api/v1/chat/completions", "HTTP 0");
    let message = AiNpcDiagnosticMessage("OpenRouter", "https://openrouter.ai/api/v1/chat/completions", detail);

    t.Check("diagnostic/names the provider", StrContains(message, "OpenRouter"));
    t.Check("diagnostic/names the url", StrContains(message, "https://openrouter.ai"));
    t.Check("diagnostic/carries the cause", StrContains(message, detail));

    // Greppable in a pasted screenshot, a log and the journal alike: the same marker
    // FTLogError writes.
    t.Check("diagnostic/carries the mod marker", StrContains(message, "[ai_npc]"));

    // It is the counterpart of the carrier line, never a substitute: a diagnostic that
    // reads as dialogue would put a url in the fiction.
    t.Check("diagnostic/is not the carrier line",
        NotEquals(message, AiNpcCarrierMessageFor(AiNpcLanguage.English)));

    // A request can die before m_requestUrl is set, and a detail is not guaranteed either.
    // Neither may produce a dangling label -- "url" with nothing after it reads as a second
    // failure on top of the first one.
    let noUrl = AiNpcDiagnosticMessage("LocalBridge", "", "no answer within 240s");
    t.Check("diagnostic/no url means no url line", !StrContains(noUrl, "url "));
    t.Check("diagnostic/no url keeps the cause", StrContains(noUrl, "no answer within 240s"));
    t.EqString("diagnostic/provider alone is still a message",
        AiNpcDiagnosticMessage("OpenAI", "", ""), "[ai_npc] provider OpenAI");
}

func AiNpcTestTransportFailure(t: ref<AiNpcTestRunner>) -> Void {
    let httpsAdvice = AiNpcDescribeTransportFailure("https://openrouter.ai/api/v1/chat/completions", "HTTP 0");

    // "HTTP 0" is the useless message this function exists to replace.
    t.Check("transport/https is explained", NotEquals(httpsAdvice, "HTTP 0"));

    // -no-tls is the one cause a player cannot observe from inside the game.
    t.Check("transport/https names the launch flag", StrContains(httpsAdvice, "-no-tls"));

    // No lane dials plain http since the local bridge was removed: its old advice would
    // describe a mod that no longer exists, so that url keeps the caller's detail.
    t.EqString("transport/plain http falls back",
        AiNpcDescribeTransportFailure("http://127.0.0.1:8787/v1/chat/completions", "HTTP 0"), "HTTP 0");

    // Regression: the https branch is the one that was missing. Reported as a dead bridge,
    // it sent a player who was on a cloud provider to go debug a local server they were not
    // using.
    t.Check("transport/https does not blame the bridge", !StrContains(httpsAdvice, "bridge unreachable"));

    // Regression: status 0 is the only thing actually observed here, so the advice must
    // OFFER causes, never assert one. "bridge unreachable - needs ... AND ..." reads as a
    // diagnosis, and the real cause once was a request body that was not valid UTF-8. "Could
    // be" is the marker of the hedge.
    t.Check("transport/https offers causes rather than asserting one",
        StrContains(httpsAdvice, "status 0") && StrContains(httpsAdvice, "Could be"));

    // Anything that is not a url the mod could have posted to keeps the caller's detail:
    // inventing TLS advice for an unknown scheme would be a guess.
    t.EqString("transport/unknown scheme falls back", AiNpcDescribeTransportFailure("", "HTTP 0"), "HTTP 0");
    t.EqString("transport/non-status detail is preserved",
        AiNpcDescribeTransportFailure("ftp://example", "the reply could not be parsed"),
        "the reply could not be parsed");

    // The provider name reaches the log for every member; "unknown" there would hide the
    // very setting a reader is trying to confirm.
    t.EqString("transport/provider name OpenRouter", AiNpcProviderName(AiNpcProvider.OpenRouter), "OpenRouter");

    // These two are not labels. They are the word sent across to the plugin, which keys its
    // own registry on them, so a rename here is a rename in Registry.cpp on the same day.
    t.EqString("transport/provider name ClaudeCli", AiNpcProviderName(AiNpcProvider.ClaudeCli), "ClaudeCli");
    t.EqString("transport/provider name CodexCli", AiNpcProviderName(AiNpcProvider.CodexCli), "CodexCli");
}

/// The CLI transport ///

// The request id, which is the whole of the CLI transport's routing.
//
// Worth asserting precisely because it looks too simple to get wrong: it is arithmetic, it
// has no game dependency, and if it were wrong the symptom would be a reply delivered to the
// wrong lane -- a compaction answer written into a conversation, or a character's reply
// silently discarded as a stale test. None of which would name this function.

// The request id, which is the whole of the CLI transport's routing.
//
// Worth asserting precisely because it looks too simple to get wrong: it is arithmetic, it
// has no game dependency, and if it were wrong the symptom would be a reply delivered to the
// wrong lane -- a compaction answer written into a conversation, or a character's reply
// silently discarded as a stale test. None of which would name this function.
func AiNpcTestCliRouting(t: ref<AiNpcTestRunner>) -> Void {
    let lanes = [AiNpcCliLaneChat(), AiNpcCliLaneRepair(), AiNpcCliLaneMemory(), AiNpcCliLaneTest()];

    let i = 0;
    while i < ArraySize(lanes) {
        let id = AiNpcCliRequestId(lanes[i], 42);
        t.Check(s"cli/lane \(lanes[i]) survives the round trip", Equals(AiNpcCliLaneOf(id), lanes[i]));
        t.Check(s"cli/serial survives lane \(lanes[i])", Equals(AiNpcCliSerialOf(id), 42));
        i += 1;
    }

    // Every lane must be distinguishable from every other, or two of them share a mailbox.
    let j = 0;
    while j < ArraySize(lanes) {
        let k = j + 1;
        while k < ArraySize(lanes) {
            t.Check(s"cli/lane \(lanes[j]) is not lane \(lanes[k])", NotEquals(lanes[j], lanes[k]));
            k += 1;
        }
        j += 1;
    }

    // The serial wraps rather than overflowing into the lane digit. A serial that leaked
    // upward would deliver a chat reply to the repair lane after a million requests -- which
    // is unreachable in one session, and exactly the kind of thing that is never tested.
    let wrapped = AiNpcCliRequestId(AiNpcCliLaneChat(), AiNpcCliRequestSpan() + 7);
    t.Check("cli/a wrapped serial stays in its lane",
        Equals(AiNpcCliLaneOf(wrapped), AiNpcCliLaneChat()));
    t.Check("cli/a wrapped serial wraps to its remainder", Equals(AiNpcCliSerialOf(wrapped), 7));
}

// The one value both transports hand to the lanes.
//
// The CLI half is what can be built without a session, so it is what is asserted here. The
// HTTP half needs a live HttpResponse and is covered by the launch checklist instead.

// The one value both transports hand to the lanes.
//
// The CLI half is what can be built without a session, so it is what is asserted here. The
// HTTP half needs a live HttpResponse and is covered by the launch checklist instead.
func AiNpcTestReply(t: ref<AiNpcTestRunner>) -> Void {
    let ok = AiNpcReply.FromCli(200,
        "{\"choices\":[{\"message\":{\"content\":\"OK\"},\"finish_reason\":\"stop\"}]}",
        "Mon, 24 Aug 2026 11:00:00 GMT");
    t.Check("reply/a 200 is ok", ok.IsOk());
    t.Check("reply/the body is parsed", IsDefined(ok.Root()));
    t.EqString("reply/the text comes back out", AiNpcExtractChatText(ok.Root()), "OK");
    t.EqString("reply/the date is carried", ok.Date(), "Mon, 24 Aug 2026 11:00:00 GMT");

    // A typed CLI failure arrives in the same shape an HTTP provider's error body has, which
    // is what lets one failure path serve both transports. If this stopped holding, a CLI
    // that is not signed in would reach the player as a bare status code.
    let failed = AiNpcReply.FromCli(401,
        "{\"error\":{\"message\":\"not signed in - run: claude login\"}}", "");
    t.Check("reply/a 401 is not ok", !failed.IsOk());
    t.EqString("reply/the typed error reads back",
        AiNpcExtractApiError(failed.Root()), "not signed in - run: claude login");

    // Nothing at all. Status 0 with no body is what a request that never left looks like on
    // either transport, and it must not be a parser complaint.
    let nothing = AiNpcReply.Nothing();
    t.Check("reply/nothing is not ok", !nothing.IsOk());
    t.Check("reply/nothing has no root", !IsDefined(nothing.Root()));
    t.Check("reply/nothing has status 0", Equals(nothing.StatusCode(), 0));

    // Garbage on stdout: the plugin promises OpenAI-shaped JSON, and the day it breaks that
    // promise the lane must report a failure rather than crash on a null root.
    let garbage = AiNpcReply.FromCli(200, "claude: command not found", "");
    t.Check("reply/garbage has no root", !IsDefined(garbage.Root()));
    t.EqString("reply/garbage yields no text", AiNpcExtractChatText(garbage.Root()), "");
}

/// Characters versus bytes ///

// Guards the difference between the two, which is invisible in English and silent in every
// other language.
//
// The literals below are the whole point of the fixture: "é" is one character and two
// bytes, so every assertion that reads as trivial here is one the byte-counting version
// FAILS. Written with ASCII only, this file would pass against the code that shipped the
// bug -- which is exactly what happened for as long as the mod was only ever typed into in
// English.

// Guards the difference between the two, which is invisible in English and silent in every
// other language.
//
// The literals below are the whole point of the fixture: "é" is one character and two
// bytes, so every assertion that reads as trivial here is one the byte-counting version
// FAILS. Written with ASCII only, this file would pass against the code that shipped the
// bug -- which is exactly what happened for as long as the mod was only ever typed into in
// English.
func AiNpcTestUtf8(t: ref<AiNpcTestRunner>) -> Void {
    let plain = "abc";
    let accented = "éàü";

    t.EqInt("utf8/len counts ASCII", AiNpcUtf8Len(plain), 3);
    t.EqInt("utf8/len counts characters, not bytes", AiNpcUtf8Len(accented), 3);
    t.EqInt("utf8/len of nothing", AiNpcUtf8Len(""), 0);

    // The regression itself: one backspace on an accent must remove the whole accent. The
    // shipped version removed one byte of the two and left the other inside the string.
    t.EqString("utf8/regression: backspace removes a whole accent",
        AiNpcUtf8DropLast("sélectionné"), "sélectionn");
    t.EqString("utf8/backspace on ASCII", AiNpcUtf8DropLast(plain), "ab");
    t.EqString("utf8/backspace on nothing is nothing", AiNpcUtf8DropLast(""), "");
    t.EqString("utf8/backspace on one character empties it", AiNpcUtf8DropLast("é"), "");

    // Cutting: the two ends, and the out-of-range arguments a caller is allowed to hand over
    // rather than check -- an unchecked subtraction is where the bug came from.
    t.EqString("utf8/left cuts characters", AiNpcUtf8Left(accented, 2), "éà");
    t.EqString("utf8/right cuts characters", AiNpcUtf8Right(accented, 2), "àü");
    t.EqString("utf8/left past the end returns everything", AiNpcUtf8Left(accented, 99), accented);
    t.EqString("utf8/right past the end returns everything", AiNpcUtf8Right(accented, 99), accented);
    t.EqString("utf8/left of nothing", AiNpcUtf8Left(accented, 0), "");
    t.EqString("utf8/right of a negative count", AiNpcUtf8Right(accented, -3), "");

    // A field showing its tail: the visible window is a promise about characters, so an
    // accented value must show as many of them as an ASCII one.
    t.EqInt("utf8/a tail window holds as many accented characters as plain ones",
        AiNpcUtf8Len(AiNpcUtf8Right("ééééééé", 4)), AiNpcUtf8Len(AiNpcUtf8Right("aaaaaaa", 4)));

    // Cleaning leaves well-formed text alone -- byte for byte, since dropping an accent
    // while keeping the character count is precisely the failure being guarded against.
    t.EqString("utf8/clean keeps ASCII", AiNpcUtf8Clean(plain), plain);
    t.EqString("utf8/clean keeps accents", AiNpcUtf8Clean(accented), accented);
    t.EqString("utf8/clean keeps punctuation and spaces", AiNpcUtf8Clean("Ça va ? Oui !"), "Ça va ? Oui !");
    t.EqString("utf8/clean of nothing", AiNpcUtf8Clean(""), "");
    t.Check("utf8/well-formed text reads as clean", AiNpcUtf8IsClean("Ça va ? Oui !"));
    t.Check("utf8/nothing reads as clean", AiNpcUtf8IsClean(""));

    // NOT COVERED HERE, and it must not be claimed: what these do to a string that is
    // ALREADY malformed. A stray byte cannot be written as a literal in this file, so the
    // detector's behaviour on one is decided by the Codeware native and can only be
    // established by a live run. Everything above is the half that holds either way -- the
    // editing is correct, so the mod no longer PRODUCES a stray byte; the cleaning is a
    // second line for values that arrive from elsewhere.
}

// Guards the operator line the player reads when anything at all goes wrong.
//
// This is the mod's only user-visible failure text, and it is the last thing anyone will
// think to check by hand -- it only ever appears when something else is already broken.

// Guards the operator line the player reads when anything at all goes wrong.
//
// This is the mod's only user-visible failure text, and it is the last thing anyone will
// think to check by hand -- it only ever appears when something else is already broken.
func AiNpcTestCarrierMessage(t: ref<AiNpcTestRunner>) -> Void {
    let english = AiNpcCarrierMessageFor(AiNpcLanguage.English);
    let french = AiNpcCarrierMessageFor(AiNpcLanguage.French);

    t.EqString("carrier/French", french,
        "Réseau mobile Night City injoignable. Contactez notre support au +1 555 0134");
    t.EqString("carrier/English", english,
        "Night City mobile network unreachable. Contact support at +1 555 0134");

    // The support number is the one thing a player might act on, so it has to survive in
    // every translation -- and stay inside the +1 555 range reserved for fiction, which is
    // what guarantees the mod never sends anyone to a real telephone.
    let i = 0;
    let languages = [AiNpcLanguage.English, AiNpcLanguage.Spanish, AiNpcLanguage.French,
                     AiNpcLanguage.German, AiNpcLanguage.Italian, AiNpcLanguage.Portuguese,
                     AiNpcLanguage.Russian, AiNpcLanguage.Ukraine];
    while i < ArraySize(languages) {
        let text = AiNpcCarrierMessageFor(languages[i]);
        t.Check(s"carrier/\(i) is translated", NotEquals(text, english) || Equals(i, 0));
        t.Check(s"carrier/\(i) carries the number", StrContains(text, "+1 555 0134"));
        t.Check(s"carrier/\(i) is not empty", StrLen(text) > 20);

        // Regression: no failure detail may leak back into the bubble. These are the
        // shapes the player used to be shown, and the reason this indirection exists.
        t.Check(s"carrier/\(i) leaks no status code", !StrContains(text, "HTTP"));
        t.Check(s"carrier/\(i) leaks no config path", !StrContains(text, "settings.json"));
        t.Check(s"carrier/\(i) leaks no marker", !StrContains(text, "NO SIGNAL"));
        i += 1;
    }

    // Accented text must survive the source file, the compiler and the string type intact.
    // A mojibake round trip is invisible at compile time -- this is the only thing that
    // would catch it before a player sees a mangled two-character sequence.
    t.Check("carrier/French keeps its accent", StrContains(french, "Réseau"));
    t.Check("carrier/French is not mojibake", !StrContains(french, "Ã"));
}

/// Conversation memory ///

// A memory built in one expression, for assertions that care about one slot at a time.

// A string of exactly `count` characters, with no spaces in it.
//
// No spaces on purpose: AiNpcMemoryClampTo backs up to a word boundary unless that would cost
// more than a quarter of the line, so a run of one character is the only filler whose clamped
// length is arithmetic rather than a property of where the spaces fell.
func AiNpcTestFill(count: Int32) -> String {
    let out = "";
    let i = 0;
    while i < count {
        out += "x";
        i += 1;
    }
    return out;
}

/// Repair policy: whether a broken command is worth a second request ///

// Four conditions decide it and each one is a real failure that was reasoned about once. They
// are arguments rather than lookups precisely so this suite can state them.

// Four conditions decide it and each one is a real failure that was reasoned about once. They
// are arguments rather than lookups precisely so this suite can state them.
func AiNpcTestRepairPolicy(t: ref<AiNpcTestRunner>) -> Void {
    let broken = "Meet me at eleven. [ACTION:KABUKI_SF:2200:1000:1]";
    // What the dispatcher could not run, and the block the model was shown. Handed in rather
    // than rescanned: whether a bracket names a real command is the claim table's answer, and
    // a second answer computed inside the repair is a second answer to drift.
    let candidates = ["[ACTION:KABUKI_SF:2200:1000:1]"];
    let vocabulary = "<actions>[ACTION:TRICK:{place}:{hour}]: when you agree a meeting.</actions>";

    let a = new AiNpcRepair();
    t.EqString("repair/an unroutable command is claimed",
        a.Claim(broken, candidates, vocabulary, true, true, true), "[ACTION:KABUKI_SF:2200:1000:1]");

    // The budget is one, and it is what stops a model that keeps writing the same broken
    // command from buying requests until the player closes the game.
    t.EqString("repair/the budget is spent after one",
        a.Claim(broken, candidates, vocabulary, true, true, true), "");

    // Nothing to correct AGAINST: a contact with no vocabulary was never given commands, so
    // a bracket in its reply is prose.
    let b = new AiNpcRepair();
    t.EqString("repair/no vocabulary, no repair", b.Claim(broken, candidates, "", true, true, true), "");

    // A dead credential makes the repair worse than the broken tag: the player would wait
    // twice for the same message.
    let c = new AiNpcRepair();
    t.EqString("repair/unusable credentials, no repair",
        c.Claim(broken, candidates, vocabulary, true, false, true), "");

    let d = new AiNpcRepair();
    t.EqString("repair/the option off means no repair",
        d.Claim(broken, candidates, vocabulary, false, true, true), "");

    let e = new AiNpcRepair();
    let nothingWrong: array<String>;
    t.EqString("repair/a clean reply is not repaired",
        e.Claim("Meet me at eleven.", nothingWrong, vocabulary, true, true, true), "");

    // A repair is a second request, so a spent day refuses it like any other. Nothing the
    // player is about to read changes: the reply exists and reads correctly, bracket aside.
    let h = new AiNpcRepair();
    t.EqString("repair/a spent budget buys no retry",
        h.Claim(broken, candidates, vocabulary, true, true, false), "");

    // Only the bracket is replaced: the prose the player is about to read cannot change.
    let f = new AiNpcRepair();
    f.Claim(broken, candidates, vocabulary, true, true, true);
    t.EqString("repair/the correction replaces only the command",
        f.Merge("[ACTION:MEET:Kabuki:2200]"),
        "Meet me at eleven. [ACTION:MEET:Kabuki:2200]");

    // An empty correction is NONE, spelled one way or another. The bracket goes either way,
    // because an unreadable command in the bubble is the whole defect this path removes.
    let g = new AiNpcRepair();
    g.Claim(broken, candidates, vocabulary, true, true, true);
    t.EqString("repair/an empty correction still strips the bracket",
        g.Merge(""), "Meet me at eleven.");
}

/// The turn: a generation is addressed once ///

/// The request record ///

func AiNpcTestRequestLogUsage(prompt: Int32, completion: Int32) -> ref<AiNpcUsage> {
    let usage = new AiNpcUsage();
    usage.known = true;
    usage.promptTokens = prompt;
    usage.completionTokens = completion;
    usage.totalTokens = prompt + completion;
    usage.cachedTokens = AiNpcTokensUnknown();
    usage.reasoningTokens = AiNpcTokensUnknown();
    return usage;
}

func AiNpcTestRequestLog(t: ref<AiNpcTestRunner>) -> Void {
    // 17174 characters for 4504 prompt tokens: the single measurement docs\PROMPT_BUDGET.md
    // derives its whole section table from. The line has to re-produce it, because that is
    // the point of writing it -- the ratio stops being a constant taken once by hand.
    let record = AiNpcRequestRecord.Sent(AiNpcLaneSpeaking(), "panam", AiNpcProvider.OpenRouter,
        null, "default", AiNpcTestFiller(16321), AiNpcTestFiller(853));
    let line = record.Line(200, AiNpcTestRequestLogUsage(4504, 312), "stop");

    t.Check("record/names the lane", StrContains(line, "lane=speaking"));
    // A mistyped parameter is not refused by the mod: it goes out and comes back a 400, which
    // is only payable if the line says which slot produced it.
    t.Check("record/names the slot", StrContains(line, "slot=dialogue"));
    // The other half of the same question: the slot says what the request was sent with, the
    // recipe says what was in it.
    t.Check("record/names the recipe", StrContains(line, "recipe=default"));
    t.Check("record/names the contact", StrContains(line, "contact=panam"));
    t.Check("record/counts both halves separately",
        StrContains(line, "chars_system=16321") && StrContains(line, "chars_user=853"));
    t.Check("record/carries the usage", StrContains(line, "prompt_tokens=4504")
        && StrContains(line, "completion_tokens=312") && StrContains(line, "total_tokens=4816"));
    t.Check("record/re-measures the budget ratio", StrContains(line, "chars_per_token=3.81"));

    // The reason finish_reason is read at all: a reply cut short by a token limit looks
    // exactly like a model that ignored its instructions, because the command it was asked
    // to emit is the last thing in the text.
    t.Check("record/states why the model stopped", StrContains(line, "finish=stop"));

    // Metadata only. Nothing the player wrote and nothing the character said may reach a
    // line that exists to be pasted into a bug report.
    t.Check("record/carries no text", !StrContains(line, ".."));

    // Absence is not zero. A provider that reports nothing measured nothing, and a record
    // full of zeroes would make an unmeasured day read as a free one.
    let silent = new AiNpcUsage();
    let absent = record.Line(200, silent, "");
    t.Check("record/says so when the provider reported nothing", StrContains(absent, "usage=absent"));
    t.Check("record/invents no token count", !StrContains(absent, "prompt_tokens="));
    t.Check("record/and invents no ratio either", !StrContains(absent, "chars_per_token="));
    t.Check("record/null usage reads the same way",
        StrContains(record.Line(200, null, ""), "usage=absent"));

    // The most informative line the log can carry: a 429 costs no tokens and is the moment
    // the daily cap was reached, so it is recorded like any other answer.
    t.Check("record/a refusal is recorded too", StrContains(record.Line(429, silent, ""), "status=429"));

    // An optional field inside an optional block leaves no key rather than a sentinel: a
    // reader must never have to know what -1 means.
    t.EqString("record/an unreported field leaves no key",
        AiNpcTokenField("cached_tokens", AiNpcTokensUnknown()), "");
    t.EqString("record/a reported zero is a measurement",
        AiNpcTokenField("cached_tokens", 0), " cached_tokens=0");

    // Two decimals, always, and rounded rather than truncated -- so two lines can be
    // compared at a glance and a ratio of 3.8 does not print as "3.8".
    t.EqString("ratio/two decimals", AiNpcRatioLabel(17174, 4504), "3.81");
    t.EqString("ratio/pads the hundredths", AiNpcRatioLabel(402, 100), "4.02");
    t.EqString("ratio/rounds up", AiNpcRatioLabel(3999, 1000), "4.00");
    t.EqString("ratio/no tokens, no ratio", AiNpcRatioLabel(1000, 0), "");

    let full = AiNpcTestJson("{\"usage\":{\"prompt_tokens\":4504,\"completion_tokens\":312,\"total_tokens\":4816,\"prompt_tokens_details\":{\"cached_tokens\":128},\"completion_tokens_details\":{\"reasoning_tokens\":64}}}");
    let parsed = AiNpcExtractUsage(full);
    t.EqBool("usage/a full block is known", parsed.known, true);
    t.EqInt("usage/prompt tokens", parsed.promptTokens, 4504);
    t.EqInt("usage/completion tokens", parsed.completionTokens, 312);
    t.EqInt("usage/cached tokens", parsed.cachedTokens, 128);
    t.EqInt("usage/reasoning tokens", parsed.reasoningTokens, 64);

    // A proxy that round-tripped the body through a JSON library with no integer type.
    t.EqInt("usage/a double still reads as a count",
        AiNpcExtractUsage(AiNpcTestJson("{\"usage\":{\"prompt_tokens\":4504.0}}")).promptTokens, 4504);

    // No block at all, and a block that says nothing: neither is a measurement.
    t.EqBool("usage/no block is not a measurement",
        AiNpcExtractUsage(AiNpcTestJson("{\"choices\":[]}")).known, false);
    t.EqBool("usage/an empty block is not one either",
        AiNpcExtractUsage(AiNpcTestJson("{\"usage\":{}}")).known, false);
    t.EqBool("usage/null root", AiNpcExtractUsage(null).known, false);
    t.EqInt("usage/an unreported field keeps the sentinel",
        AiNpcExtractUsage(AiNpcTestJson("{\"usage\":{\"prompt_tokens\":10}}")).cachedTokens,
        AiNpcTokensUnknown());

    t.EqString("finish/read from the first choice",
        AiNpcExtractFinishReason(AiNpcTestJson("{\"choices\":[{\"finish_reason\":\"length\"}]}")), "length");
    t.EqString("finish/absent reads as nothing",
        AiNpcExtractFinishReason(AiNpcTestJson("{\"choices\":[{}]}")), "");
    t.EqString("finish/null root", AiNpcExtractFinishReason(null), "");
}

// A string of a given length, to stand in for a prompt without carrying one.
//
// Doubled rather than appended character by character: these run at session start, and
// building seventeen thousand characters one at a time is seventeen thousand string
// allocations on the critical path of every load.

// A string of a given length, to stand in for a prompt without carrying one.
//
// Doubled rather than appended character by character: these run at session start, and
// building seventeen thousand characters one at a time is seventeen thousand string
// allocations on the critical path of every load.
func AiNpcTestFiller(length: Int32) -> String {
    let text = ".";
    while StrLen(text) < length {
        text += text;
    }
    return StrLeft(text, length);
}

func AiNpcTestGeneration(t: ref<AiNpcTestRunner>) -> Void {
    let gen = AiNpcGeneration.ForPlayer("panam", "t'es ou ?", AiNpcChannelId.Text);
    t.EqString("gen/a generation knows who it is for", gen.Contact(), "panam");
    t.EqString("gen/and what it was asked", gen.Ask(), "t'es ou ?");
    t.EqString("gen/and nothing was sent yet", gen.Url(), "");

    gen.SendingTo("https://openrouter.ai/api/v1/chat/completions");
    t.EqString("gen/the url is the one captured at send time",
        gen.Url(), "https://openrouter.ai/api/v1/chat/completions");

    // The invariant: opening a second generation cannot re-address the first. This is what
    // stops a reply arriving nine seconds later from being filed under whoever is on screen.
    let second = AiNpcGeneration.ForPlayer("judy", "salut", AiNpcChannelId.Text);
    t.EqString("gen/a new one does not re-address the old", gen.Contact(), "panam");
    t.EqString("gen/and the new one is addressed to its own", second.Contact(), "judy");

    // The repair budget is generation-scoped, which is why there is no Refill to forget:
    // beginning one IS refilling it.
    let broken = "Deal. [ACTION:BROKEN:1]";
    let candidates = ["[ACTION:BROKEN:1]"];
    let vocabulary = "<actions>[ACTION:TRICK:{place}:{hour}]: when you agree a meeting.</actions>";
    t.EqString("gen/a fresh generation brings a fresh repair budget",
        gen.Repair().Claim(broken, candidates, vocabulary, true, true, true), "[ACTION:BROKEN:1]");
    t.EqString("gen/spent within it", gen.Repair().Claim(broken, candidates, vocabulary, true, true, true), "");
    t.EqString("gen/the next one starts with its own budget",
        AiNpcGeneration.ForPlayer("panam", "?", AiNpcChannelId.Text).Repair().Claim(broken, candidates, vocabulary, true, true, true),
        "[ACTION:BROKEN:1]");

    // An idle generation names nobody rather than being null, so the typing indicator and the
    // failure log have something to address before the first send of a session.
    t.EqString("gen/idle names nobody", AiNpcGeneration.Idle().Contact(), "");

    /// Who asked ///

    // The distinction three things downstream depend on: which ending the transcript gets,
    // whether the scripted path is consulted, and -- the one that matters -- whether a failure
    // is allowed to write an operator line into a thread nobody is waiting on.
    t.EqBool("gen/the player's generation does not speak first", gen.SpeaksFirst(), false);
    t.EqString("gen/and carries no author", gen.AskedBy(), "");
    t.EqInt("gen/and no ticket", gen.Ticket(), 0);

    let mine = AiNpcGeneration.ForMod("river_ward", "rogue_gigs", "C'est son anniversaire.", 7, "", AiNpcChannelId.Text);
    t.EqBool("gen/a mod's generation speaks first", mine.SpeaksFirst(), true);
    t.EqString("gen/and names its author", mine.AskedBy(), "rogue_gigs");
    t.EqString("gen/and carries the reason as its ask", mine.Ask(), "C'est son anniversaire.");
    t.EqInt("gen/and the ticket it must answer on", mine.Ticket(), 7);
    t.EqString("gen/addressed like any other", mine.Contact(), "river_ward");
    t.EqBool("gen/an idle generation is not speaking first",
        AiNpcGeneration.Idle().SpeaksFirst(), false);

    /// The intent of one occasion ///

    // Empty is the ordinary answer and has to stay one: a mod that states nothing must leave
    // the character exactly as she was, because the alternative is a blank <intent> section on
    // every unprompted message anybody ever asks for.
    t.EqString("gen/a mod that states no intent carries none", mine.Intent(), "");

    let purposeful = AiNpcGeneration.ForMod("river_ward", "rogue_gigs", "C'est son anniversaire.",
        7, "You want to know whether {they} is still in the city.", AiNpcChannelId.Text);
    t.EqString("gen/an intent given is an intent carried", purposeful.Intent(),
        "You want to know whether {they} is still in the city.");
    t.EqString("gen/and it does not disturb the reason", purposeful.Ask(),
        "C'est son anniversaire.");

    // The resolver itself, and both directions. The override outranks the standing want AND
    // the mission -- the mission is the case it exists for.
    t.EqString("intent/a stated one wins over the character's own",
        AiNpcIntentOf("panam", "", "You want to hear how the shoot went."),
        "You want to hear how the shoot went.");
    t.EqString("intent/it wins over the tracked mission too",
        AiNpcIntentOf("panam", "riders_on_the_storm", "You want to hear how the shoot went."),
        "You want to hear how the shoot went.");
    t.EqString("intent/stating none falls back to the mission",
        AiNpcIntentOf("panam", "riders_on_the_storm", ""),
        AiNpcIntentFor("panam", "riders_on_the_storm"));
    t.EqString("intent/and with no mission, to what she always wants",
        AiNpcIntentOf("panam", "", ""), AiNpcIntentFor("panam", ""));
}

// The two endings a transcript can have, and the guard on the one that is written by a mod.
//
// Asserted on the pure halves -- AiNpcTranscriptHandover and AiNpcTranscriptReasonLine -- since
// the builders around them read the store and the clock. What is pinned here is the shape the
// model is handed, which is the whole of what CharacterWantsToSay changes about the prompt.

// Everything asserted here is a RULE rather than a wire, which is why AiNpcUsageLedger.reds
// is a separate file from the service that reaches for the disk. The rules are also the part
// that can be wrong in a way nobody notices for a day: a boundary read off the wrong string
// silently purges a real total, and a charge that rounds to zero is a ceiling with a hole in
// it. None of it needs a session.
func AiNpcTestUsageLedgerCharge(tokens: Int32, estimated: Bool) -> ref<AiNpcCharge> {
    let charge = new AiNpcCharge();
    charge.tokens = tokens;
    charge.estimated = estimated;
    return charge;
}

func AiNpcTestUsageLedger(t: ref<AiNpcTestRunner>) -> Void {
    /// The day, read off the wire ///

    // The shape RFC 9110 requires a server to send, and the shape every backend measured
    // here does send.
    t.EqString("usage/reads the day off a Date header",
        AiNpcUsageDayFromHttpDate("Sat, 23 Aug 2026 15:42:58 GMT"), "2026-08-23");
    t.EqString("usage/pads the day and the month",
        AiNpcUsageDayFromHttpDate("Fri, 02 Jan 2026 00:00:01 GMT"), "2026-01-02");

    // A header the mod cannot read confirms NOTHING. That is the safe direction: the tally
    // keeps accumulating under the last day it knew and the cap keeps applying, where a
    // guessed date would silently purge a real total.
    t.EqString("usage/an unreadable header names no day",
        AiNpcUsageDayFromHttpDate("Sat Aug 23 15:42:58 2026"), "");
    t.EqString("usage/an absent header names no day", AiNpcUsageDayFromHttpDate(""), "");
    t.EqString("usage/an unknown month names no day",
        AiNpcUsageDayFromHttpDate("Sat, 23 Xxx 2026 15:42:58 GMT"), "");

    /// What a request is charged ///

    let measured = new AiNpcUsage();
    measured.known = true;
    measured.promptTokens = 4504;
    measured.completionTokens = 312;
    measured.totalTokens = 4816;
    let full = AiNpcMeasureCharge(measured, 17174);
    t.EqInt("usage/charges the provider's own total", full.tokens, 4816);
    t.EqBool("usage/a measured charge is not an estimate", full.estimated, false);

    // A provider that reports the halves but no total is still measuring.
    let halves = new AiNpcUsage();
    halves.known = true;
    halves.promptTokens = 4504;
    halves.completionTokens = 312;
    halves.totalTokens = AiNpcTokensUnknown();
    t.EqInt("usage/adds the halves when there is no total",
        AiNpcMeasureCharge(halves, 17174).tokens, 4816);

    // The departure from "absence is never zero", and the reason for it: a ceiling that
    // charges nothing when the provider says nothing is a switch anyone can turn off by
    // picking the right backend. So it charges a guess, and says that it guessed.
    let silent = new AiNpcUsage();
    let guessed = AiNpcMeasureCharge(silent, 17174);
    t.EqInt("usage/estimates what nobody measured", guessed.tokens, 4508);
    t.EqBool("usage/and marks the estimate as one", guessed.estimated, true);
    t.EqBool("usage/a null usage block is an estimate too",
        AiNpcMeasureCharge(null, 3810).estimated, true);

    // Rounded rather than truncated: nothing this mod sends may round down to free.
    t.EqInt("usage/rounds the estimate", AiNpcEstimateTokens(381), 100);
    t.EqInt("usage/the smallest send still costs", AiNpcEstimateTokens(4), 1);
    t.EqInt("usage/nothing sent costs nothing", AiNpcEstimateTokens(0), 0);

    /// The tally ///

    let ledger = new AiNpcUsageLedger();
    ledger.RollTo("2026-08-23");
    ledger.Add(AiNpcLaneSpeaking(), AiNpcTestUsageLedgerCharge(4816, false));
    ledger.Add(AiNpcLaneThinking(), AiNpcTestUsageLedgerCharge(1200, false));
    ledger.Add(AiNpcLaneSpeaking(), AiNpcTestUsageLedgerCharge(4000, true));

    t.EqInt("usage/one day accumulates across lanes", ledger.total, 10016);
    t.EqInt("usage/and can still be taken apart", ledger.LaneTotal(AiNpcLaneSpeaking()), 8816);
    t.EqInt("usage/the thinking lane is counted too", ledger.LaneTotal(AiNpcLaneThinking()), 1200);
    t.EqInt("usage/what was guessed is kept apart", ledger.estimated, 4000);

    // A charge with no lane behind it -- the Idle record's -- is filed under a name rather
    // than under a blank key nobody could read.
    ledger.Add("", AiNpcTestUsageLedgerCharge(50, false));
    t.EqInt("usage/an unattributed charge is still named", ledger.LaneTotal("unattributed"), 50);

    t.EqBool("usage/the same day purges nothing", ledger.RollTo("2026-08-23"), false);
    t.EqBool("usage/an unnamed day purges nothing", ledger.RollTo(""), false);
    t.EqInt("usage/so the total stands", ledger.total, 10066);

    // Tomorrow and three weeks later are the same event, and there is no third case.
    t.EqBool("usage/a new day purges", ledger.RollTo("2026-08-24"), true);
    t.EqInt("usage/and starts from zero", ledger.total, 0);
    t.EqInt("usage/lanes go with it", ledger.LaneTotal(AiNpcLaneSpeaking()), 0);
    t.EqBool("usage/and so does the warning latch", ledger.warned, false);

    /// The rule ///

    let spent = new AiNpcUsageLedger();
    spent.RollTo("2026-08-23");
    spent.Add(AiNpcLaneSpeaking(), AiNpcTestUsageLedgerCharge(200000, false));

    // The sentence the whole design is: refused when the day recorded is the day the provider
    // last said it was, and its total has reached the budget.
    t.EqBool("budget/refuses a spent day",
        AiNpcUsageAllows(spent, "2026-08-23", true, 200000), false);

    // THE FIRST REQUEST OF A SESSION ALWAYS GOES THROUGH. Nothing has come back yet, so no
    // day has been confirmed, so there is nothing to check the tally against -- and refusing
    // on a date the mod cannot verify would lock out a player who came back the next day.
    t.EqBool("budget/no day confirmed, no refusal",
        AiNpcUsageAllows(spent, "", true, 200000), true);

    // A tally that belongs to a day that is over refuses nothing; the charge that follows
    // purges it.
    t.EqBool("budget/yesterday's total refuses nothing",
        AiNpcUsageAllows(spent, "2026-08-24", true, 200000), true);

    // Off is off: the tally still counts, and never refuses. That is the default.
    t.EqBool("budget/the cap disabled never refuses",
        AiNpcUsageAllows(spent, "2026-08-23", false, 200000), true);

    let partial = new AiNpcUsageLedger();
    partial.RollTo("2026-08-23");
    partial.Add(AiNpcLaneSpeaking(), AiNpcTestUsageLedgerCharge(199999, false));
    t.EqBool("budget/one token short is still a yes",
        AiNpcUsageAllows(partial, "2026-08-23", true, 200000), true);

    /// The warning ///

    t.EqInt("budget/warns at four fifths", AiNpcUsageWarnAt(200000), 160000);
    t.EqBool("budget/the crossing is what is announced",
        AiNpcUsageWarningDue(159000, 161000, 200000, false), true);
    t.EqBool("budget/not before it", AiNpcUsageWarningDue(100000, 120000, 200000, false), false);
    t.EqBool("budget/and not twice", AiNpcUsageWarningDue(159000, 161000, 200000, true), false);
    t.EqBool("budget/nor once past it",
        AiNpcUsageWarningDue(170000, 180000, 200000, false), false);

    /// The slider ///

    // The clamp and the min/max the menu advertises are the same two numbers; if they drift,
    // the menu is lying.
    t.EqInt("budget/the slider is in thousands", AiNpcClampDailyBudget(200), 200000);
    t.EqInt("budget/clamped to the floor", AiNpcClampDailyBudget(1), 10000);
    t.EqInt("budget/clamped to the ceiling", AiNpcClampDailyBudget(5000), 1000000);

    /// The file ///

    let written = new AiNpcUsageLedger();
    written.RollTo("2026-08-23");
    written.Add(AiNpcLaneSpeaking(), AiNpcTestUsageLedgerCharge(4816, false));
    written.Add(AiNpcLaneThinking(), AiNpcTestUsageLedgerCharge(1200, true));
    written.warned = true;

    let readBack = AiNpcUsageFromJson(AiNpcUsageToJson(written));
    t.EqString("usage/the file keeps the day", readBack.day, "2026-08-23");
    t.EqInt("usage/the file keeps the total", readBack.total, 6016);
    t.EqInt("usage/the file keeps what was guessed", readBack.estimated, 1200);
    t.EqBool("usage/the file keeps the warning latch", readBack.warned, true);
    t.EqInt("usage/the file keeps the lanes", readBack.LaneTotal(AiNpcLaneThinking()), 1200);

    // A missing or unreadable file is one day counted from zero, never a lane that refuses to
    // send because its own bookkeeping would not parse.
    t.EqInt("usage/an unreadable file reads as an empty day", AiNpcUsageFromJson(null).total, 0);
}

/// What the player is told about the budget ///

// Structural, like AiNpcTestCarrierMessage: what is asserted is that every language answers
// with something, and that the answer is NOT the carrier line -- that one means the network
// is down, and it would send a player hunting a problem they do not have.

// Structural, like AiNpcTestCarrierMessage: what is asserted is that every language answers
// with something, and that the answer is NOT the carrier line -- that one means the network
// is down, and it would send a player hunting a problem they do not have.
func AiNpcTestBudgetMessages(t: ref<AiNpcTestRunner>) -> Void {
    let languages = [AiNpcLanguage.English, AiNpcLanguage.Spanish, AiNpcLanguage.French,
        AiNpcLanguage.German, AiNpcLanguage.Italian, AiNpcLanguage.Portuguese,
        AiNpcLanguage.Russian, AiNpcLanguage.Ukraine];

    let i = 0;
    let count = ArraySize(languages);
    let spentOk = true;
    let warnOk = true;
    let distinct = true;

    while i < count {
        let language = languages[i];
        let spent = AiNpcBudgetSpentMessageFor(language);
        let warning = AiNpcBudgetWarningMessageFor(language);

        if Equals(StrLen(spent), 0) {
            spentOk = false;
        }
        if Equals(StrLen(warning), 0) {
            warnOk = false;
        }
        if Equals(spent, AiNpcCarrierMessageFor(language)) || Equals(spent, warning) {
            distinct = false;
        }
        i += 1;
    }

    t.EqBool("budget/every language says the day is spent", spentOk, true);
    t.EqBool("budget/every language warns", warnOk, true);
    t.EqBool("budget/and neither is the carrier line", distinct, true);
}
