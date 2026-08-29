// The seam, and nothing else. This file declares a module and holds no code.
//
// A release build ships without the self-tests, so something in the shipped half has to be
// able to ask whether they are there. `@if(ModuleExists(...))` is the only question redscript
// can answer at compile time, and it takes a MODULE -- so a module has to exist for the answer
// to be no. AiNpcSelfTest.reds is what asks.
//
// That job used to belong to `module AiNpc.Tests` on AiNpcTests.reds itself, which made the
// assertions live in a different module from the code they assert. Cross-module access needs
// `public`, so 284 declarations were exported to every other mod on the machine for the sole
// benefit of a test file that is deleted before release -- the suite was deciding ai_npc's
// public ABI. Splitting the marker off puts the assertions back in `module AiNpc`, where they
// reach what they test without any of it being exported.
//
// tools\package.ps1 drops THIS FILE AND AiNpcTests.reds together, and checks both directions:
// the marker without the suite would leave AiNpcSelfTest.reds calling a function that is not
// in the build, and the suite without the marker would compile the assertions out of reach and
// report "0 tests", which reads exactly like a mod that never started.

module AiNpc.TestSuite
