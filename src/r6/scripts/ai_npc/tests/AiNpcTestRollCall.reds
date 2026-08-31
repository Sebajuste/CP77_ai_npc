module AiNpc

// L'appel : la seule liste de tout ce qui s'execute au demarrage d'une session.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

func AiNpcRunAllTests() -> ref<AiNpcTestRunner> {
    let t = new AiNpcTestRunner();

    AiNpcTestTrimLeadingBlanks(t);
    AiNpcTestTidyAfterRemoval(t);
    AiNpcTestAppend(t);
    AiNpcTestTrim(t);
    AiNpcTestUndo(t);
    AiNpcTestPendingReply(t);
    AiNpcTestScriptedReply(t);
    AiNpcTestTranscript(t);
    AiNpcTestLegacyMigration(t);
    AiNpcTestJsonRoundTrip(t);
    AiNpcTestMessageTime(t);
    AiNpcTestGapMarkers(t);
    AiNpcTestJournal(t);
    AiNpcTestJournalPointer(t);
    AiNpcTestJournalListing(t);
    AiNpcTestResponseExtraction(t);
    AiNpcTestActionParsing(t);
    AiNpcTestTransferClamp(t);
    AiNpcTestTransferLedger(t);
    AiNpcTestContactSupport(t);
    AiNpcTestDoor(t);
    AiNpcTestReplaceAll(t);
    AiNpcTestTemplateExpansion(t);
    AiNpcTestActionTagInventory(t);
    AiNpcTestConfigHelpers(t);
    AiNpcTestPromptOverrides(t);
    AiNpcTestRecipeSchema(t);
    AiNpcTestRecipeQueries(t);
    AiNpcTestRecipeParse(t);
    AiNpcTestRecipeRefusals(t);
    AiNpcTestRecipeBook(t);
    AiNpcTestRecipeTemplate(t);
    AiNpcTestRecipeRendering(t);
    AiNpcTestRecipeSpeechMoved(t);
    AiNpcTestSlotResolution(t);
    AiNpcTestSlotAliases(t);
    AiNpcTestSlotOverlay(t);
    AiNpcTestPassSources(t);
    AiNpcTestPassTable(t);
    AiNpcTestPassBuilders(t);
    AiNpcTestModelPresets(t);
    AiNpcTestTruncation(t);
    AiNpcTestActionSelector(t);
    AiNpcTestArchiveNumber(t);
    AiNpcTestContactHash(t);
    AiNpcTestRomanceFacts(t);
    AiNpcTestQuestSheets(t);
    AiNpcTestSheetActions(t);
    AiNpcTestVariantFields(t);
    AiNpcTestLanguageFromLocale(t);
    AiNpcTestGenderStatement(t);
    AiNpcTestPlayerDescription(t);
    AiNpcTestWorldLore(t);
    AiNpcTestWorldKnowledge(t);
    AiNpcTestTransportFailure(t);
    AiNpcTestUtf8(t);
    AiNpcTestDiagnosticMessage(t);
    AiNpcTestCliRouting(t);
    AiNpcTestReply(t);
    AiNpcTestWatchdog(t);
    AiNpcTestFactBridge(t);
    AiNpcTestWeather(t);
    AiNpcTestRuleComposition(t);
    AiNpcTestSectionText(t);
    AiNpcTestCarrierMessage(t);
    AiNpcTestMemoryPolicy(t);
    AiNpcTestMemoryClamp(t);
    AiNpcTestMemoryFounding(t);
    AiNpcTestMemoryRender(t);
    AiNpcTestMemoryRequest(t);
    AiNpcTestMemoryParse(t);
    AiNpcTestMemoryMerge(t);
    AiNpcTestMemoryRebase(t);
    AiNpcTestMemoryPacts(t);
    AiNpcTestMemoryArchive(t);
    AiNpcTestMemoryWindow(t);
    AiNpcTestMemoryIdleWindow(t);
    AiNpcTestMemoryJournal(t);
    AiNpcTestQuestContext(t);
    AiNpcTestSectionChain(t);
    AiNpcTestUiLabels(t);
    AiNpcTestTerminalOrder(t);
    AiNpcTestTerminalWrap(t);
    AiNpcTestKeyboardCapture(t);
    AiNpcTestKeyRepeat(t);
    AiNpcTestSessionRegistryPolicy(t);
    AiNpcTestSessionPolicy(t);
    AiNpcTestCallTransitions(t);
    AiNpcTestCallOpensOnce(t);
    AiNpcTestPhoneState(t);
    AiNpcTestPhoneOpenIntent(t);
    AiNpcTestPhoneForbidden(t);
    AiNpcTestPendingContext(t);
    AiNpcTestExtensionOrder(t);
    AiNpcTestFloorLease(t);
    AiNpcTestTicketBook(t);
    AiNpcTestSpeechQueue(t);
    AiNpcTestExtensionCoverage(t);
    AiNpcTestRepairPolicy(t);
    AiNpcTestGeneration(t);
    AiNpcTestTranscriptEndings(t);
    AiNpcTestRequestLog(t);
    AiNpcTestUsageLedger(t);
    AiNpcTestBudgetMessages(t);

    return t;
}

/// Chat session policy, observed through a mock renderer ///

// A renderer that draws nothing and records everything.
//
// It answers the two questions whose answer changes the session's behaviour -- SplitBudget
// and IsAtBottom -- as instructed, because a mock that always said "yes, at the bottom"
// would make the follow-the-conversation assertions pass without ever exercising the branch
// that leaves a reader alone.
