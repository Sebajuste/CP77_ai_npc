module AiNpc

import RedFileSystem.*
import RedData.Json.*

// Le collecteur de resultats, et ce qui les ecrit sur le disque.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

class AiNpcTestRunner {
    public let passed: Int32 = 0;
    public let failures: array<String>;

    public func Check(name: String, condition: Bool) -> Void {
        if condition {
            this.passed += 1;
        } else {
            ArrayPush(this.failures, name);
        }
    }

    public func EqString(name: String, actual: String, expected: String) -> Void {
        if Equals(actual, expected) {
            this.passed += 1;
        } else {
            ArrayPush(this.failures, s"\(name): expected [\(expected)], got [\(actual)]");
        }
    }

    public func EqInt(name: String, actual: Int32, expected: Int32) -> Void {
        if actual == expected {
            this.passed += 1;
        } else {
            ArrayPush(this.failures, s"\(name): expected \(expected), got \(actual)");
        }
    }

    public func EqBool(name: String, actual: Bool, expected: Bool) -> Void {
        if Equals(actual, expected) {
            this.passed += 1;
        } else {
            ArrayPush(this.failures, s"\(name): expected \(expected), got \(actual)");
        }
    }

    public func Total() -> Int32 {
        return this.passed + ArraySize(this.failures);
    }
}

// Compact history builder: "V:hi" is a message from V, "N:yo" a reply from the character.

func AiNpcWriteTestResults(t: ref<AiNpcTestRunner>, storage: ref<FileSystemStorage>) -> Void {
    let failed = ArraySize(t.failures);

    if failed > 0 {
        FTLogError(s"[ai_npc]: SELF-TESTS FAILED: \(failed) of \(t.Total()).");
        let i = 0;
        while i < failed {
            FTLogError(s"[ai_npc]:   - \(t.failures[i])");
            i += 1;
        }
    } else {
        FTLog(s"[ai_npc]: self-tests passed (\(t.passed)/\(t.Total())).");
    }

    if !IsDefined(storage) {
        return;
    }

    let failureList = ParseJson("[]") as JsonArray;
    let i = 0;
    while i < failed {
        failureList.AddItemString(t.failures[i]);
        i += 1;
    }

    let root = ParseJson("{}") as JsonObject;
    root.SetKeyInt64("passed", Cast<Int64>(t.passed));
    root.SetKeyInt64("failed", Cast<Int64>(failed));
    root.SetKeyInt64("total", Cast<Int64>(t.Total()));
    root.SetKey("failures", failureList);

    storage.GetFile("test-results.json").WriteJson(root, "    ");
}

/// The phone state machine ///

// Renders an edge as one letter, so a whole navigation reads as a string in the assertion:
// R raised, T tab switch, B rebuild.
