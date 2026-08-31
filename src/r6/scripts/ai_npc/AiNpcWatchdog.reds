// The clock on a wait that may never end.
//
// RedHttpClient reports an answer and nothing else. A request that is dropped produces no
// callback at all, and both lanes are built around "the callback is where a request ends":
// with no callback the speaking lane leaves the typing indicator up, `isGenerating` true and
// the input line dead until the save is reloaded, and the thinking lane never compacts again
// for the rest of the session.
//
// A DelaySystem callback is the only clock reachable from here, and it cannot be cancelled.
// So a wait's timer is never cancelled -- the wait is RENAMED. Every wait gets a number, a
// timer carries the number it was armed for, and a timer whose number is no longer current
// has nothing to report. That is what stops the timer of a finished request from cutting
// short the one that replaced it, which a naive boolean cannot.
//
// It holds no game state and makes no decision: each lane owns its own scheduling and decides
// what a timeout means for it. This only answers whose timer is speaking.

module AiNpc

public class AiNpcWatchdog {
    // Names the wait in progress. Never reused and never reset: a name only has to differ
    // from every name still in the delay queue, not to stay small.
    private let m_current: Int32 = 0;

    // Whether anything is waiting at all. The name alone cannot answer that: after a wait
    // ends, m_current holds a name no timer carries, which is indistinguishable from a name
    // whose timer has simply not fired yet.
    private let m_armed: Bool = false;

    // A wait begins. The returned name belongs to the timer armed for it.
    public func Arm() -> Int32 {
        this.m_current += 1;
        this.m_armed = true;
        return this.m_current;
    }

    // The wait ended on its own. Renaming is what disarms: every timer still in the queue
    // now carries a name nobody answers to, including the one just armed.
    public func Disarm() -> Void {
        this.m_current += 1;
        this.m_armed = false;
    }

    public func IsCurrent(waitId: Int32) -> Bool {
        return Equals(waitId, this.m_current);
    }

    // Is an answer still expected? This is what every reply handler asks before it touches
    // anything, on both transports and in both lanes.
    //
    // The question a transport cannot answer for itself: a request is never cancelled, only
    // abandoned, so a provider that takes 95 seconds against a 90-second clock still answers
    // -- into a lane that has since torn the turn down and may be holding a different
    // character's. HTTP has no serial to catch that, and the serial the CLI does carry is
    // still current during the pacing delay between a delivered answer and the end of the
    // generation. One predicate covers both, because it is one question.
    public func IsWaiting() -> Bool {
        return this.m_armed;
    }
}

/// Scheduling ///

// Both lanes arm their timer through here so the one decision that is easy to get wrong is
// made once: a timeout is measured in the same seconds every other delay in this mod uses,
// unaffected by time dilation. A clock that slowed down with the game would let a request
// hang for as long as the player stayed in a menu.
func AiNpcArmTimeout(callback: ref<DelayCallback>, seconds: Float) -> Void {
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(callback, seconds, false);
}

// Each timer names the wait it was armed for and nothing else. Reaching the lane is
// AiNpcLaneCallback's job, including the case where there is no longer a lane to reach.

public class AiNpcSpeakingTimeoutCallback extends AiNpcSpeakingLaneCallback {
    public let waitId: Int32;

    protected func Run(lane: ref<AiNpcHttpSystem>) -> Void {
        lane.OnWaitTimedOut(this.waitId);
    }

    public static func Create(waitId: Int32) -> ref<AiNpcSpeakingTimeoutCallback> {
        let self = new AiNpcSpeakingTimeoutCallback();
        self.waitId = waitId;
        return self;
    }
}

public class AiNpcTestTimeoutCallback extends AiNpcSetupCallback {
    public let waitId: Int32;

    protected func Run(setup: ref<AiNpcSetupSystem>) -> Void {
        setup.OnTestTimedOut(this.waitId);
    }

    public static func Create(waitId: Int32) -> ref<AiNpcTestTimeoutCallback> {
        let self = new AiNpcTestTimeoutCallback();
        self.waitId = waitId;
        return self;
    }
}

public class AiNpcActionTimeoutCallback extends AiNpcActionLaneCallback {
    public let waitId: Int32;

    protected func Run(lane: ref<AiNpcActionService>) -> Void {
        lane.OnWaitTimedOut(this.waitId);
    }

    public static func Create(waitId: Int32) -> ref<AiNpcActionTimeoutCallback> {
        let self = new AiNpcActionTimeoutCallback();
        self.waitId = waitId;
        return self;
    }
}

public class AiNpcThinkingTimeoutCallback extends AiNpcThinkingLaneCallback {
    public let waitId: Int32;

    protected func Run(lane: ref<AiNpcMemoryService>) -> Void {
        lane.OnWaitTimedOut(this.waitId);
    }

    public static func Create(waitId: Int32) -> ref<AiNpcThinkingTimeoutCallback> {
        let self = new AiNpcThinkingTimeoutCallback();
        self.waitId = waitId;
        return self;
    }
}
