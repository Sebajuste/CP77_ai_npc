// Who holds the keyboard, and how it is given back.
//
// Clicking the chat's text field takes the keyboard (AiNpcTerminalField.Focus), and a capture
// that outlives its page is not a UI glitch: the player walks back into the world and cannot
// move, because WASD is still eaten by a text field nobody can see.
//
// The capture BELONGS to the page that drew the field. It is claimed when the field is
// clicked and released on every route out, without any of those routes needing to know what a
// text field is:
//
//     leaving our page      -> AiNpcTerminalChat.ForgetPage       (every build, and Detach)
//     leaving for a page
//       that is not ours    -> the LoadWebPage hook in AiNpcTerminalSite
//     the browser closing   -> BrowserGameController.OnUninitialize -> Detach
//     a reply in flight     -> AiNpcTerminalField.SetDisabled
//     Escape, or a click
//       anywhere else       -> the field itself, and the page's backdrop handler
//
// A registry rather than a field handle, because the route that matters most -- the player
// clicks a button of the browser shell, outside our canvas -- runs in a hook on a VANILLA
// controller that has no way to reach the page it is replacing. One holder at a time,
// released by identity, like AiNpcChatSessionRegistry: two pages overlap for an instant when
// the next is built before the previous is torn down, so a release must never cancel a claim
// a newer page has just made.

module AiNpc

// An object that owns the keyboard: give it back, and take a key.
//
// ApplyKey is here rather than on the field because a keystroke does not only come from the
// engine -- a held key is replayed by AiNpcKeyRepeat, which knows an owner and nothing else.
// Abstract, so neither the registry nor the repeat clock learns that the only claimant today
// is a text field on a computer screen.
public abstract class AiNpcKeyboardClaimant extends IScriptable {
    public func ReleaseKeyboard() -> Void {
    }

    public func ApplyKey(evt: ref<inkKeyInputEvent>) -> Void {
    }
}

//
// Pure functions over the holder, so the self-tests can assert them with no system, no
// widgets and no game.

// A claim always wins: whoever clicked last is who the player is typing into. Claiming
// nothing is not a way to release -- that is what a release is for -- so it leaves the
// current holder alone rather than silently stranding it.
func AiNpcKeyboardAfterClaim(current: ref<AiNpcKeyboardClaimant>,
                                    who: ref<AiNpcKeyboardClaimant>)
                                    -> ref<AiNpcKeyboardClaimant> {
    if !IsDefined(who) {
        return current;
    }
    return who;
}

// Released BY IDENTITY. A page being torn down releases itself, and if the player has
// already opened another one, that older teardown must not take the new page's keyboard
// away -- the field would still be drawn as focused while every key went back to the world.
func AiNpcKeyboardAfterRelease(current: ref<AiNpcKeyboardClaimant>,
                                      who: ref<AiNpcKeyboardClaimant>)
                                      -> ref<AiNpcKeyboardClaimant> {
    if IsDefined(who) && Equals(current, who) {
        return null;
    }
    return current;
}

// A ScriptableSystem for the same reason the session registry is one: it exists exactly for
// the length of a game session, which is longer than any widget and shorter than the mod.
public class AiNpcKeyboardCapture extends ScriptableSystem {

    private let m_holder: ref<AiNpcKeyboardClaimant>;

    public static func Get() -> ref<AiNpcKeyboardCapture> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcKeyboardCapture>()) as AiNpcKeyboardCapture;
    }

    // The previous holder is told to let go before the new one is recorded. Without that,
    // two fields -- two computers, or a page rebuilt around a stale one -- would both
    // believe they have the keyboard, and only one of them would be right.
    public func Claim(who: ref<AiNpcKeyboardClaimant>) -> Void {
        let previous = this.m_holder;
        let next = AiNpcKeyboardAfterClaim(previous, who);
        if Equals(next, previous) {
            return;
        }
        this.m_holder = next;
        if IsDefined(previous) {
            previous.ReleaseKeyboard();
        }
    }

    public func Release(who: ref<AiNpcKeyboardClaimant>) -> Void {
        this.m_holder = AiNpcKeyboardAfterRelease(this.m_holder, who);
    }

    // The unmount everything else calls: give the keyboard back, whoever has it. Clearing
    // the holder BEFORE telling it to let go is what stops the claimant's own release path
    // from coming back here and looping.
    public func ReleaseAll() -> Void {
        let previous = this.m_holder;
        this.m_holder = null;
        if IsDefined(previous) {
            previous.ReleaseKeyboard();
        }
    }

    public func Holder() -> ref<AiNpcKeyboardClaimant> {
        return this.m_holder;
    }
}

//
// All three no-op outside a game session -- the registry is a system, and no caller should
// have to know that.

func AiNpcClaimKeyboard(who: ref<AiNpcKeyboardClaimant>) -> Void {
    let capture = AiNpcKeyboardCapture.Get();
    if IsDefined(capture) {
        capture.Claim(who);
    }
}

func AiNpcReleaseKeyboard(who: ref<AiNpcKeyboardClaimant>) -> Void {
    let capture = AiNpcKeyboardCapture.Get();
    if IsDefined(capture) {
        capture.Release(who);
    }
}

// "Whatever is holding the keyboard, let go of it." The one line a hook on a vanilla
// controller needs, and the only one it is allowed to know.
func AiNpcReleaseKeyboardCapture() -> Void {
    let capture = AiNpcKeyboardCapture.Get();
    if IsDefined(capture) {
        capture.ReleaseAll();
    }
}

// Handing the keyboard back to the game.
//
// It was taken with inkSystem.SetFocus, so it is given back the same way. A null focus is what
// a vanilla-shaped controller asks for when it is done with a text field
// (RequestSetFocus(null)); this is that request from an object that is not a controller.
func AiNpcClearInkFocus() -> Void {
    let inkSystem = GameInstance.GetInkSystem();
    if IsDefined(inkSystem) {
        inkSystem.SetFocus(null);
    }
}
