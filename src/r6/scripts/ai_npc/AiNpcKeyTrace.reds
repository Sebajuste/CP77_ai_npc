// A trace for ONE question: what does the engine deliver for a key that does not type?
//
// Measured symptom on an AZERTY keyboard: `!` produces nothing, and the dead key `^` followed
// by `e` produces no `ê`. Three causes would explain either one, and they need three different
// fixes -- no event is emitted at all, an event arrives but IsCharacter() is false, or a
// character arrives and a modifier guard discards it. Guessing picks the wrong one.
//
// Two lanes, because no single event carries both halves of the answer:
//
//   Codeware's KeyInputEvent (Input/Key) -> key code and modifiers, no character.
//     Bound for every key while the phone chat is in its typing state, so it sees what the
//     player types into the phone -- where the text field belongs to Codeware and cannot be
//     instrumented from here.
//
//   inkKeyInputEvent (a widget's OnInputKey) -> IsCharacter and GetCharacter.
//     Only the terminal field, which is ours.
//
// So the phone answers "was an event emitted, under which EInputKey, with which modifiers",
// and the terminal answers "did it carry a character". Together they name the cause.
//
// FTLog rather than AiNpcLog: the trace must not depend on Debug Mode being on, because a
// player asked to reproduce a keyboard bug should not first have to find a setting.
//
// AltGr is why the modifiers are printed. Windows delivers it as Ctrl+Alt, and both text
// fields discard a character when either is down -- so on AZERTY the guard would reject
// @ # { } [ ] | \ ~ ` and the euro sign. The trace says whether that is what is happening
// rather than leaving it a plausible story.

module AiNpc

import Codeware.*

// The off switch. False costs one comparison per keystroke and writes nothing; deleting the
// file plus its two call sites is the full revert.
func AiNpcKeyTraceEnabled() -> Bool {
    return true;
}

// Shared tail, so the two lanes cannot drift into two formats a reader has to reconcile.
func AiNpcKeyTraceModifiers(shift: Bool, ctrl: Bool, alt: Bool) -> String {
    return s"shift=\(shift) ctrl=\(ctrl) alt=\(alt)";
}

// The phone lane. Every action, not only IACT_Press: "the key emitted a release and no press"
// and "the key emitted nothing" are different answers, and only one of them is our problem.
func AiNpcKeyTraceEngine(event: ref<KeyInputEvent>) -> Void {
    if !AiNpcKeyTraceEnabled() {
        return;
    }
    FTLog(s"[ai_npc keytrace] engine action=\(event.GetAction()) key=\(event.GetKey()) "
        + AiNpcKeyTraceModifiers(event.IsShiftDown(), event.IsControlDown(), event.IsAltDown()));
}

// The terminal lane. The character is printed twice -- as itself and counted -- because a log
// that renders a glyph as nothing does not say whether the string was empty. The count settles
// it, and it is a count of characters: an accent is one, whatever it weighs in bytes.
func AiNpcKeyTraceWidget(evt: ref<inkKeyInputEvent>) -> Void {
    if !AiNpcKeyTraceEnabled() {
        return;
    }
    let char = evt.GetCharacter();
    FTLog(s"[ai_npc keytrace] widget action=\(evt.GetAction()) key=\(evt.GetKey()) "
        + AiNpcKeyTraceModifiers(evt.IsShiftDown(), evt.IsControlDown(), evt.IsAltDown())
        + s" isCharacter=\(evt.IsCharacter()) char='\(char)' chars=\(AiNpcUtf8Len(char))");
}
