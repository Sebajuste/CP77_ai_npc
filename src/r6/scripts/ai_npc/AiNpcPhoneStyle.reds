// Every number and every asset the phone chat draws with.
//
// HUD units, not the terminal's frame units, which is why this file is separate from
// AiNpcTerminalStyle: the identity crosses (see AiNpcStyle), the lengths cannot.
//
// Almost every widget below sets a plain colour AND binds the property to one of the HUD's
// own style resources. The plain value is what shows if the style resource fails to resolve;
// the binding keeps the chat legible for a player who has changed the HUD's readability
// settings. The phone lives inside that HUD, so those constants are the right authority --
// the terminal does not, and refuses them.
//
// One-off layout coordinates are NOT here: a margin used once, by one widget, in one builder,
// is part of that builder's description of its own shape. What is here is what REPEATS.

module AiNpc

public abstract class AiNpcPhoneStyle {

    //
    // Plain values; each call site also binds the widget's fontSize to the HUD's readability
    // constant, so these are the fallback and the proportion rather than the last word.

    // The messages header and the contact's name.
    public static func FsHeading() -> Int32 {
        return 50;
    }

    // The typed line.
    public static func FsInput() -> Int32 {
        return 42;
    }

    // Key hints, and the "is typing" line.
    public static func FsHint() -> Int32 {
        return 38;
    }

    // The two serial numbers in the header corners. Decoration, deliberately tiny.
    public static func FsFluff() -> Int32 {
        return 20;
    }

    // Every key-hint glyph, and the click hint on the input line.
    public static func IconSize() -> Vector2 {
        return new Vector2(64.0, 64.0);
    }

    // The thick cyan rules in the header.
    public static func RuleHeight() -> Float {
        return 7.0;
    }

    // The thin coral rules that separate the bands.
    public static func HairlineHeight() -> Float {
        return 2.0;
    }

    // The input line and its hint, greyed while the lane will refuse anyway.
    public static func DisabledOpacity() -> Float {
        return 0.2;
    }

    public static func RuleOpacity() -> Float {
        return 0.2;
    }

    //
    // Game assets, each spelled out exactly once. A mistyped resource path does not fail --
    // the widget simply draws nothing -- so a second copy of one of these is a typo waiting
    // to happen somewhere no error will ever be raised.

    public static func AtlasKeyboard() -> ResRef {
        return r"base\\gameplay\\gui\\common\\input\\icons_keyboard.inkatlas";
    }

    public static func AtlasCommonIcons() -> ResRef {
        return r"base\\gameplay\\gui\\common\\icons\\atlas_common.inkatlas";
    }

    public static func AtlasShapes() -> ResRef {
        return r"base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas";
    }

    public static func AtlasPhone() -> ResRef {
        return r"base\\gameplay\\gui\\widgets\\phone\\new_phone_assets.inkatlas";
    }

    public static func AtlasNotification() -> ResRef {
        return r"base\\gameplay\\gui\\widgets\\hud_johnny\\notification_assets.inkatlas";
    }

    public static func AtlasMasks() -> ResRef {
        return r"base\\gameplay\\gui\\common\\masks.inkatlas";
    }
}
