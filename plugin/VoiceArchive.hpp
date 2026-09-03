// Lire une replique de doublage dans les archives du joueur, sans rien y ecrire.
//
// Les archives de Cyberpunk ne stockent JAMAIS un chemin : seulement le FNV1a64 du chemin en
// minuscules. C'est ce qui rend une recette possible -- huit octets par replique retenue, et
// aucun dictionnaire a livrer. Voir docs\PLAN_VOICE_LANE.md § 5.
//
// CE QUI REND CE LECTEUR COURT. Le doublage est le seul coin des archives ou tout est simple,
// et c'est mesure : sur 401 fichiers echantillonnes parmi les 103 221 du doublage francais, un
// seul segment, jamais compresse, sans exception. Donc pas d'Oodle sur ce chemin, et pas de
// remontage de segments. Un lecteur general aurait besoin des deux.
//
// PENDANT QUE LE JEU TOURNE, et c'est la seule chose qui pouvait tuer l'idee : les archives
// sont ouvertes en partage lecture-ecriture, jamais en exclusif. Mesure du 2026-09-01, jeu
// lance : dix extraits en 2,9 s au lieu de 2,8, identiques octet pour octet.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ainpc::archive
{
// Le FNV1a64 d'un chemin depot, qui est la seule facon de designer un fichier.
//
// Le chemin est mis en minuscules et ses separateurs sont des antislashs : c'est sous cette
// forme que le jeu a calcule ses hachages, et une majuscule suffit a ne rien trouver.
uint64_t HashOfDepotPath(const std::string& aDepotPath);

// La locale que le jeu donne pour son doublage -- "fr-fr", "en-us" -- vers le code qui nomme
// l'archive : `lang_fr_voice.archive`. Vide quand cette locale n'a pas de doublage connu.
//
// La distinction n'est pas cosmetique : le jeu a deux reglages de langue, le texte et la voix,
// et ce sont les archives de LA VOIX qui portent les repliques. Un joueur en sous-titres
// francais sur un doublage anglais existe, et c'est l'anglais qu'il faut cloner.
std::string ArchiveCodeForLocale(const std::string& aLocale);

// Les archives de doublage d'une langue -- le jeu de base et Phantom Liberty -- vues comme un
// seul corpus. Ouvertes une fois, gardees ouvertes : leurs index pesent 10 Mo dans 6,7 Go et
// les relire par personnage couterait 200 ms a chaque fois.
class VoiceArchives
{
public:
    // `aLanguage` est un code de doublage : "fr", "en", "de"... Rend false quand aucune archive
    // de cette langue n'est installee, ce qui est le cas ordinaire pour une langue que le
    // joueur n'a pas telechargee.
    bool Open(const std::wstring& aGameRoot, const std::string& aLanguage);

    bool IsOpen() const;

    // Les octets bruts d'un fichier, tels que l'archive les porte. False quand ce hachage n'est
    // pas dans cette installation -- ce qui arrive apres un correctif qui reencode le doublage,
    // et c'est la limite connue d'une recette.
    bool Read(uint64_t aHash, std::vector<uint8_t>& aOut) const;

    void Close();

    ~VoiceArchives();

private:
    struct Volume;

    // Ouvre une archive et retient l'emplacement du segment unique de chaque fichier. Membre
    // plutot que fonction libre parce que Volume est a nous : un lecteur exterieur n'a aucune
    // raison de savoir comment une archive est indexee.
    static Volume* OpenVolume(const std::wstring& aPath);

    std::vector<Volume*> m_volumes;
};
} // namespace ainpc::archive
