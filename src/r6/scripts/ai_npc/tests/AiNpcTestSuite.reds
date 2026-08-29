// The seam, and nothing else. This file declares a module and holds no code.
//
// A release build ships without the self-tests, so something in the shipped half has to be
// able to ask whether they are there. `@if(ModuleExists(...))` is the only question redscript
// can answer at compile time, and it takes a MODULE -- so a module has to exist for the answer
// to be no. AiNpcSelfTest.reds is what asks.
//
// That job used to belong to `module AiNpc.Tests` on the assertions themselves, which made the
// assertions live in a different module from the code they assert. Cross-module access needs
// `public`, so 284 declarations were exported to every other mod on the machine for the sole
// benefit of a test file that is deleted before release -- the suite was deciding ai_npc's
// public ABI. Splitting the marker off puts the assertions back in `module AiNpc`, where they
// reach what they test without any of it being exported.
//
// This file lives in tests\ with the assertions, and tools\package.ps1 drops that whole folder
// for a release. The folder is the unit on purpose: a list of file names shipped 5000 lines of
// assertions the day somebody forgot to extend it. What the folder cannot give on its own,
// package.ps1 checks by hand -- that this file is inside it. The marker without the assertions
// would leave AiNpcSelfTest.reds calling a function that is not in the build; the assertions
// without the marker would compile out of reach and report "0 tests", which reads exactly like
// a mod that never started.

module AiNpc.TestSuite
