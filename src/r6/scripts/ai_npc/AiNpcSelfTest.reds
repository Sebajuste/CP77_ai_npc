module AiNpc

import RedFileSystem.*

// The seam that lets a release build ship without the self-tests.
//
// AiNpcStorageService calls AiNpcRunSelfTests once its storage handle is settled -- that is
// the only point in startup where "the storage is open, or it definitively is not" is a
// fact, and the results have to land in that storage for tools\test.ps1 to read them
// offline. What it calls depends on whether the tests\ folder is in the build:
//
//   debug build    AiNpcTestSuite.reds is there to declare the module, the first branch
//                  compiles and the suite runs at startup.
//   release build  tools\package.ps1 dropped the whole tests\ folder, ModuleExists is
//                  false, the second branch compiles and this is a no-op the compiler inlines
//                  away.
//
// The module asked about is AiNpcTestSuite.reds and NOT the file holding the assertions: those
// live in `module AiNpc` like the rest of the mod, so they reach what they test without any of
// it having to be exported. No import here for the same reason. See AiNpcTestSuite.reds.
//
// Conditional compilation rather than an annotation: @wrapMethod cannot target a class
// declared in the same compilation pass (UNRESOLVED_METHOD on a script-defined class, in a
// module or not), so the tests cannot mount themselves onto the service. Something in the
// shipped build has to name them, and this file is that something -- the same shape the
// terminal site uses for BrowserExtension: one mod, two valid builds.
@if(ModuleExists("AiNpc.TestSuite"))
public func AiNpcRunSelfTests(storage: ref<FileSystemStorage>) -> Void {
    AiNpcWriteTestResults(AiNpcRunAllTests(), storage);
}

@if(!ModuleExists("AiNpc.TestSuite"))
public func AiNpcRunSelfTests(storage: ref<FileSystemStorage>) -> Void {}
