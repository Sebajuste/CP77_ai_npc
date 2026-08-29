# Les faits d'issue des arcs — relevé du 2026-08-24

Ce que le jeu de base écrit quand l'histoire d'un personnage **se décide**, et pourquoi il n'y
a pas de règle générique à en tirer.

Tout ce qui suit est **relevé dans les fichiers de quête**, pas deviné : archives extraites par
hash FNV1a64 depuis `basegame_4_gamedata.archive`, graphes lus avec le mode `qgraph` du harnais
`NA_PerspectiveFix/tools/wkdump`. Chaque nom vient d'un nœud `questFactsDBManagerNodeDefinition`
ou d'une condition `questVarComparison_ConditionType`.

## Pourquoi ce document existe

`ai_npc` ne connaît aujourd'hui qu'un booléen par personnage : le fait `*_lover` est posé, ou
il ne l'est pas. Donc **« V ne l'a jamais tenté » et « V a dit non » produisent le même
prompt** — la ligne générique *« You and V are not together. An advance from V is not taken
up… »*. Correct pour le premier cas, faux pour le second.

Il y a trois états : **pas commencé / ensemble / échoué**. Et le relevé ci-dessous montre que
le troisième ne se lit pas de la même façon pour deux personnages.

## Ce qui est vérifié

| Personnage | Ensemble | La décision, et son nom réel |
|---|---|---|
| **Judy** | `sq030_judy_lover` | **`sq030_failed`** — un fait d'échec explicite. Aussi `judy_left_nc` : elle quitte Night City |
| **Kerry** | `sq028_kerry_relationship` | **`sq028_kerry_goes_home_alone`** — il rentre seul. Le pendant est `sq028_kerry_got_home`. Fin d'arc : `sq028_done` |
| **River** | `sq029_river_lover` | pas de fait d'échec propre : fin d'arc `sq029_done` posé par `sq029_conclusion`, et l'absence du fait `lover` est la seule différence |
| **Panam** | `sq027_panam_lover` | **introuvable** — voir plus bas |

### River, et pourquoi il casse toute règle générique

Sa romance n'est pas la seule chose qui peut mal finir, et l'autre chose ne dépend pas d'elle.
**La Chasse est la quête `sq021`**, et `sq029` relit ses faits à l'entrée :

| Fait | Sens |
|---|---|
| `sq021_randy_saved` | Randy est vivant |
| `sq021_good_farm_chosen` / `sq021_bad_farm_chosen` | la ferme choisie à la fin de l'analyse braindance |
| `sq021_river_dead` | **River lui-même peut mourir dans sq021** |
| `sq021_done` | la quête est finie, quoi qu'il en soit |

Rater `sq021` tue le neveu. Ça ferme la romance — et ça change la relation **même avec un V
masculin, qui n'avait aucune romance à rater**. Ce n'est donc pas un état de romance : c'est
l'issue de l'arc du personnage, et elle vaut pour tout le monde.

### Panam : non localisée

Aucun `base\quest\side_quests\sq027\...` dans l'index (550 938 entrées balayées, `sq024`,
`sq025`, `sq026`, `sq028`, `sq029`, `sq030`, `sq031`, `sq032` répondent tous, `sq027` non).
`q104` est bien son arc — Ghost Town, l'AV, le motel — mais il ne pose que `panam_default_on`.
Ses quêtes suivantes n'ont pas été trouvées aux chemins essayés.

