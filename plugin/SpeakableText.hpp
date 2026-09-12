// Le texte d'une replique, reecrit dans le vocabulaire du modele de voix.
//
// Le tokenizer du modele francais (4000 morceaux) ne connait ni l'apostrophe courbe, ni les
// tirets, ni les espaces insecables, ni les points de suspension en un signe. Il les decoupe en
// octets bruts, que le modele n'a presque jamais vus : mesure le 2026-09-11, « t’arrive » se
// prononce « te arrive ». Le LLM, lui, ecrit ces signes. Le chat et le journal les gardent ;
// seule la voix recoit la forme ASCII.

#pragma once

#include <string>

namespace ainpc::voice
{
std::string Speakable(const std::string& aUtf8Text);
} // namespace ainpc::voice
