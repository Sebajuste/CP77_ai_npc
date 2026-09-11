// La voie parlee : une file, un worker, et le choix du moteur.
//
// Ce fichier ne synthetise rien. Il ordonne des repliques, en choisit le moteur, et remet le
// tampon a `ainpc::audio` -- de sorte que :
//
//   - il n'y a qu'un seul chemin audio dans le mod, deja mesure en jeu ;
//   - raccrocher coupe la voix, parce que Stop() appartient a ce chemin ;
//   - changer de moteur ne change que ce qui remplit le tampon.
//
// DEUX MOTEURS, ET LE DISQUE ARBITRE. `ainpc::voice` est PocketTTS, embarque dans cette DLL :
// il parle de la voix du personnage, et il lui faut le pack de modeles plus une reference pour
// ce contact. `ainpc::sapi` est la voix de Windows : elle ne ressemble a personne et elle est
// toujours la. Le choix se fait par personnage et a chaque replique, parce qu'un joueur aura
// Judy et pas Rogue -- traiter les voix clonees comme un seul interrupteur serait faux dans
// l'etat ou se trouvent la plupart des installations.
//
// JAMAIS SUR LE FIL APPELANT. Une replique coute une a trois secondes, et l'appelant est le
// jeu. Speak() met en file et rend la main ; un worker fait le travail et remet lui-meme le
// tampon au chemin audio.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ainpc::speech
{
// Met une replique en file. Rend false seulement si elle est vide ou si le worker ne demarre
// pas ; un echec de SYNTHESE se signale plus tard, par le journal, parce qu'a ce moment-la
// l'appelant est parti.
//
// `aContactId` designe qui parle, et c'est ce qui choisit la voix. Vide, la replique est dite
// par la voix de secours -- ce qui est le bon comportement pour une ligne qui n'appartient a
// aucun personnage.
//
// `aVoiceFile` est le fichier de reference que la fiche du personnage nomme -- `judy.wav` par
// defaut, autre chose si elle le dit. Vide, la voie descend d'un palier sans rien tenter.
//
// `aCatalogueVoice` est la voix de catalogue que la fiche nomme -- ce qui parle quand aucun
// clone n'est possible, et le seul palier que le pack libre puisse offrir.
//
// `aVoiceOverLocale` est la langue du DOUBLAGE du jeu, telle qu'il la donne : c'est dans ces
// archives-la qu'une reference se fabrique, et pas dans celles des sous-titres.
//
// Les repliques sont dites dans l'ordre ou elles arrivent : un personnage ne se parle pas
// dessus, et une reponse streamee arrive ici en plusieurs phrases qui sont une seule prise de
// parole coupee en morceaux. Une file qui prend du retard sur le joueur cesse de grandir --
// la borne et le bout qu'elle laisse tomber sont dans Speech.cpp.
//
// `aRate` est la vitesse de lecture de la voix neuronale : 1,06 la joue un demi-ton plus haut
// et six pour cent plus vite. La voix de secours l'ignore.
//
// Rend le numero de la replique, celui que son resultat citera ; zero quand rien n'est mis en file.
uint32_t Speak(const std::string& aUtf8Text, const std::string& aContactId,
               const std::string& aVoiceFile, const std::string& aCatalogueVoice,
               const std::string& aVoiceOverLocale, float aRate);

// Prepare la voix d'un personnage sans rien dire, et rend la main aussitot.
//
// Ce que cela paie d'avance : charger le modele (~2,5 s, une fois par session), fabriquer la
// reference depuis les archives du joueur (~250 ms, une fois par personnage) et la cloner
// (~3 s, une fois par personnage). Sept secondes qu'un joueur entendrait autrement comme un
// silence apres la premiere replique.
//
// Appele quand un appel commence a sonner : la sonnerie dure vingt secondes, et personne
// n'attend pendant. Sans effet si tout est deja chaud, et sans effet du tout quand le pack de
// modeles est absent.
void Warm(const std::string& aContactId, const std::string& aVoiceFile,
          const std::string& aCatalogueVoice, const std::string& aVoiceOverLocale);

// Ouvre la sortie au format de la voix qui va parler, avant qu'elle ait quoi que ce soit a dire.
// Appelee sur le fil de jeu quand une reponse parlee est demandee, quel que soit le canal : la
// sortie ouverte avale son propre silence au lieu du premier mot. Sans effet sur une sortie deja
// ouverte. Rend ce qui s'est passe, en mots.
std::string Prime(const std::string& aVoiceFile, const std::string& aCatalogueVoice, float aRate);

// Ce que le haut-parleur est en train de dire, mot pour mot. Vide quand rien ne joue.
//
// LE SEUL MOYEN DE FAIRE SUIVRE UN SOUS-TITRE. Une reponse arrive phrase par phrase et la file
// les joue dans l'ordre, donc au moment ou la troisieme est mise en file, c'est la premiere
// qu'on entend. Une surface qui affiche ce qu'elle vient d'envoyer affiche donc la mauvaise, et
// une duree estimee ne la rattrape pas -- elle derive a chaque phrase.
//
// La file, elle, sait : chaque morceau porte le numero de sa replique, et le premier morceau que
// le peripherique n'a pas encore rendu est celui qu'on entend. Le texte revient plutot que le
// numero pour que l'appelant n'ait aucune comptabilite a tenir : il affiche ce qu'on lui donne.
std::string Speaking();

// Le silence, tout de suite : ce qui joue s'arrete, ce qui attendait est jete, et la replique
// en cours de synthese est abandonnee.
//
// Appelee quand le joueur raccroche. Les trois vont ensemble : couper le son en laissant la
// file ferait parler un contact a qui plus personne ne parle, et laisser la synthese finir
// retarderait de plusieurs secondes le premier mot du prochain appel -- le worker est serie.
//
// La chaleur des voix n'est pas touchee : elle a coute sept secondes et ne depend d'aucun appel.
void Silence();

// Ou en est la preparation de cette voix, en un mot :
//
//   "ready"        elle est chaude ; la premiere replique ne coutera que sa synthese
//   "pending"      elle chauffe encore
//   "unavailable"  il n'y a rien a chauffer -- pas de pack, ou aucune voix pour ce contact
//   "unknown"      personne ne l'a demandee
//
// Quatre reponses et pas un booleen, parce que l'appelant en fait trois choses differentes :
// attendre, decrocher, et decrocher TOUT DE SUITE. Confondre les deux dernieres ferait sonner
// vingt secondes dans le vide une installation sans pack.
std::string VoiceState(const std::string& aContactId);

// Les echantillons d'une replique par la VOIX DE SECOURS, sans les jouer. Bloquant, et c'est
// la raison de sa presence ici : la suite hors jeu peut l'appeler sur une chaine fixe et
// verifier que des octets reviennent, sans son et sans session.
//
// La voie neuronale n'est pas assertable de cette facon, et ce n'est pas un oubli : un rendu de
// la bonne forme n'a jamais rien prouve sur une voix. Elle a son propre banc, hors du jeu,
// decrit dans tools\pocket-engine\README.md -- et son critere est une oreille.
//
// `aWhy` n'est rempli qu'en cas d'echec.
bool Render(const std::string& aUtf8Text, std::vector<uint8_t>& aSamples, std::string& aWhy);

// Le format que Render() ecrit -- celui de la voix de secours, pas celui de la voie neuronale,
// qui rend en 24 kHz. Le worker lit le format du moteur qui a effectivement rempli le tampon ;
// personne d'autre n'a de raison de le demander.
uint32_t SampleRate();
uint16_t Channels();
uint16_t BitsPerSample();

// Ce qui est arrive a la derniere replique remise, en mots -- pour la fenetre et le journal.
std::string LastResult();

// Ou le plugin est installe, d'ou se deduisent le pack de modeles et le dossier des voix.
// Pose une fois au chargement ; vide, la voie neuronale est simplement absente.
void SetPluginDirectory(const std::wstring& aPluginDirectory);

// Arrete le worker et rend le modele. Appele quand le plugin se decharge.
void Shutdown();
} // namespace ainpc::speech