Piste, tirée du même relevé : **`sq029_river_lover` n'est posé par aucune questphase non plus**
— `sq029.questphase` ne fait que le *lire*, en condition. Les faits de romance sont donc
vraisemblablement écrits par les **scènes** (`.scene`, le choix de dialogue), pas par les
graphes de quête. Chercher côté `scenes\` pour Panam.

## Ce qui en a été fait — 2026-08-25

Les trois vérifiés sont câblés, par **deux conditions de variante** ajoutées au vocabulaire
fermé (`AiNpcVariantConditions`), donc utilisables aussi bien par une fiche de `cast\` que par
un `characters.<mod>.json` :

| Condition | Ce qu'elle lit | Qui l'utilise |
|---|---|---|
| `romanceFailed` | par personnage, dans `AiNpcRomanceFailedFor` | Judy, Kerry, River |
| `randyDead` | `sq021_done` sans `sq021_randy_saved` | River |

La règle par personnage vit dans `AiNpcStoryState.reds`, un seul `switch`, parce que les trois
formes sont différentes. Les fiches ne portent que du texte. Panam répond **false** tant que
son fait n'est pas localisé : un nom de fait faux est silencieux, et il rendrait froide une
Panam que le joueur n'a jamais refusée.

River porte les deux, et `randyDead` est écrit en premier : la première variante qui fournit
un champ gagne, et dans une partie où le neveu est mort *et* la romance refusée, c'est le
deuil qui parle.

## Ce que ce relevé dit du code à écrire

Trois personnages, trois formes différentes : un fait d'échec nommé (`sq030_failed`), un fait
qui décrit un geste (`sq028_kerry_goes_home_alone`), et une issue qui vient **d'une autre
quête** et vaut hors romance (`sq021_randy_saved`).

Une paire de noms de faits par fiche ne les exprime pas. Et un mini-langage de prédicats en
JSON violerait la règle du dossier — les données portent le texte, jamais le prédicat.

La forme qui reste, et c'est celle que le mod utilise déjà pour la romance : **une extension
par personnage qui en a besoin**, enregistrée par `ai_npc` sur son propre contact via
`RegisterExtension`, lisant ses faits à elle et contribuant son texte à elle. Du code au cas
par cas, parce que les cas sont différents. `AiNpcRomanceExtension` est le patron.

## Deuxième relevé — 2026-08-26, l'arc de Judy

Même méthode, même harnais : `sq026.quest` et `sq030.quest` sortis de `basegame_4_gamedata`
par hash, puis les phases sous `phases\`, lues avec le mode `qgraph`. Le premier relevé
cherchait **comment une romance se décide** ; celui-ci cherche **ce que le personnage a
vécu**, ce qui n'est pas la même question et ne se lit pas dans les mêmes nœuds.

### Ce qui est câblé

| Condition | Fait | Ce qu'elle dit |
|---|---|---|
| `evelynDead` | `sq026_01_done` | *Both Sides, Now* est close : Evelyn est morte et enterrée |
| `cloudsSettled` | `sq026_done` | l'arc de Clouds est fini, quelle qu'en soit l'issue |
| `leftNightCity` | `judy_left_nc` | par personnage, comme `romanceFailed`. Posé sur trois branches de `sq030`, chacune faisant disparaître Judy et sa camionnette |

Les trois sont **offertes à toutes les fiches**, comme `randyDead` : la mort d'Evelyn n'est
pas un état de romance et ne concerne pas qu'un contact.

### Pourquoi un scan de chaînes ne suffit pas — la démonstration

Le fichier `sq026_end.questphase` contient la chaîne `judy_pissed`, exactement là où on
attend le fait qui dit que V a pris le pot-de-vin. **`judy_pissed` est un nom de socket**,
pas un fait : c'est une sortie du nœud de scène `sq026_15_end`, et le graphe porte l'issue
sur le fil, pas dans la base de faits. Un scan `grep` l'aurait câblé, et la condition serait
restée fausse pour toujours, en silence.

C'est la raison pour laquelle ce document exige le parseur CR2W et pas une recherche de
texte : seul un `questFactsDBManagerNodeDefinition` prouve qu'un nom est un fait.

### Trouvé et volontairement NON câblé

`sq026_refused`, posé quand le fil de Clouds est abandonné, en même temps que
`sq026_active = 0`. Le nom est réel, le nœud est réel. Ce qui n'est pas établi, c'est s'il
veut dire « V a dit non à Judy » ou « la quête a été abandonnée ».

La distinction n'est pas académique, et elle inverse le risque habituel : **un nom de fait
faux est silencieux et inoffensif** — il répond toujours faux. **Un fait dont le sens est
faux ne l'est pas** : il mettrait dans l'état « refusée » une Judy que personne n'a
refusée, et précisément dans les parties que personne ne regarde.

### Une conséquence sur le prompt, découverte en câblant

Judy est la **première fiche livrée à utiliser `liveContext`**. Ce champ atterrit dans
`<now>`, où chaque contributeur termine sa propre ligne — l'horloge le fait, chaque
fragment d'extension le fait. `provider.GetLiveContext()` ne le faisait pas, parce qu'il
rend le champ brut. La ligne collait donc à la suivante.

Corrigé **à l'émetteur** (`AiNpcBuildSystemPrompt`) et non dans le texte : autrement, chaque
fiche et chaque `characters.<mod>.json` devrait penser au saut de ligne final, et celle qui
l'oublie repart dans le même bug.

## Troisième relevé — 2026-08-27, la nuit où Johnny porte le corps de V

Même méthode, même harnais : `sq031.quest` sorti de `basegame_4_gamedata` par hash FNV1a64
(56 574 entrées dans l'index), puis les neuf phases sous `phases\`, lues en mode `qgraph`.

Les deux premiers relevés cherchaient comment une romance se décide, puis ce qu'un personnage
a vécu. Celui-ci cherche autre chose : **ce que quelqu'un d'autre que V a appris.** Jusqu'ici
aucune fiche ne pouvait l'exprimer, et Rogue affirmait connaître l'engramme dans la tête de V
dès le premier message d'une partie neuve, par un canal qui n'existe pas.

### Ce que pose sq031

| Fait | Posé où | Sens |
|---|---|---|
| `sq031_active` | phase racine | *Chippin' In* court |
| **`sq031_afterlife_sequence_done`** | phase `afterlife`, dernier nœud | Johnny, dans le corps de V, a fini de parler à Rogue au bar |
| `sq031_cool_metal_fire_done` | phase `striptease` | *A Cool Metal Fire* est close |
| `sq031_ruby_dead` | phase `grave` | — |
| **`sq031_rogue_date_done`** | phase `bushidox` | le drive-in a eu lieu |
| `sq031_done` | phase `bushidox` | l'arc entier est clos |

### Pourquoi `sq031_afterlife_sequence_done` est sûr

Trois raisons, et la troisième est celle qui décide :

- c'est un `questFactsDBManagerNodeDefinition`, donc un fait prouvé et pas un nom de socket ;
- il est posé sur le **dernier nœud** de sa phase, après la scène
  `sq031_01a_smack_afterlife.scene` ;
- **la phase `afterlife` est la première d'un chaînage strictement linéaire** — `afterlife`,
  `tattoo`, `striptease`, `motel`, `rogue`, `ebunike`. Le passage au bar n'est pas un arrêt
  facultatif de cette nuit : aucun chemin ne le saute.

Dans la branche où V refuse de laisser Johnny prendre le volant, la quête ne tourne pas, le
fait reste à 0, et personne d'autre que V ne sait. C'est le comportement voulu.

### Le piège de ce relevé

`rogue_default_on` apparaît dans quatre phases et se lit comme « Rogue est présente ». C'est le
**toggle de spawn** de son PNJ, mis à 0 puis à 1 dans la même phase. Même classe que
`judy_pissed` au relevé précédent : un `grep` l'aurait câblé, et la condition aurait vacillé au
gré des déplacements du personnage.

### Posés ailleurs, donc non câblés

`sq031_grayson_killed`, `sq031_ebunike_rogue_left`, `sq031_grayson_encounter_on` sont lus en
condition par les graphes et posés par **aucun** d'entre eux — donc par les scènes, comme les
faits de romance du premier relevé. Ils demandent une passe en mode `scene` avant d'être crus.

### Ce qui en a été fait — 2026-08-27

| Condition | Fait | Qui l'utilise |
|---|---|---|
| `johnnyRevealed` | `sq031_afterlife_sequence_done` | Rogue |
| `johnnyDateDone` | `sq031_rogue_date_done` | Rogue |

Les deux sont des faits de monde, offertes à toutes les fiches comme `randyDead` : Johnny se
montrant à quelqu'un qui l'a connu n'est pas la propriété d'un contact.

### La limite découverte en câblant

**Les `seedFacts` ne se varient pas.** `AiNpcVariantFields()` couvre `bio`, `relationship`,
`liveContext`, `speechStyle` et `intent`, et rien d'autre. Un fait d'amorce nommant l'engramme
passait donc sous toutes les gardes ci-dessus et disait à Rogue ce qu'elle ne sait pas encore.
Il a été supprimé plutôt que conditionné, et un test le vérifie.

