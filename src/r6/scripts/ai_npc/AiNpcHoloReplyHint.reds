// « R Répondre », au-dessus de la ligne de saisie, quand un holo du jeu laisse la parole au
// modèle. Des widgets et aucun état : le tour de parole vit dans AiNpcCallSystem.

module AiNpc

func AiNpcHoloReplyHintGap() -> Float {
    return 70.0;
}

class AiNpcHoloReplyHint extends IScriptable {

    // Faible : le HUD du téléphone est reconstruit sans prévenir, et l'indice avec lui.
    private let m_strip: wref<inkHorizontalPanel>;

    public final func Show(visible: Bool) -> Void {
        if !visible {
            this.Hide();
            return;
        }
        if IsDefined(this.m_strip) {
            return;
        }
        let host = AiNpcHoloInputHost();
        if !IsDefined(host) {
            AiNpcLog("No phone HUD host: the reply hint has nowhere to go.");
            return;
        }

        let strip = AiNpcInkHorizontal(host, n"ainpc_reply_hint");
        strip.SetHAlign(inkEHorizontalAlign.Left);
        strip.SetVAlign(inkEVerticalAlign.Top);
        strip.SetAnchorPoint(new Vector2(0.0, 0.0));
        strip.SetFitToContent(true);
        strip.SetMargin(new inkMargin(AiNpcHoloInputLeft(),
            AiNpcHoloInputTop() - AiNpcHoloReplyHintGap(), 0.0, 0.0));
        AiNpcPhoneHint(strip, n"hint_reply", n"kb_r", AiNpcCallReplyLabel(AiNpcResolveLanguage()));
        this.m_strip = strip;
    }

    public final func Hide() -> Void {
        if !IsDefined(this.m_strip) {
            return;
        }
        let host = AiNpcHoloInputHost();
        if IsDefined(host) {
            host.RemoveChildByName(n"ainpc_reply_hint");
        }
        this.m_strip = null;
    }
}
