// Reading a JSON value that may not be there.
//
// Every accessor returns null or "" instead of dereferencing a missing field. A chain of
// unchecked casts down a response body --
//
//   responseObj.GetKey("choices") as JsonArray -> .GetItem(0u) as JsonObject -> ...
//
// -- yields null at the first step whenever the payload is an ERROR object rather than a
// completion, and takes the whole callback down with it. Free OpenRouter models return error
// objects routinely, so that path is the common one.
//
// Generic rather than response-shaped: the memory model, the journal and the config loader
// all read JSON a human or an older build may have written, and all four callers need the
// same "absent reads as absent" guarantee.

module AiNpc

import RedData.Json.*

func AiNpcAsJsonObject(value: ref<JsonVariant>) -> ref<JsonObject> {
    if !IsDefined(value) || value.IsUndefined() || !value.IsObject() {
        return null;
    }
    return value as JsonObject;
}

func AiNpcJsonObjectAt(parent: ref<JsonObject>, key: String) -> ref<JsonObject> {
    if !IsDefined(parent) || !parent.HasKey(key) {
        return null;
    }
    return AiNpcAsJsonObject(parent.GetKey(key));
}

func AiNpcJsonArrayAt(parent: ref<JsonObject>, key: String) -> ref<JsonArray> {
    if !IsDefined(parent) || !parent.HasKey(key) {
        return null;
    }
    let value = parent.GetKey(key);
    if !IsDefined(value) || value.IsUndefined() || !value.IsArray() {
        return null;
    }
    return value as JsonArray;
}

func AiNpcJsonItemObject(items: ref<JsonArray>, index: Uint32) -> ref<JsonObject> {
    if !IsDefined(items) || index >= items.GetSize() {
        return null;
    }
    return AiNpcAsJsonObject(items.GetItem(index));
}

func AiNpcJsonString(parent: ref<JsonObject>, key: String) -> String {
    if !IsDefined(parent) || !parent.HasKey(key) {
        return "";
    }
    let value = parent.GetKey(key);
    if !IsDefined(value) || value.IsUndefined() || !value.IsString() {
        return "";
    }
    return value.GetString();
}

// A whole number that may not be there, with an explicit answer for "it was not there".
//
// The caller states what absence reads as, because zero is a legitimate value everywhere
// this is used: a provider that reports `completion_tokens: 0` measured something, and a
// provider that reports no usage block at all measured nothing. Collapsing the two would
// put invented zeroes in the request log and make an unmeasured day look free.
//
// The three numeric shapes are all accepted because none of them is under our control: the
// same field arrives as an integer from one provider and as a double from a proxy that
// round-tripped the body through a JSON library with no integer type.
func AiNpcJsonInt(parent: ref<JsonObject>, key: String, absent: Int32) -> Int32 {
    if !IsDefined(parent) || !parent.HasKey(key) {
        return absent;
    }
    let value = parent.GetKey(key);
    if !IsDefined(value) || value.IsUndefined() {
        return absent;
    }
    if value.IsInt64() {
        return Cast<Int32>(value.GetInt64());
    }
    if value.IsUint64() {
        return Cast<Int32>(value.GetUint64());
    }
    if value.IsDouble() {
        return Cast<Int32>(value.GetDouble());
    }
    return absent;
}
