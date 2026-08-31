// The second half of ai_npc.dll's native surface: sound.
//
// Read the head of AiNpcCliNative.reds before adding anything here. A native class that no
// loaded plugin registered does not fail gracefully -- RED4ext validates the compiled blob
// after every plugin has loaded and refuses it, and the GAME does not start. This file is the
// second line that error can carry, and there must not be a third without a reason.
//
// It is a class of its own rather than a function bolted onto AiNpcCli because the name would
// then lie: `AiNpcCli.Beep()` says the CLI lanes make sound, and nothing about the two is
// related beyond sharing a DLL. One line of boot risk is the price of a name that is true.
//
// @if(ModuleExists()) cannot guard any of this: the validation happens against the compiled
// blob, before a conditional would be evaluated.

module AiNpc

public native class AiNpcAudio {
    // Plays a short tone through the system's audio output, generated in the DLL: no asset,
    // no manifest, no file read or written. It is the proof that the mod can make a sound at
    // all, and it is the only thing this class does today.
    //
    // Returns what the device said, in words, and writes the same sentence to
    // red4ext\logs\ai_npc-*.log. A String rather than a Bool because the answer IS the
    // measurement: silence has two causes that look identical from a chair -- the device
    // refused the format, or it took the buffer and played it somewhere nobody is listening --
    // and only the device can tell them apart.
    public static native func Beep() -> String;

    // Says a line out loud, through the system's own speech synthesiser, and plays it on the
    // same path as everything else this class makes: memory to speakers, no file.
    //
    // Returns at once, so the answer describes the PREVIOUS line -- the one just handed over
    // has not been spoken yet, and the delay it reports is what the voice lane is judged on.
    public static native func Speak(text: String) -> String;
}
