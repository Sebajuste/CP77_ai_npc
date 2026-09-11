// La ligne de saisie d'un appel : le champ du terminal, qui prévient l'appel quand il rend le
// clavier. Toutes les sorties passent par ReleaseKeyboard -- Entrée, Échap, un clic ailleurs,
// un autre champ qui prend le clavier -- donc aucune n'est oubliée.

module AiNpc

class AiNpcHoloField extends AiNpcTerminalField {

    public func ReleaseKeyboard() -> Void {
        let held = this.IsFocused();
        super.ReleaseKeyboard();
        if !held {
            return;
        }
        let call = AiNpcCallSystem.Get();
        if IsDefined(call) {
            call.ReportTypingEnded();
        }
    }
}
