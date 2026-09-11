# Ouvrir un SMS ou un holo — plan d'implémentation

Décidé avec l'utilisateur le 2026-09-11, implémenté le même jour. Compilé et linté hors ligne
dans les trois formes, **jamais lancé**. Ce qui reste à mesurer en jeu est en bas.

## Le problème

Sur une ligne de contact, le mod ajoute T (chat) et G (appel) aux touches vanilla : trop
d'indices pour une ligne. Et ils montrent l'architecture du mod au joueur (une touche par
implémentation) au lieu de ses intentions (écrire, appeler).

Vanilla : F appelle, depuis la liste de contacts. R répond, une fois une conversation ouverte.

## La décision

**Le mod n'ajoute plus aucune touche sur la liste de contacts.** F reste seule, et le mod se
loge à l'intérieur de ce que le jeu ouvre.

| Verbe | Contact non géré par le mod | Contact géré |
|---|---|---|
| Écrire | vanilla | vanilla, et notre conversation est une entrée de la liste des conversations du contact |
| Appeler (F) | vanilla, sans chat | scène d'appel vanilla prévue → on la lance, + barre de chat ; sinon → notre holo |

## SMS : notre conversation est une conversation du contact

Le jeu range déjà les SMS d'un contact en plusieurs conversations (`ContactData.threadsCount`,
`MessengerDialogViewController.ShowThread`), une par moment de l'histoire. Notre conversation
devient l'une d'elles, épinglée en tête, comme une conversation de quête qui n'aurait pas de fin
écrite. L'ouvrir affiche le chat du mod tel qu'il existe aujourd'hui.

- L'historique vanilla se relit avec le geste vanilla, sans rien changer.
- Le texte écrit par le jeu et le texte improvisé par le modèle ne se mélangent jamais.
- Un personnage du mod sans aucun SMS du jeu ouvre directement le chat : une liste d'une seule
  conversation fait ouvrir la messagerie du jeu toute seule (`m_isSingleThread`).
- Les lignes de contact des personnages du mod sont rendues appelables et « avec messages »,
  pour que F et la touche des messages s'y offrent. Ce que le jeu sait vraiment d'un appel se
  relit dans le journal (`AiNpcVanillaCallable`), jamais sur la ligne.

Écarté : **le fil unifié** (historique vanilla en lecture seule au-dessus du fil IA). Faisable,
mais une réplique IA qui contredit le SMS de quête juste au-dessus se lit comme un bug du jeu,
et le découpage en conversations disparaît.

## Holo : la barre de chat entre dans le holo vanilla

### Aiguillage à l'appel

1. Contact non géré par le mod → appel vanilla, rien de plus.
2. Contact géré, appel vanilla possible (`ContactData.isCallable`) → appel vanilla, et la
   barre de chat s'y greffe.
3. Contact géré, pas d'appel vanilla possible → le mod passe l'appel lui-même
   (`AiNpcCallSystem.Dial`, déjà en place).

Conséquence acceptée : un appel vanilla sans aucun choix ne laisse jamais la parole au modèle.
C'est le prix de la cohérence, pas un défaut à corriger.

