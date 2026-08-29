// The two animations the phone chat plays, and nothing else.
//
// They look alike at a glance -- translate plus fade, linear, easy out -- and they are not:
//
//     the panel     slides in from the RIGHT, 250 units, over 0.10s
//     one message   rises from BELOW,          50 units, over 0.15s
//
// Written down because folding them into one parameterised helper is the obvious tidy-up and
// it is wrong: the axis, the distance and the duration all differ, and a chat where messages
// arrive from the wrong direction is a visual regression no assertion here can catch.
//
// An inkAnimDef is cheap. A definition held in a field across a HUD rebuild is one more
// handle that can outlive the tree it was made for.

module AiNpc

// The chat panel arriving. Played once, on the root, at the end of the build.
func AiNpcPhoneEntranceAnim() -> ref<inkAnimDef> {
    let translation = new inkAnimTranslation();
    translation.SetStartTranslation(new Vector2(250.0, 0.0));
    translation.SetEndTranslation(new Vector2(0, 0));
    translation.SetType(inkanimInterpolationType.Linear);
    translation.SetMode(inkanimInterpolationMode.EasyOut);
    translation.SetDuration(0.1);

    let alpha = new inkAnimTransparency();
    alpha.SetStartTransparency(0.0);
    alpha.SetEndTransparency(1.0);
    alpha.SetType(inkanimInterpolationType.Linear);
    alpha.SetMode(inkanimInterpolationMode.EasyOut);
    alpha.SetDuration(0.1);

    let definition = new inkAnimDef();
    definition.AddInterpolator(translation);
    definition.AddInterpolator(alpha);
    return definition;
}

// One message arriving. Played only for a message that is happening now -- a replayed
// history animates nothing, or twenty replies land at once.
func AiNpcPhoneMessageAnim() -> ref<inkAnimDef> {
    let translation = new inkAnimTranslation();
    translation.SetStartTranslation(new Vector2(0.0, 50.0));
    translation.SetEndTranslation(new Vector2(0, 0));
    translation.SetType(inkanimInterpolationType.Linear);
    translation.SetMode(inkanimInterpolationMode.EasyOut);
    translation.SetDuration(0.15);

    let alpha = new inkAnimTransparency();
    alpha.SetStartTransparency(0.0);
    alpha.SetEndTransparency(1.0);
    alpha.SetType(inkanimInterpolationType.Linear);
    alpha.SetMode(inkanimInterpolationMode.EasyOut);
    alpha.SetDuration(0.15);

    let definition = new inkAnimDef();
    definition.AddInterpolator(translation);
    definition.AddInterpolator(alpha);
    return definition;
}
