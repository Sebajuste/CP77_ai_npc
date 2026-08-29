// A held key, repeated -- the half of a keyboard the engine does not provide.
//
// EInputAction is Press, Release, Axis, and nothing else. There is no repeat action: a key
// held down delivers ONE event and then silence, so a field that only reacts to a press
// deletes one character and stops. Codeware's own TextInput generates the repeat in script
// exactly like this.
//
// Nothing here is about a text field, a terminal or a page: it is a key, a clock and two
// thresholds, so a second surface that needs a held key does not have to copy a tick loop.
//
// The clock is an animation that does nothing -- a progress interpolated from 0 to 0, one
// frame long, looping for ever -- played on the owner's widget, whose OnStartLoop ticks 60
// times a second. ink gives a widget no other clock, and a DelayCallback would not do: it
// does not survive a save/load, and this has to live exactly as long as the widget.

module AiNpc

//
// The two decisions that can be wrong, as pure functions taking their thresholds rather than
// reading them, so an assertion can state a case in numbers instead of in constants.

// Long before the first repeat, short between the following. The delay is what stops a tap
// from ever repeating; the interval is what makes holding backspace useful.
//
// `>=` and not `==`: a tick lost to a frame the game spent elsewhere would, with `==`, leave
// the counter past the mark and the key held down for ever without repeating again.
func AiNpcRepeatFires(ticks: Int32, repeating: Bool, delay: Int32, every: Int32)
                             -> Bool {
    if repeating {
        return ticks >= every;
    }
    return ticks >= delay;
}

// Which keys repeat. Backspace is the one this exists for; characters repeat because a
// keyboard repeats them and a player holding one expects a line of them.
//
// Enter does NOT. On a keyboard it repeats like anything else, but a field turns it into a
// send: held half a second it would fire a message, then thirty a second at an LLM. Escape
// does not either -- it has already given the keyboard back, and there is nothing to say
// twice.
func AiNpcKeyRepeats(evt: ref<inkKeyInputEvent>) -> Bool {
    if Equals(evt.GetKey(), EInputKey.IK_Enter) {
        return false;
    }
    if Equals(evt.GetKey(), EInputKey.IK_Escape) {
        return false;
    }
    if Equals(evt.GetKey(), EInputKey.IK_Backspace) {
        return true;
    }
    return evt.IsCharacter() && !evt.IsControlDown() && !evt.IsAltDown();
}

// Counted in ticks of the 60 Hz loop above: about half a second before a held key starts
// repeating, about thirty characters a second after that. Both are Codeware's numbers, from
// the text input the phone chat is built on -- matching them is what stops the two fields
// from feeling like two different keyboards.
func AiNpcKeyRepeatDelayTicks() -> Int32 {
    return 30;
}

func AiNpcKeyRepeatEveryTicks() -> Int32 {
    return 2;
}

public class AiNpcKeyRepeat extends IScriptable {

    // Weak: the owner holds this object, and an owner held back would be an owner that never
    // dies. The tick checks it every frame, so a cleared wref simply stops the repeat.
    private let m_owner: wref<AiNpcKeyboardClaimant>;

    // The last press, kept until its own release. Not a key code: what is replayed is the
    // EVENT, so a repeated keystroke and a pressed one cannot drift apart.
    private let m_held: ref<inkKeyInputEvent>;
    private let m_repeating: Bool;
    private let m_ticks: Int32;
    private let m_proxy: ref<inkAnimProxy>;

    public final func Bind(owner: ref<AiNpcKeyboardClaimant>) -> Void {
        this.m_owner = owner;
    }

    // Started on the widget the keys arrive at, once per build of it. Stopping first is not
    // hygiene: a page visited twice would otherwise leave a loop beating on the widget of
    // the page before, and one more of them after every visit.
    public final func Start(widget: ref<inkWidget>) -> Void {
        this.Stop();
        if !IsDefined(widget) {
            return;
        }

        let step = new inkAnimTextValueProgress();
        step.SetStartProgress(0.0);
        step.SetEndProgress(0.0);
        step.SetDuration(1.0 / 60.0);

        let def = new inkAnimDef();
        def.AddInterpolator(step);

        let options: inkAnimOptions;
        options.loopInfinite = true;
        options.loopType = inkanimLoopType.Cycle;

        this.m_proxy = widget.PlayAnimationWithOptions(def, options);
        if IsDefined(this.m_proxy) {
            this.m_proxy.RegisterToCallback(inkanimEventType.OnStartLoop, this,
                                            n"OnAiNpcRepeatTick");
        }
    }

    public final func Stop() -> Void {
        this.Forget();
        if IsDefined(this.m_proxy) {
            this.m_proxy.Stop();
            this.m_proxy = null;
        }
    }

    // A press replaces whatever was held and starts its delay again from zero, which is what
    // a keyboard does when a second key goes down while the first is still held.
    public final func Press(evt: ref<inkKeyInputEvent>) -> Void {
        this.Forget();
        if AiNpcKeyRepeats(evt) {
            this.m_held = evt;
        }
    }

    // Only the release of the key that started the repeat ends it: with two keys down, the
    // first one lifted must not silence the one still held.
    public final func Release(evt: ref<inkKeyInputEvent>) -> Void {
        if IsDefined(this.m_held) && Equals(evt.GetKey(), this.m_held.GetKey()) {
            this.Forget();
        }
    }

    // Nothing is held any more. Called by every release, and by every way of losing the
    // keyboard -- a player who clicked away mid-backspace must not watch the line keep
    // emptying itself.
    public final func Forget() -> Void {
        this.m_held = null;
        this.m_repeating = false;
        this.m_ticks = 0;
    }

    // Sixty times a second, and almost always nothing: between keystrokes there is no held
    // key, and the whole tick is one IsDefined.
    protected cb func OnAiNpcRepeatTick(anim: ref<inkAnimProxy>) -> Void {
        if !IsDefined(this.m_held) || !IsDefined(this.m_owner) {
            return;
        }
        this.m_ticks += 1;
        if !AiNpcRepeatFires(this.m_ticks, this.m_repeating,
                             AiNpcKeyRepeatDelayTicks(), AiNpcKeyRepeatEveryTicks()) {
            return;
        }
        // The first repeat is what turns the long wait into the short one: from here the key
        // fires every couple of ticks until it is released.
        this.m_ticks = 0;
        this.m_repeating = true;
        this.m_owner.ApplyKey(this.m_held);
    }
}