Écarté : **« la quête d'abord, sinon l'IA »** (router vers le vanilla seulement quand une quête
attend l'appel). Après les arcs, Panam, River, Judy restent appelables pour toujours, et l'un
des deux côtés perdait sa place.

### Tour de parole, réplique par réplique

Le conflit de voix est rendu impossible par construction. **On ne lit jamais l'audio vanilla.**

| Situation | Barre de chat (R) | Choix vanilla |
|---|---|---|
| La scène vanilla parle (entre deux choix) | cachée | — |
| Choix vanilla affiché, non minuté | disponible | disponibles |
| La ligne de saisie est ouverte | ouverte | **masqués et bloqués** ; rendus si le joueur abandonne sa ligne |
| Le joueur a envoyé un message au modèle | cachée | **masqués et bloqués** jusqu'à la fin de notre voix |
| Le joueur a pris un choix vanilla | cachée jusqu'au prochain choix affiché | — |
| Choix minuté (`timeProvider` défini sur le hub) | cachée | disponibles |

Mesuré en jeu le 2026-09-11 : Entrée dans la ligne de saisie validait la réplique du jeu.
`DialogConfirm` lie F **et** Entrée, et le moteur traite la validation lui-même : masquer la
liste ne l'arrête pas. Tant que la ligne tient le clavier, ou que les choix sont masqués, toutes
les actions de choix (`Choice1` à `Choice4`, `ChoiceApply`) sont **consommées** dans
`PlayerPuppet.OnAction` -- le patron de Night City Allies. Une lettre tapée les déclenche aussi.

Deux signaux seulement, et aucun ne lit l'audio vanilla :

- **la réplique vanilla est finie** : le choix suivant s'affiche ;
- **notre réplique est finie** : c'est notre file de parole qui le dit.

Le joueur peut enchaîner plusieurs échanges avec le modèle devant le même choix en attente,
puis prendre une réponse vanilla, et la scène reprend.

Le modèle reçoit la transcription de la scène en cours, sinon il répond sans savoir ce qui
vient d'être dit. Les sous-titres passent déjà par `UIGameData`
(voir `AiNpcCallSubtitle.reds`).

### Fin d'appel

- La scène vanilla raccroche → l'appel est terminé. Pas de reprise, pas de maintien : le PNJ a
  raccroché.
- Notre holo : **maintien de T** pour raccrocher, indice affiché seulement dans ce cas.

### Touches

| Geste | Action du jeu écoutée | Quand |
|---|---|---|
| R | `Choice2` | répondre au modèle, dans les deux holos (même sens que R vanilla : répondre) |
| maintien de T (0,5 s) | `PhoneReject` | raccrocher, seulement notre holo |

On écoute les **actions** nommées, jamais les touches brutes : un joueur qui a remappé son
clavier garde des gestes cohérents, et on n'intercepte pas des touches dont la navigation du
téléphone a besoin (mesuré : ça la casse).

F est abandonné : c'est `Choice1`, la touche de sélection par défaut du jeu.

Relevé dans `r6/config/inputUserMappings.xml` et `inputContexts.xml` : R est aussi `Reload`
hors dialogue (recharger en répondant est sans gravité). T en appui court est
`PhoneInteract` (ouvrir le téléphone), d'où le maintien.

## Ce qui change dans le code

| Fichier | Changement |
|---|---|
| `AiNpcSystem.reds` | le clavier n'est écouté que pendant le chat (`ListenKeys`) ; T, G, `OnContactListKey`, `PlaceCall` et `ReportContactRow` disparaissent ; `ReportMessagesAction` ouvre le chat depuis la touche des messages |
| `AiNpcPhoneState.reds` | la ligne mémorisée pour T et `IsOnContacts` disparaissent |
| `AiNpcPhoneWidgets.reds` | le badge `kb_t` et la marche des lignes de contact disparaissent |
| `AiNpcCallChoices.reds` | répondre passe de `Choice1` à `Choice2` ; raccrocher passe à `PhoneReject` |
| `AiNpcCallState.reds` | `AiNpcCallOrigin` (le nôtre / celui du jeu) et `AiNpcCallMayJoin` |
| `AiNpcCallSystem.reds` | rejoint et quitte un appel du jeu (`ReportPhoneCall`), porte le tour de parole (`ReportDialogHubs`), F (`ReportCallRequested`), le maintien de T (`ReportPhoneAction`) |
| `AiNpcCallVanilla.reds` | `AiNpcVanillaCallable` : le journal dit si le jeu a une scène d'appel |
| `AiNpcHooks.reds` | `CallContact`, `ExecuteAction`, `OnContactSelectionChanged`, `OnPhoneCall`, `GetContactDataArray`, `GetMessageDataArrayForContact`, `dialogWidgetGameController.UpdateDialogsData` |
| **nouveau** `AiNpcCallRoute.reds` | qui passe l'appel sur F, pur |
| **nouveau** `AiNpcHoloTurn.reds` | le tour de parole, pur |
| **nouveau** `AiNpcDialogHub.reds` | lire le hub de dialogue, savoir s'il est minuté, le faire relire |
| **nouveau** `AiNpcMessengerThread.reds` | greffer notre conversation, rendre les lignes des personnages appelables |
| **nouveau** `AiNpcHoloReplyHint.reds` | « R Répondre » au-dessus de la ligne de saisie d'un holo du jeu |
| `tests/` | `AiNpcTestCallRoute.reds`, `AiNpcTestHoloTurn.reds`, libellés |

Pas de système dédié à l'observation du holo vanilla : c'est un appel comme un autre, porté par
`AiNpcCallSystem` avec une origine différente.

Les choix du jeu sont masqués **à l'affichage**, dans `UpdateDialogsData` : le tableau noir
`DialogChoiceHubs` n'est jamais réécrit. La scène garde ses données, et les rendre revient à
reposer la même valeur pour que l'affichage la relise.

La notification SMS ouverte par T (`AiNpcNotificationAction.reds`) n'est pas concernée : autre écran,
et c'est le geste vanilla.

## Relevé hors ligne (vanilla décompilé, `C:\tmp\redscript\vanilla`)

- F sur la liste de contacts : `NewHudPhoneGameController.CallContact`, qui refuse une ligne
  dont `isCallable` est faux.
- La liste des conversations d'un contact : `MessengerUtils.GetMessageDataArrayForContact`,
  appelée par `ShowSelectedContactMessages` seule.
- La liste de contacts : `JournalManager.GetContactDataArray`, via
  `MessengerUtils.GetCallableAndNonEmptyContacts`.
- Début et fin d'un holo : `NewHudPhoneGameController.OnPhoneCall`, qui porte
  `PhoneCallInformation` (`contactName`, `callPhase`).
- Choix minuté : `timeProvider` défini sur le hub ou sur un choix (`dialogUI.script`).

## À mesurer au premier lancement

Rien de ceci n'a tourné. Dans l'ordre où un défaut se verrait :

1. **F sur un personnage du mod que le jeu ne sait pas appeler** : notre holo sonne. Log :
   `F on '<id>': Dialing <id>...`.
2. **F sur un personnage que le jeu sait appeler** : l'appel du jeu part, puis
   `Call: idle -> connected ('<id>')` quand il décroche. Si cette ligne manque, `contactName`
   ne porte pas l'id du contact.
3. **Au premier choix de la scène** : `Holo turn: Scene -> Choice`, et « R Répondre » au-dessus
   de la ligne de saisie.
4. **R, une ligne, Entrée** : `Holo turn: Choice -> Model`, les choix disparaissent ; ils
   reviennent avec `Model -> Choice` quand la voix se tait. À vérifier : que la scène n'avance
   pas pendant que ses choix sont masqués, et que F ne choisit rien pendant ce temps.
5. **R dans un hub de dialogue** : ne déclenche-t-il pas aussi un `Choice2` du jeu.
6. **Maintien de T sur notre holo** : raccroche, et l'invite « Raccrocher » montre bien T.
7. **La touche des messages** sur un personnage du mod : sa liste montre notre conversation en
   tête, avec l'aperçu de sa dernière ligne ; sans SMS du jeu, le chat s'ouvre directement.

8. **Les relances du PNJ** (« T'es encore là ? ») pendant qu'un choix attend : mesurées
   seulement, rien n'est bloqué. Chaque réplique du jeu pendant un appel du jeu est journalisée :
   `Holo line during <tour> (over our turn): <nom>: '<texte>' [<type>, <durée>s]`. La mention
   `(over our turn)` marque celles qui tombent pendant que le joueur écrit ou que le modèle
   répond. Chacune est aussi **classée dans la transcription de l'appel** comme une réplique
   ordinaire (`filed`) : le modèle ne sait pas qu'elle vient de la scène, et elle reste dans
   la mémoire du personnage. Une réplique déjà présente dans l'historique du contact n'est pas
   reclassée (`not filed`), pour qu'un appel répété ou une réponse choisie deux fois ne crée pas
   de doublon. Mesuré le 2026-09-11 (holo avec Rogue) : une écoute du tableau noir
   `UIGameData.ShowDialogLine` n'a rien reçu. Les répliques de scène arrivent aux contrôleurs par
   le gestionnaire natif de sous-titres ; la détection est maintenant un hook sur
   `BaseSubtitlesGameController.ShowDialogLines`, où les deux chemins se rejoignent, limité au
   contrôleur principal (`SubtitlesGameController`).

   Relevé hors ligne pour la suite : le système de scène n'expose aux scripts ni pause ni saut
   de réplique. Le seul levier de blocage trouvé est le volume des dialogues du joueur, un
   réglage sauvegardé -- écarté, parce qu'un plantage en pleine réponse le laisserait à zéro.

Limite connue : « la voix s'est tue » se lit sur `AiNpcAudio.Speaking()`. Si la dernière phrase
est encore en synthèse quand la requête se termine, les choix peuvent revenir un instant avant
qu'elle ne sonne. Le signal exact demanderait à la DLL un état « en attente de synthèse ».
