// Fabriquer la voix de reference d'un personnage, sur la machine du joueur, a partir de sa
// propre copie du jeu.
//
// C'est la moitie que `tools\voice-extract` fait hors du jeu et que le mod refusait de faire :
// « des centaines de megaoctets d'intermediaires et des minutes de travail ». Avec une recette
// -- les repliques retenues designees par leur hachage -- ce n'est plus vrai : 1,5 Mo lus dans
// une archive de 5 Go, et moins d'une seconde. Voir docs\PLAN_VOICE_LANE.md § 5.
//
// QUAND. A la premiere replique d'un personnage, pas au chargement. Le cout est de ~250 ms par
// personnage, plus 200 ms une fois pour ouvrir les index ; place la, il tombe dans l'aller-retour
// vers le modele, ou personne ne le voit. Au lancement, ce serait trois secondes ajoutees au
// chargement pour dix voix dont neuf ne serviront peut-etre pas.
//
// CE QUE CA N'EST PAS. Une distribution de voix : rien n'est livre, tout est lu chez le joueur.
// Et ca ne sert que si le pack de clonage est installe -- sans son encodeur, le moteur ne sait
// pas quoi faire d'une reference. C'est `AiNpc::voice::Available` qui tranche, pas ce fichier.

#pragma once

#include <string>

namespace ainpc::voicemake
{
// La recette est-elle la, et les archives de doublage avec ? Repond non sans rien ouvrir de
// couteux : c'est la question qu'on pose avant de decider si une reference est fabricable.
bool Possible(const std::wstring& aPluginDirectory);

// Fabrique `<contact>.wav` dans r6\storages\AiNpc\voices\, ou dit pourquoi elle n'a pas pu.
//
// Bloquant, de l'ordre de la demi-seconde. Appele depuis le worker de la voie parlee, jamais
// depuis le fil de jeu. Rend false si le fichier existe deja : refabriquer une reference que
// le joueur a peut-etre remplacee par la sienne serait la lui reprendre.
// `aLocale` est ce que le jeu repond pour son DOUBLAGE -- "fr-fr", "en-us" -- et pas pour ses
// sous-titres : ce sont deux reglages, et ce sont les archives de la voix qu'on ouvre.
// `aVoiceFile` est le nom du fichier a ecrire ; `aContactId` reste ce que la recette indexe.
bool Make(const std::wstring& aPluginDirectory, const std::string& aContactId,
          const std::string& aVoiceFile, const std::string& aLocale, std::string& aWhy);
} // namespace ainpc::voicemake
