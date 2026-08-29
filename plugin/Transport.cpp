#include "Transport.hpp"

#include "Json.hpp"

namespace ainpc
{
bool ParseChatBody(const std::string& aBody, ChatRequest& aRequest, std::string& aError)
{
    json::Value root;
    if (!json::Parse(aBody, root) || !root.IsObject())
    {
        aError = "the request body was not JSON";
        return false;
    }

    aRequest.model = root.StringAt("model");

    const json::Value* messages = root.Find("messages");
    if (!messages || !messages->IsArray())
    {
        aError = "the request body had no messages array";
        return false;
    }

    // Concatenated per role rather than taken one each, because a caller is entitled to send
    // more than one system block -- and joining them here keeps that from being a surprise
    // to every backend separately.
    for (const json::Value& message : messages->items)
    {
        if (!message.IsObject())
        {
            continue;
        }
        const std::string role = message.StringAt("role", "user");
        const std::string content = message.StringAt("content");
        std::string& target = (role == "system") ? aRequest.system : aRequest.user;
        if (!target.empty())
        {
            target += "\n\n";
        }
        target += content;
    }

    if (aRequest.user.empty())
    {
        aError = "the request body had no user message";
        return false;
    }
    return true;
}

std::string MakeChatResponse(const std::string& aText, bool aHaveUsage, long long aPromptTokens,
                             long long aCompletionTokens, long long aCachedTokens)
{
    std::string out = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":";
    out += json::Quote(aText);
    // "stop" is not a guess: a reply only reaches this function once the backend has ruled
    // out a non-zero exit, an error flag and an empty result, so what is left is complete.
    out += "},\"finish_reason\":\"stop\"}]";

    if (aHaveUsage)
    {
        out += ",\"usage\":{\"prompt_tokens\":";
        out += std::to_string(aPromptTokens);
        out += ",\"completion_tokens\":";
        out += std::to_string(aCompletionTokens);
        out += ",\"total_tokens\":";
        out += std::to_string(aPromptTokens + aCompletionTokens);
        out += ",\"prompt_tokens_details\":{\"cached_tokens\":";
        out += std::to_string(aCachedTokens);
        out += "}}";
    }

    out += "}";
    return out;
}

ChatReply Failure(int aStatus, const std::string& aMessage)
{
    ChatReply reply;
    reply.status = aStatus;
    reply.body = "{\"error\":{\"message\":" + json::Quote(aMessage) + "}}";
    return reply;
}

const std::vector<std::wstring>& ScrubbedVariables()
{
    // Anthropic's key and endpoint overrides, the third-party gateway switches, and everything
    // Codex documents as a way to authenticate without a subscription. The list is worth
    // re-reading against each CLI's own documentation when either of them gains a new one: a
    // variable we fail to remove is a player billed per token without being told.
    //
    // CODEX_HOME is deliberately NOT here. It is where the Codex sign-in lives, so removing it
    // would not protect the player -- it would sign them out of their own subscription.
    static const std::vector<std::wstring> variables = {
        L"ANTHROPIC_API_KEY",
        L"ANTHROPIC_AUTH_TOKEN",
        L"ANTHROPIC_BASE_URL",
        L"ANTHROPIC_MODEL",
        L"ANTHROPIC_CUSTOM_HEADERS",
        L"CLAUDE_CODE_USE_BEDROCK",
        L"CLAUDE_CODE_USE_VERTEX",
        L"AWS_BEARER_TOKEN_BEDROCK",
        L"OPENAI_API_KEY",
        L"OPENAI_BASE_URL",
        L"CODEX_API_KEY",
        L"CODEX_ACCESS_TOKEN",
        L"OPENAI_FEDERATION_RULE_ID",
        L"OPENAI_IDENTITY_TOKEN_FILE",
        L"OPENAI_WORKLOAD_IDENTITY_CONTEXT",
    };
    return variables;
}
} // namespace ainpc
