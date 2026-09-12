#include "SpeakableText.hpp"

#include <string_view>

namespace ainpc::voice
{
namespace
{
struct Substitution
{
    std::string_view from;
    std::string_view to;
};

// Les formes entourees d'espaces d'abord : la premiere entree qui correspond gagne.
// L'ASCII n'est pas touche : les signes que le tokenizer rend en octets (« ! », « : ») sont des
// octets qu'il a vus a l'entrainement.
constexpr Substitution kSubstitutions[] = {
    {"\xE2\x80\x99", "'"},       // apostrophe courbe
    {"\xE2\x80\x98", "'"},       // guillemet simple ouvrant
    {"\xCA\xBC", "'"},           // lettre apostrophe
    {"\xE2\x80\xA6", "..."},     // points de suspension
    {" \xE2\x80\x94 ", ", "},    // tiret cadratin
    {" \xE2\x80\x93 ", ", "},    // tiret demi-cadratin
    {"\xE2\x80\x94", ", "},
    {"\xE2\x80\x93", ", "},
    {"\xC2\xA0", " "},           // espace insecable
    {"\xE2\x80\xAF", " "},       // espace fine insecable
    {"\xC3\x80", "A"},           // A accent grave : se prononce comme A
    {"\xC5\x92", "Oe"},          // OE lie
};
} // namespace

std::string Speakable(const std::string& aUtf8Text)
{
    const std::string_view text(aUtf8Text);
    std::string out;
    out.reserve(text.size());

    size_t i = 0;
    while (i < text.size())
    {
        const std::string_view rest = text.substr(i);
        const Substitution* match = nullptr;
        for (const Substitution& substitution : kSubstitutions)
        {
            if (rest.starts_with(substitution.from))
            {
                match = &substitution;
                break;
            }
        }
        if (match != nullptr)
        {
            out += match->to;
            i += match->from.size();
        }
        else
        {
            out += text[i];
            ++i;
        }
    }
    return out;
}
} // namespace ainpc::voice
