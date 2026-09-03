// La voix de secours : celle que Windows installe.
//
// Elle ne ressemble a aucun personnage et n'essaie pas. Ce qu'elle apporte est un plancher --
// un joueur qui n'a pas installe le pack de modeles, ou qui n'a fait aucune reference, entend
// quand meme parler. Un mod qui se tait quand une dependance manque se lit comme un mod casse.
//
// Elle vaut aussi comme temoin : quand la voie neuronale ne sort rien, entendre SAPI dire la
// meme replique separe « le moteur a echoue » de « rien n'est arrive jusqu'ici ».
//
// COM doit etre initialise sur le fil appelant, ou ne l'etre sur aucun -- Render() s'en charge
// quand personne d'autre ne l'a fait.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ainpc::sapi
{
// Une replique, en PCM 16 bits mono. Bloquant. `aWhy` n'est rempli qu'en cas d'echec.
//
// Ce que SAPI ecrit est deja du PCM au format demande, donc rien a convertir ici -- c'est la
// difference avec la voie neuronale, qui rend du flottant.
bool Render(const std::string& aUtf8Text, std::vector<uint8_t>& aSamples, std::string& aWhy);

// Mono 22050, ce qui est deja la bande passante d'un telephone et le quart des octets d'un
// 44100 stereo.
uint32_t SampleRate();
uint16_t Channels();
uint16_t BitsPerSample();
} // namespace ainpc::sapi
