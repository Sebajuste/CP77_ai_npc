# NOTICE — AI NPC

Ce fichier complète `LICENSE`. La licence MIT couvre **le code écrit pour ce mod** ;
elle ne peut rien dire de ce qui appartient à d'autres. C'est l'objet de ce document.

## 1. Code original

Tout le code source de ce dépôt écrit par Sebajuste — redscript, Lua, C++, PowerShell,
Python d'outillage — est distribué sous licence MIT (voir `LICENSE`).
Copyright (c) 2026 Sebajuste.

## 2. Propriété de CD PROJEKT RED

*Cyberpunk 2077*, son moteur, ses assets, ses noms, personnages, marques et logos sont
la propriété de **CD PROJEKT S.A.** Ce mod n'est ni affilié à, ni approuvé, ni
sponsorisé par CD PROJEKT RED.

Les identifiants du jeu que ce mod manipule — noms de classes, de méthodes, de champs,
`TweakDBID`, chemins de dépôt — sont cités à seule fin d'interopérabilité. Ils ne sont
pas couverts par la licence MIT ci-dessus et ne sont pas concédés par Sebajuste.

Les ressources livrées dans le `.archive` de ce mod sont créées pour lui. Dans la mesure
où l'une d'elles dérive d'un asset original de *Cyberpunk 2077*, elle reste la propriété
de CD PROJEKT S.A. et n'est couverte ni par la licence MIT, ni par aucune concession de
Sebajuste : utilisable dans *Cyberpunk 2077* seulement, dans les conditions de la section 3.

## 3. Conditions d'utilisation imposées par CD PROJEKT RED

L'usage et la redistribution de ce mod sont soumis, **en plus** de la licence MIT, au
*CD PROJEKT RED User Agreement* accepté avec les outils de modding (REDmod), et aux
*Fan Content Guidelines* de CD PROJEKT RED. En particulier :

- distribution **gratuite et non commerciale** uniquement — pas de vente, pas d'accès
  payant, pas de contenu réservé à des contributeurs ;
- pas de distribution de fichiers du jeu destinés à un usage **hors** du jeu ;
- les termes en vigueur sont ceux publiés par CD PROJEKT RED, qui priment sur cette
  paraphrase.

La licence MIT autorise l'usage commercial ; ce n'est pas une contradiction. MIT
s'applique au code de Sebajuste, l'accord CDPR s'applique par-dessus à toute
utilisation dans le contexte du jeu. **Résultat net pour un tiers : non commercial.**

## 4. Dépendances tierces

Ces composants ne sont **pas inclus** dans le livrable : le joueur les installe
séparément. Ils restent soumis à leurs licences et copyrights respectifs.

| Composant | Rôle / licence |
|---|---|
| redscript | Compile les `.reds` du mod au lancement — jac3km4, licence MIT. |
| RED4ext | Chargeur de plugins natifs — WopsS, licence MIT. |
| Codeware | Types redscript additionnels (`ScriptableService`, callbacks) — psiberx, licence MIT. |
| Cyber Engine Tweaks | Runtime Lua et overlay in-game — yamashi et contributeurs, licence MIT. |
| Mod Settings | Page d'options partagée — licence propre à ce mod. |

## 5. Réutilisation

Fork, modification, traduction et mods dépendants sont les bienvenus, dans les termes
de la licence MIT (conserver le copyright et l'avis de licence) et de la section 3.
Les champs *Permissions* de la page Nexus font foi pour ce qui y est publié : la
licence de ce dépôt n'y est pas lue automatiquement.
