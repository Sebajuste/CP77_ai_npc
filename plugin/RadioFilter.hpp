// Le filtre « radio » de la voix holo.
//
// La voix sort par waveOut, hors du mixeur du jeu : l'effet que les holos vanilla recoivent ne
// l'atteint pas. Il est donc refait ici, sur le PCM, avant la sortie.
//
// Passe-haut et passe-bas de Butterworth d'ordre 4, puis une saturation douce de gain unitaire
// en petit signal.

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace ainpc::radio
{
enum class Level
{
    Off,
    Light,
    Medium,
    Strong,
};

// La valeur de "holoRadioFilter" dans settings.json. Absente ou inconnue : Medium.
Level LevelNamed(const std::string& aName);
const char* NameOf(Level aLevel);

// Un filtre par replique : son etat enjambe les morceaux, sinon chaque jonction claque.
class Filter
{
public:
    Filter(Level aLevel, uint32_t aSampleRate);

    // PCM 16 bits mono, en place.
    void Process(uint8_t* aPcm, size_t aBytes);

private:
    struct Biquad
    {
        double b0 = 1.0;
        double b1 = 0.0;
        double b2 = 0.0;
        double a1 = 0.0;
        double a2 = 0.0;
        double z1 = 0.0;
        double z2 = 0.0;

        double Step(double aInput);
    };

    Biquad m_stages[4];
    int m_stageCount = 0;
    double m_drive = 0.0;
};
} // namespace ainpc::radio
