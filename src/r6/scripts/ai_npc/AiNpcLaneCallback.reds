// How a delayed call finds the lane it was addressed to.
//
// A DelaySystem timer cannot be cancelled and does not belong to the session that armed it:
// it fires into whatever process state exists at the time, which may be a main menu, a
// different save, or a session that is still attaching its systems. The container lookup
// therefore answers null, and a callback that dereferences it dies in a place with no caller
// to blame -- the stack names the delay system.
//
// Every delayed call in this mod resolves through one of the classes below, so the check that
// makes that safe is written once per lane rather than once per timer. Doing nothing is the
// whole of the correct behaviour: the lane the timer was speaking to no longer exists, so it
// has nothing to be told.
//
// One base class per lane rather than one carrying a target: the lanes are deliberately
// separate, and neither may be reachable through the other's state.

module AiNpc

public abstract class AiNpcSpeakingLaneCallback extends DelayCallback {
    public func Call() {
        let lane = GetAiNpcHttpSystem();
        if IsDefined(lane) {
            this.Run(lane);
        }
    }

    protected func Run(lane: ref<AiNpcHttpSystem>) -> Void {}
}

public abstract class AiNpcThinkingLaneCallback extends DelayCallback {
    public func Call() {
        let lane = AiNpcMemoryService.Get();
        if IsDefined(lane) {
            this.Run(lane);
        }
    }

    protected func Run(lane: ref<AiNpcMemoryService>) -> Void {}
}

abstract class AiNpcCallLaneCallback extends DelayCallback {
    public func Call() {
        let call = AiNpcCallSystem.Get();
        if IsDefined(call) {
            this.Run(call);
        }
    }

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {}
}

public abstract class AiNpcSetupCallback extends DelayCallback {
    public func Call() {
        let setup = GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(NameOf<AiNpcSetupSystem>()) as AiNpcSetupSystem;
        if IsDefined(setup) {
            this.Run(setup);
        }
    }

    protected func Run(setup: ref<AiNpcSetupSystem>) -> Void {}
}
