// Making a widget, without the four lines that are the same every time.
//
// Building an ink widget by hand is a name, a font family, a weight, a size, a colour and a
// reparent before anything specific to that widget is said. Three of those carry no decision,
// and the colour is a decision that belongs in AiNpcStyle rather than at a call site where
// forty spelled-out Color literals cannot be kept in agreement.
//
// Deliberately NOT a builder with twenty optional parameters: these make a widget, name it,
// parent it, and give it the two or three properties nothing ever wants different. The caller
// configures the rest on the returned handle. Every helper reparents before returning, and
// ink applies a property whenever it is set, parented or not.
//
// The phone only. The terminal draws into a screen mesh and has its own Label / Bar / Plate /
// Button primitives with their own coordinate space.

module AiNpc

func AiNpcInkCanvas(parent: ref<inkCompoundWidget>, name: CName) -> ref<inkCanvas> {
    let widget = new inkCanvas();
    widget.SetName(name);
    widget.Reparent(parent);
    return widget;
}

func AiNpcInkFlex(parent: ref<inkCompoundWidget>, name: CName) -> ref<inkFlex> {
    let widget = new inkFlex();
    widget.SetName(name);
    widget.Reparent(parent);
    return widget;
}

func AiNpcInkVertical(parent: ref<inkCompoundWidget>, name: CName) -> ref<inkVerticalPanel> {
    let widget = new inkVerticalPanel();
    widget.SetName(name);
    widget.Reparent(parent);
    return widget;
}

func AiNpcInkHorizontal(parent: ref<inkCompoundWidget>, name: CName) -> ref<inkHorizontalPanel> {
    let widget = new inkHorizontalPanel();
    widget.SetName(name);
    widget.Reparent(parent);
    return widget;
}

func AiNpcInkRect(parent: ref<inkCompoundWidget>, name: CName, colour: Color) -> ref<inkRectangle> {
    let widget = new inkRectangle();
    widget.SetName(name);
    widget.SetTintColor(colour);
    widget.Reparent(parent);
    return widget;
}

func AiNpcInkImage(parent: ref<inkCompoundWidget>, name: CName, atlas: ResRef,
                          part: CName, colour: Color) -> ref<inkImage> {
    let widget = new inkImage();
    widget.SetName(name);
    widget.SetAtlasResource(atlas);
    widget.SetTexturePart(part);
    widget.SetTintColor(colour);
    widget.Reparent(parent);
    return widget;
}

// The family and the weight are not parameters: one typeface is the identity, and a call
// site that could pick another one is a call site that will.
func AiNpcInkText(parent: ref<inkCompoundWidget>, name: CName, text: String,
                         size: Int32, colour: Color) -> ref<inkText> {
    let widget = new inkText();
    widget.SetName(name);
    widget.SetText(text);
    widget.SetFontFamily(AiNpcStyle.FontFamily());
    widget.SetFontStyle(AiNpcStyle.FontStyleBody());
    widget.SetFontSize(size);
    widget.SetTintColor(colour);
    widget.Reparent(parent);
    return widget;
}

//
// Two calls that only ever appear together: a widget that sets a style resource without
// binding a property to it has done nothing, and one that binds without the resource binds
// to nothing. Pairing them is what stops a half-written binding from compiling into silence.

func AiNpcInkBind(widget: ref<inkWidget>, style: ResRef, property: CName, value: CName) -> Void {
    widget.SetStyle(style);
    widget.BindProperty(property, value);
}

// The common case by a wide margin: tint this widget the way the HUD tints its own panels.
func AiNpcInkBindTint(widget: ref<inkWidget>, value: CName) -> Void {
    AiNpcInkBind(widget, AiNpcStyle.MainColorsStyle(), n"tintColor", value);
}
