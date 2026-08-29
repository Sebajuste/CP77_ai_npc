// The identity: what makes this mod recognisable on any surface it draws on.
//
// Colour roles, typography, and the HUD style resources a role is expressed through.
// **No lengths.** Not one margin, size, anchor or coordinate.
//
// That is forced by the game: the terminal draws into a browser page whose frame is about
// 3140 x 1200 units scaled onto a screen mesh, the phone draws into the HUD's own units, and
// a length crossing between them would be wrong on one of them by construction. Sizes live in
// AiNpcTerminalStyle and AiNpcPhoneStyle, one per surface. What DOES cross is the palette.
//
// A role is named for its meaning, not its hue -- Character(), not Cyan() -- so that changing
// what the mod looks like is one edit here rather than a sweep through two files.
//
// A role carries BOTH a plain Color and the style path plus property name that expresses it,
// because the two surfaces disagree: the phone binds tints and font sizes to the HUD's own
// style resources (MainColors.Blue, Message.TextColor...), which are the game's readability
// settings and would make a phone that ignored them the one unreadable panel on the HUD; the
// terminal refuses to bind, because on a page rendered into a screen mesh those constants are
// the wrong authority and a bound value cannot be corrected from script.
//
// Everything is exposed through functions, never as constants another file copies, so a
// palette option in Mod Settings would be a change in this file alone.

module AiNpc

public abstract class AiNpcStyle {

    // V. Mint, and the one colour that means "you" on every surface.
    public static func Player() -> Color {
        return new Color(Cast(0u), Cast(255u), Cast(188u), Cast(255u));
    }

    // The plate and border behind V's own words on the phone. A shade off Player() rather
    // than the same value: a bubble whose fill matches its text is unreadable.
    public static func PlayerEdge() -> Color {
        return new Color(Cast(0u), Cast(255u), Cast(198u), Cast(255u));
    }

    // Whoever is being spoken to. The most-used colour in the mod, and the one that must never
    // be written out as a literal at a call site.
    public static func Character() -> Color {
        return new Color(Cast(94u), Cast(246u), Cast(255u), Cast(255u));
    }

    public static func CharacterPlate() -> Color {
        return new Color(Cast(23u), Cast(44u), Cast(46u), Cast(255u));
    }

    public static func CharacterEdge() -> Color {
        return new Color(Cast(52u), Cast(145u), Cast(151u), Cast(255u));
    }

    // Ordinary text with no speaker.
    public static func Body() -> Color {
        return new Color(Cast(225u), Cast(225u), Cast(215u), Cast(255u));
    }

    // Present but not the point: timestamps, hints, a row that is not selected.
    public static func Dim() -> Color {
        return new Color(Cast(130u), Cast(130u), Cast(145u), Cast(255u));
    }

    // Coral. Attention, never decoration -- if it is on screen, something wants reading.
    public static func Accent() -> Color {
        return new Color(Cast(255u), Cast(97u), Cast(89u), Cast(255u));
    }

    // The text caret, which has to be visible against both plates and belongs to neither
    // voice.
    public static func Caret() -> Color {
        return new Color(Cast(255u), Cast(255u), Cast(78u), Cast(255u));
    }

    // The phone's chrome: a gold rule and two near-blacks behind the message list.
    public static func Trim() -> Color {
        return new Color(Cast(161u), Cast(126u), Cast(51u), Cast(255u));
    }

    public static func Backdrop() -> Color {
        return new Color(Cast(20u), Cast(20u), Cast(20u), Cast(255u));
    }

    public static func BackdropDeep() -> Color {
        return new Color(Cast(14u), Cast(14u), Cast(23u), Cast(255u));
    }

    //
    // The family is shared; the SIZES are not, and live in each surface's own style module.

    public static func FontFamily() -> String {
        return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily";
    }

    public static func FontStyleBody() -> CName {
        return n"Medium";
    }

    public static func FontStyleBold() -> CName {
        return n"Bold";
    }

    // Headings are upper-cased by the widget rather than by the string, so a translation
    // never has to carry the casing and no language is shouted at by accident.
    public static func HeadingCase() -> textLetterCase {
        return textLetterCase.UpperCase;
    }

    public static func BodyCase() -> textLetterCase {
        return textLetterCase.OriginalCase;
    }

    //
    // Used by the phone, ignored by the terminal. Here rather than in AiNpcPhoneStyle because
    // MainColorsTint() and Character() are the same decision written for two different
    // authorities, and must be changed together or not at all.

    public static func MainColorsStyle() -> ResRef {
        return r"base\\gameplay\\gui\\common\\main_colors.inkstyle";
    }

    public static func PanelStyle() -> ResRef {
        return r"base\\gameplay\\gui\\common\\styles\\panel.inkstyle";
    }

    public static func MessengerStyle() -> ResRef {
        return r"base\\gameplay\\gui\\fullscreen\\phone_quest_menu\\messenger.inkstyle";
    }

    // The property name that carries Character() through the HUD's own readability style.
    public static func PropCharacterTint() -> CName {
        return n"MainColors.Blue";
    }

    public static func PropAccentTint() -> CName {
        return n"MainColors.Red";
    }

    public static func PropLabelOpacity() -> CName {
        return n"MenuLabel.MainOpacity";
    }
}
