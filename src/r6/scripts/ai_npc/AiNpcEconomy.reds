// The one place this mod moves eddies.
//
// The cap is the point of the file. A transfer is requested by an ACTION TAG in a model's
// reply, and a model can be argued with: nothing stops a player from talking a character into
// emitting the tag every message, whatever amount each one names. AiNpcActions clamps one tag
// to the cap; AiNpcTransferLedger clamps the conversation to it, per contact.
//
// What is left here is the half that needs the game: the item grant, and the log line the
// ledger is not allowed to write.
//
// A ScriptableSystem, so the running totals are per-playthrough and cannot leak across a save
// load. Deliberately NOT persistent: the allowance resets with the conversation, and a reload
// landing on an older save should not inherit a spend it never made.

module AiNpc

public class AiNpcEconomySystem extends ScriptableSystem {

    public static func Get() -> ref<AiNpcEconomySystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(NameOf<AiNpcEconomySystem>()) as AiNpcEconomySystem;
    }

    private let m_ledger: ref<AiNpcTransferLedger>;

    private func OnAttach() -> Void {
        this.m_ledger = new AiNpcTransferLedger();
    }

    // Returns what actually moved, which is not always what was asked for. The caller needs
    // that number rather than a Bool: a character who promised 750 and released 300 has to be
    // told the real figure, or its next message carries on as though the whole sum had gone.
    // Reporting only to the log is how that promise was broken silently for as long as this
    // command has existed.
    public func TransferMoneyToPlayer(contactId: String, amount: Int32) -> Int32 {
        let granted = this.m_ledger.Grant(contactId, amount, AiNpcTransferCap());

        if granted <= 0 {
            AiNpcLog(s"Transfer of \(amount) from '\(contactId)' refused: cap of \(AiNpcTransferCap()) eddies already reached with this contact.");
            return 0;
        }

        let player = GetPlayer(this.GetGameInstance());
        let transactionSystem = GameInstance.GetTransactionSystem(this.GetGameInstance());
        let moneyID = ItemID.FromTDBID(t"Items.money");
        transactionSystem.GiveItem(player, moneyID, granted);

        AiNpcLog(s"'\(contactId)' transferred \(granted) eddies (\(this.m_ledger.SpentOn(contactId))/\(AiNpcTransferCap()) with this contact).");
        return granted;
    }

    // Called when a thread is cleared, from the one door that clears one: the character starts
    // fresh, and so does its allowance. Everybody else's total is left alone -- clearing one
    // conversation says nothing about what another character has already released.
    public func ResetTransferAllowance(contactId: String) -> Void {
        this.m_ledger.Reset(contactId);
    }
}
