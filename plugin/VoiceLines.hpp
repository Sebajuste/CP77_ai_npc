// Les repliques qu'un mod donne a couper pour une voix qui n'est pas du casting d'ai_npc.
//
// POURQUOI CA NE PEUT PAS ETRE UN MOTIF. Les archives ne portent aucun chemin, seulement le
// FNV1a64 du chemin en minuscules : rien ici ne peut chercher « toutes les repliques de telle
// etiquette ». Un mod qui veut la voix d'un personnage vanilla doit donc NOMMER ses repliques,
// une par une -- `tools\voice-extract` les choisit hors ligne et en donne la liste.
//
// Les noms sont ceux des fichiers seuls, sans dossier : ils sont identiques d'une langue a
// l'autre, et c'est la locale de doublage du joueur qui decide ou les lire.
//
// Ce que ca vaut : ai_npc ne connait aucun personnage d'un autre mod et ne livre aucune de ses
// repliques. Il prete sa machine ; la matiere reste celle du joueur.

#pragma once

#include <string>
#include <vector>

namespace ainpc::voicelines
{
// Ce que le mod declare pour `aVoiceName` -- le nom de reference sans extension ni derivation.
// Une seconde declaration remplace la premiere : le dernier a parler est celui qui sait.
//
// Rend vrai quand la table a change, ce qui laisse a l'appelant le droit de se taire : la
// declaration est repetee a chaque replique, et une trace par replique noierait le journal.
//
// Ecrite depuis le fil de jeu, lue depuis le worker de la voie parlee.
bool Declare(const std::string& aVoiceName, const std::vector<std::string>& aFileNames);

// Les noms declares pour cette voix, vide quand personne n'en a declare.
std::vector<std::string> For(const std::string& aVoiceName);
} // namespace ainpc::voicelines
