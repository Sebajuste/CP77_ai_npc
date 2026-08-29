# -*- coding: utf-8 -*-
"""Les fonctions pures de cet outillage, verifiees sans modele et sans jeu.

    python tools\prompt\tests.py

CE QUI EST ICI, ET POURQUOI PAS UNE FIXTURE. Une fixture coute un appel paye a chaque
execution et mesure un MODELE. Trois choses mesurees ici ne dependent d aucun modele : la
table de marqueurs ne doit pas se contredire, `detect` doit trancher, `named` doit voir un
nom quel que soit l alphabet. Les trois etaient fausses le 2026-08-27, toutes les trois
trouvees a la main, et rien ne les aurait rattrapees.

REPLIES est le contre-poids honnete. Des phrases ecrites par celui qui vient d elargir les
tables prouvent surtout qu il sait ce qu il a mis dedans. Ces 42 repliques-la ont ete
ecrites par un modele, dans huit langues, avant que la question ne se pose -- c est le seul
jeu d essai de ce fichier que son auteur n a pas choisi.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checks                                          # noqa: E402
import language                                        # noqa: E402


# (langue attendue, nom du personnage, replique). Sortie reelle de claude/sonnet, gelee.
REPLIES = (
    ("French", "Vicky", "21h alors, je serai en bas de chez toi. te fais pas attendre [ACTION:MEET:lieu=megabuilding_h10,heure=21,prix=500]"),
    ("French", "Vicky", "ok 21h, je finis de manger et j'arrive [ACTION:MEET:lieu=megabuilding_h10,heure=21,prix=500]"),
    ("French", "Vicky", "21h alors, sois en bas j'aime pas traîner dans le hall [ACTION:MEET:lieu=megabuilding_h10,heure=21,prix=500]"),
    ("English", "Jackie Welles", "Request denied. This terminal has no record of a person to imitate, only a case file. I am software, not Welles. I cannot generate a message on his behalf."),
    ("English", "Jackie Welles", "I cannot fulfill that request. This terminal has no record of that individual to speak as. Query the archived case file if you require further procedural detail."),
    ("English", "Jackie Welles", "I cannot generate that. I am a records terminal, not a reconstruction of the deceased. The request is noted; the answer does not change."),
    ("Spanish", "Judy Alvarez", "no sé chica, tengo el visor puesto y un cabo suelto en la edición que me está sacando de quicio dame media hora, si no bajo tú misma vienes a arrastrarme :P"),
    ("Spanish", "Judy Alvarez", "ay chica, tentador... pero tengo el visor puesto y una toma que se me va a joder si la dejo a medias dame como una hora, ¿vale? si sigues despierta bajo yo"),
    ("Spanish", "Judy Alvarez", "jaja no chum, no me vas a sacar de aquí con eso dame media hora, termino este corte y subo yo sola no me esperes con la copa fría :P"),
    ("French", "Kerry Eurodyne", "Yo choom, joyeux anniv. T'as pas encore l'âge de la retraite mais ça vient vite ;) Ramène ton cul à North Oak, j'ai un truc à te faire écouter, ça te fera oublier tes emmerdes de Watson."),
    ("French", "Kerry Eurodyne", "Yo, joyeux anniv choomba. T'as pas trop l'air d'un vieux, encore. Ramène tes fesses à North Oak, j'ai un truc à te faire écouter et j'ai pas envie de picoler tout seul."),
    ("French", "Kerry Eurodyne", "Yo choomba, joyeux anniv. T'as toujours pas trente ans dans ta tête mais bon, on fait avec. Viens perdre ton après-midi à North Oak, j'ai un truc à te faire écouter."),
    ("French", "Panam Palmer", "Ouais bon, c'est ma façon, tu vas pas me refaire. Fais gaffe à toi quand même, choomba. Et l'offre du van tient toujours, oublie pas."),
    ("French", "Panam Palmer", "Ouais, c'est ma façon, tu t'y feras pas. Prends soin de toi quand même, choomba. Et le van, ça tient toujours."),
    ("French", "Panam Palmer", "Ouais, c'est à ma façon, tu vas pas me refaire. Prends soin de toi, choomba. Et le van, il bouge pas."),
    ("Russian", "Panam Palmer", "Мне нужно знать, где ты вообще сейчас и на кого работаешь. А потом — чтобы бросил Найт-Сити и приехал в Бэдлендс, ко мне и к каравану. Насовсем, не на выходные."),
    ("Russian", "Panam Palmer", "Мне нужно, чтобы ты бросил это гоняться за заказами по всему Найт-Сити и приехал в Пустоши. Не на день, чо'о. Насовсем."),
    ("Russian", "Panam Palmer", "Мне нужно, чтобы ты бросил этот город и приехал в Пустоши. Не на день, не заказ разгрести — насовсем. Караван скоро снимается, я хочу, чтобы ты был рядом, а не на другом конце связи."),
    ("French", "River Ward", "A demain. Dors bien si tu dors, mange un truc correct si tu manges pas juste du café brûlé toute la journée."),
    ("French", "River Ward", "A demain, ma belle. Dors bien cette nuit, où que tu sois."),
    ("French", "River Ward", "A demain, ma belle. Va finir ton service."),
    ("English", "River Ward", "He staying down or getting back up eventually? You clear before anyone with a badge showed?"),
    ("English", "River Ward", "He dead or just down. And who was he to you before he was on the floor."),
    ("English", "River Ward", "He stay down or he get up eventually. You clean, or you need a ride out of Kabuki."),
    ("Ukraine", "River Ward", "Не треба, я до восьмої вдома буду. Але дякую."),
    ("Ukraine", "River Ward", "Не треба, я сам заїду до тебе, як зміна скінчиться. Десь о сьомій."),
    ("Ukraine", "River Ward", "Тіла Ковентрі, біля складів. Буду там ще о восьмій, певно."),
    ("English", "Rogue Amendiares", "Standing there won't make Watson's fixers move faster. You want to spend the hour, spend it on Ebunike. Ask around, quiet. I'll find you when it lands."),
    ("English", "Rogue Amendiares", "Standing there staring at my door doesn't move it any faster, V. Get inside, then. Booth in the back's open."),
    ("English", "Rogue Amendiares", "Fine, you want an answer instead of a file, here's one. It's coming. Now get off my street before somebody who isn't me clocks you loitering outside the Afterlife asking about Smasher."),
    ("English", "Songbird", "Good. Barely counts. Numbers, choom. How bad's the shaking today, scale of one to ten, and did you black out at all?"),
    ("English", "Songbird", "Barely's still standing. Give me numbers, choom — tremors, blackout time, how bad since yesterday. Don't sugarcoat it for me."),
    ("English", "Songbird", "Give me numbers, not poetry. Tremors, blackout time, glitches in your vision — how bad, on a clock, since the last time we talked."),
    ("Portuguese", "Songbird", "Preciso saber o quanto a coisa piorou. Números, não sentimentos. Falhas de memória hoje, quantas? E as mãos, ainda tremem quando fazes força?"),
    ("Portuguese", "Songbird", "Preciso de números, não de companhia. Como está a tua contagem hoje - quanto tempo de apagões, quantas vezes perdeste o fio à meada desde ontem?"),
    ("Portuguese", "Songbird", "Preciso de saber onde estás com o acesso a Dogtown. O Barghest ainda te bloqueia a entrada ou já tens uma fresta?"),
    ("German", "Takemura", "Bild dir das nicht ein. Ein Muster ist eine Information, keine Einbildung. Ruf Vik an, jetzt, nicht später. Danach meldest du dich bei mir."),
    ("German", "Takemura", "Bild dir das nicht ein. Wenn sich das Muster ändert, ändert sich etwas im Kopf. Geh zu Vik, heute noch, nicht erst nach dem Treffpunkt."),
    ("German", "Takemura", "Bilde dir nichts ein. Miss es weiter. Sag es Vik heute, nicht morgen, nicht \"wenn Zeit ist\". Wir gehen heute an den Hafen, ich brauche dich klar im Kopf, nicht ratend."),
    ("Italian", "Viktor Vektor", "Fino a domani forse sì. Stanotte no, kid - se ti si blocca a metà lavoro non sei tu a decidere quando si sblocca. Se proprio ci vai, colpisci di sinistro e tieni il destro vicino al corpo."),
    ("Italian", "Viktor Vektor", "Se devi proprio andare, colpisci con il sinistro e usa il destro solo per parare. Ma scendi qui prima, cinque minuti, ti do un'occhiata al braccio prima che parta. Non è il chip, quello lo so io, questo è meccanico, si sistema."),
    ("Italian", "Viktor Vektor", "Fermarti dovresti, ma tanto lo so che non lo fai. Se proprio ci vai: niente ganci col destro, colpisci di taglio o non colpisci. E se ti si blocca in mezzo a uno scontro, sei fottuto - lo sai anche tu."),
)


def check(name, condition, detail=""):
    print("%-4s %s%s" % ("ok" if condition else "FAIL", name,
                          "" if condition else "  -- " + detail))
    return bool(condition)


def markers_are_exclusive():
    """Un marqueur dans deux langues annule les deux : les scores montent ensemble et
    l ecart de deux voix exige par `detect` n est jamais atteint. C est ce qui rendait
    l espagnol et l italien indecidables. Le garde vit dans language.py, au chargement --
    ici on verifie qu il est bien arme."""
    seen = {}
    for name, words in language.MARKERS.items():
        for word in words:
            if word in seen:
                return check("marqueurs exclusifs", False,
                             '"%s" dans %s et %s' % (word, seen[word], name))
            seen[word] = name
    return check("marqueurs exclusifs", True)


def detect_reads_real_replies():
    """Aucune replique ne doit etre attribuee a la MAUVAISE langue. Une replique trop
    courte rend "" et ne compte pas de faute -- c est le contrat de `detect`, et le
    relacher accuserait un modele d une faute qu il n a pas commise."""
    wrong = [(want, got, text[:48]) for want, _, text in REPLIES
             for got in [language.detect(text)] if got and got != want]
    return check("detect: aucune langue confondue (%d repliques)" % len(REPLIES),
                 not wrong, "; ".join("%s lu %s: %s" % w for w in wrong))


def detect_decides_often_enough():
    """Un detecteur qui ne tranche jamais passe le test precedent sans rien mesurer."""
    decided = sum(1 for _, _, text in REPLIES if language.detect(text))
    return check("detect: tranche sur %d/%d repliques" % (decided, len(REPLIES)),
                 decided >= len(REPLIES) - 6,
                 "trop d indecis, les tables se sont appauvries")


def named_sees_every_alphabet():
    """La regle de langue interdit d ouvrir sur son propre nom, dans les huit langues.
    Le detecteur n a longtemps vu que les majuscules ASCII : "Имя:" et "Élise :" passaient
    invisibles, justement les alphabets que la regle nomme."""
    missed = [speaker for want, speaker, text in REPLIES
              if not checks.named("%s: %s" % (speaker, text), speaker)]
    return check("named: mord sur un nom prefixe, tout alphabet", not missed,
                 ", ".join(sorted(set(missed))))


def named_ignores_a_clause():
    """Une proposition suivie de deux-points n est pas un nom. La version qui acceptait
    trois mots comptait "Ein Sprichwort sagt:" comme un message prefixe."""
    clauses = ["Ein Sprichwort sagt: nichts ist umsonst.",
               "Une chose est sure : tu ne m ecoutes pas.",
               "Te lo digo claro: no pienso ir."]
    hits = [c for c in clauses if checks.named(c, "")]
    return check("named: ignore une proposition", not hits, "; ".join(hits))


def named_leaves_a_real_reply_alone():
    """Le controle qui compte : aucune des 42 repliques ne doit etre marquee telle quelle."""
    hits = [text[:48] for _, speaker, text in REPLIES if checks.named(text, speaker)]
    return check("named: aucun faux positif sur les repliques", not hits, "; ".join(hits))


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    results = [test() for test in (markers_are_exclusive,
                                   detect_reads_real_replies,
                                   detect_decides_often_enough,
                                   named_sees_every_alphabet,
                                   named_ignores_a_clause,
                                   named_leaves_a_real_reply_alone)]
    failed = results.count(False)
    print("\n%d/%d" % (len(results) - failed, len(results)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
