// La voix neuronale, embarquee : PocketTTS tourne DANS ai_npc.dll.
//
// Pas de serveur, pas de Python, pas de port, rien a installer pour le joueur au-dela du pack
// de modeles. C'est ce que `Speech.hpp` annoncait -- « swapping SAPI for a real text-to-speech
// service later changes what fills the buffer and nothing else » -- et c'est ce fichier qui le
// remplit desormais.
//
// CE QU'IL FAUT SUR LE DISQUE, et rien de tout cela n'est livre par le zip du mod :
//
//   red4ext\plugins\ai_npc\models\     les .onnx, le tokenizer, bos_before_voice.bin
//   r6\storages\AiNpc\voices\          les references, faites par le joueur
//
// Le pack de modeles s'installe a part (voir docs\MEASURE_VOICE_ENGINE.md). Absent, Available()
// repond non et la voie retombe sur SAPI : un mod sans le pack parle quand meme.
//
// JAMAIS SUR LE FIL DE JEU. Charger le modele prend deux secondes et une replique une a trois ;
// l'appelant est le worker de `ainpc::speech`, jamais l'appelant d'origine.

#pragma once

#include "Audio.hpp"

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

namespace ainpc::voice
{
// Le pack de modeles est-il installe ? Lu sur le disque a chaque appel : un joueur qui installe
// le pack sans relancer le jeu doit pouvoir l'entendre.
bool Available(const std::wstring& aPluginDirectory);

// Le pack installe sait-il faire une voix a partir d'un son ? C'est la presence de l'encodeur
// Mimi, la moitie que le pack libre n'a pas, et elle ne se deduit pas d'Available() : les deux
// packs portent la meme sentinelle.
//
// Se demande AVANT de retenir une reference, parce que les references vivent dans
// r6\storages\, que Vortex ne gere pas : elles survivent a la desinstallation du pack de
// clonage. Sans cette question, un joueur revenu au pack libre choisit un palier que le moteur
// ne sait pas lire et retombe sur la voix de Windows, alors que le catalogue etait la.
bool CanClone(const std::wstring& aPluginDirectory);

// Ce fichier de reference existe-t-il ? Avec CanClone(), c'est ce qui decide, PAR PERSONNAGE,
// si le moteur peut parler de sa voix -- un joueur aura Judy et pas Rogue, et la voie doit etre
// juste dans cet etat plutot que de traiter les voix clonees comme un seul interrupteur.
bool HasVoiceFor(const std::wstring& aPluginDirectory, const std::string& aVoiceFile);

// Cette voix de catalogue est-elle livree avec les modeles ? C'est le palier qui parle quand
// aucun clone n'est possible, et le seul que le pack libre puisse offrir -- son encodeur est a
// zero, donc il ne fabrique aucune voix, mais il en charge de toutes faites.
bool HasCatalogueVoice(const std::wstring& aPluginDirectory, const std::string& aVoiceName);

// Une replique, dite par ce contact, POUSSEE VERS LA VOIE AUDIO AU FIL DE L'EAU.
//
// Le moteur rend son premier morceau en ~123 ms et la replique entiere en une a trois
// secondes. Accumuler avant de jouer faisait attendre la seconde pour entendre la premiere ;
// `ainpc::audio` sait desormais enchainer, alors chaque morceau part des qu'il existe.
//
// Bloquant jusqu'a la fin de la synthese -- le son, lui, a commence bien avant. L'appelant est
// le worker de la voie parlee, jamais le fil de jeu.
//
// La conversion depuis le flottant vit ici et pas dans la voie audio : le moteur rend des
// echantillons flottants, `ainpc::audio` ne prend que du PCM, et il a raison de n'en prendre
// que -- c'est a ce qui remplit le tampon de livrer ce que le tampon promet.
//
// `aVoiceFile` est le nom d'un fichier de r6\storages\AiNpc\voices\, tel que la fiche du
// personnage le declare. Un nom plutot qu'un contact, parce que deux contacts peuvent partager
// une reference et qu'un joueur peut deposer la sienne sous le nom qu'il veut.
//
// `aWhy` n'est rempli qu'en cas d'echec.
// `aSilent` rend tout sans rien jouer : c'est le prechauffage, qui traverse le meme chemin et
// jette ce qu'il produit.
// `aFirstSound` recoit l'instant ou le premier morceau est remis au peripherique ; sa propre
// latence de sortie, quelques dizaines de millisecondes, n'y est pas.
// `aRate` ouvre la sortie a `kSampleRate * aRate` : les memes echantillons, lus plus vite ou
// plus lentement, donc hauteur et debit ensemble et aucun traitement.
bool Render(const std::wstring& aPluginDirectory, const std::string& aVoiceFile,
            const std::string& aUtf8Text, bool aSilent, float aRate,
            std::chrono::steady_clock::time_point& aFirstSound, std::string& aWhy);

// Le format auquel Render() ouvre la sortie pour cette vitesse de lecture.
audio::Format OutputFormat(float aRate);

// Le format que Render() ecrit. Celui de Mimi, pas un choix : 24 kHz mono.
uint32_t SampleRate();
uint16_t Channels();
uint16_t BitsPerSample();

// Abandonne le rendu en cours a la prochaine tranche.
//
// La synthese continue de tourner plusieurs secondes apres qu'on a raccroche, et le worker est
// serie : sans cela, un rappel immediat attendrait la fin d'une replique que plus personne
// n'ecoute. La marque est levee au debut de chaque rendu, donc l'appeler hors rendu ne coute
// rien et n'empeche pas le suivant.
void CancelCurrent();

// Libere le modele et son etat. Appele quand le plugin se decharge.
void Shutdown();
} // namespace ainpc::voice
