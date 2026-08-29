module AiNpc

// The single source of truth for the mod version.
//
// It lives in the shipped scripts rather than only in the archive name, because the archive
// name does not survive installation: Vortex identifies a mod by the MD5 of its archive
// against a meta server, falls back to the file name for a locally built zip, and reads
// nothing at all from inside it. Once installed there is otherwise no way to tell which build
// is running.
//
// tools\package.ps1 reads this value and names the archive from it, so the two cannot
// disagree.

func AiNpcVersion() -> String {
    return "0.9.5";
}
