// Reading the in-game clock.
//
// Two questions, and they are not the same one. The prompt shows a wall clock ("3:45pm");
// a stored message needs an absolute number it can be SUBTRACTED from, so that a gap marker
// can say how long ago something was said. A formatted clock cannot answer the second.
//
// Both delegate their formatting to AiNpcClockLabel, in the pure history model, so the clock
// in the system prompt and the one inside a gap marker cannot drift apart.

module AiNpc

// The wall clock the prompt shows, as "3:45pm".
func AiNpcGetCurrentTime() -> String {
    let time = GameInstance.GetGameTime(GetGameInstance());
    return AiNpcClockLabel(GameTime.GetSeconds(time));
}

// The absolute stamp a stored message carries.
//
// Seconds since the start of the playthrough, not a time of day: it keeps the day, so two
// messages a week apart cannot read as one hour apart once subtracted.
//
// Returns AiNpcTimeUnknown() if the time system is unreachable -- outside a session, for
// instance -- because a stamp of zero would be indistinguishable from a real midnight.
func AiNpcGetCurrentGameTimeSeconds() -> Int32 {
    let timeSystem = GameInstance.GetTimeSystem(GetGameInstance());
    if !IsDefined(timeSystem) {
        return AiNpcTimeUnknown();
    }
    return GameTime.GetSeconds(timeSystem.GetGameTime());
}
