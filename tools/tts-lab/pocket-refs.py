# -*- coding: utf-8 -*-
"""Passe les extraits de `voice-extract` dans PocketTTS, un rendu par personnage.

    python tools\\tts-lab\\pocket-refs.py                    # la replique "argot"
    python tools\\tts-lab\\pocket-refs.py --line longue      # une autre de lines.json
    python tools\\tts-lab\\pocket-refs.py judy panam         # deux personnages

Le pendant de `clone-refs.py`, pour l'autre moteur. Meme entree, meme mesure, meme sortie :
`out\\pocket-<personnage>-<replique>.wav`, a cote des `clone-*` de Zonos. C'est ce qui rend
l'A/B possible -- et c'est la seule question qui compte, parce qu'un rendu de la bonne forme
ne prouve rien sur la voix.

CE QUE CE BANC MESURE ET QUE ZONOS NE PERMETTAIT PAS. L'etat de voix se calcule ici
explicitement (`get_state_for_audio_prompt`) et se garde : le cout du clonage est donc separe
du cout de la parole, ce qui est exactement la question posee au mod -- « cloner une fois par
PNJ » coute-t-il quelque chose a chaque replique. Zonos cachait cet etat dans son serveur, et
par NOM DE FICHIER, ce qui a fausse trois mesures avant d'etre trouve.

INSTALLATION -- elle est de l'utilisateur, pas de l'agent : le modele francais pese 672 Mo.

    pip install pocket-tts
    python tools\\tts-lab\\pocket-refs.py --language french_24l

PocketTTS demande Python 3.10 a 3.14 et PyTorch 2.5+ ; cette machine a deja 3.10.6 et
torch 2.5.1, donc `pip install pocket-tts` n'ajoute que le paquet. Le depot Hugging Face est
sous acceptation : il faut un compte et avoir accepte les conditions avant le premier
telechargement.
"""
import argparse
import os
import sys
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import voice_bench  # noqa: E402

# Deux depots, et un seul est ferme : `kyutai/pocket-tts-without-voice-cloning` est libre,
# `kyutai/pocket-tts` est **sur liste d'autorisation**. Mesure du 2026-09-01 : un compte
# authentifie et a jour recoit quand meme un 403 GatedRepoError tant que Kyutai ne l'a pas
# ajoute. Ce n'est donc pas une case a cocher, c'est une demande a faire approuver.
#
# ET LE PAQUET AVALE L'ERREUR : `load_model` tente les poids avec clonage, attrape n'importe
# quelle exception, et charge silencieusement ceux sans. On obtient un modele qui parle
# parfaitement et qui refuse de cloner, sans qu'aucun message ne dise pourquoi.
CLONING_GATED = """le clonage demande un acces au depot ferme kyutai/pocket-tts.

  1. demander l'acces sur https://huggingface.co/kyutai/pocket-tts -- et attendre l'approbation
  2. hf auth login

Etre authentifie ne suffit pas : le compte doit etre sur la liste des autorises.
En attendant, --catalogue rend les voix pretes du modele, qui ne clonent pas.

(%s)"""


def write_wav(path, rate, audio):
    """Ecrit en PCM 16 bits, sans scipy.

    Deux raisons plutot qu'une : c'est une dependance de moins a faire installer, et le banc
    ne relit pas le WAV flottant que scipy ecrirait. Un rendu que la mesure ne sait pas lire
    ne se mesure pas.
    """
    values = audio.detach().cpu().numpy() if hasattr(audio, "detach") else audio
    values = values.reshape(-1)
    frames = bytearray()
    for v in values:
        sample = int(round(float(v) * 32767.0))
        frames += max(-32768, min(32767, sample)).to_bytes(2, "little", signed=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(int(rate))
        handle.writeframes(bytes(frames))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("characters", nargs="*")
    parser.add_argument("--line", default="argot")
    parser.add_argument("--language", default="french_24l",
                        help="le modele de langue ; french_24l est la variante lente et bonne")
    parser.add_argument("--voices", default=voice_bench.VOICES)
    parser.add_argument("--tag", default="")
    parser.add_argument("--threads", type=int, default=4,
                        help="fils de calcul ; torch en prend UN par defaut, ce qui divise "
                             "le debit par 1,5 et double le delai avant le premier son")
    parser.add_argument("--catalogue", action="store_true",
                        help="les voix pretes du modele au lieu de nos references ; "
                             "ne demande aucun compte Hugging Face")
    args = parser.parse_args()

    try:
        import torch
        from pocket_tts import TTSModel
    except ImportError:
        raise SystemExit("pocket-tts n'est pas installe : pip install pocket-tts")

    # Mesure du 2026-09-01 sur le modele francais : 1 fil rend 1,02x le temps reel et le
    # premier son a 411 ms ; 4 fils rendent 1,46x et 190 ms ; 8 fils 1,66x et 164 ms. Le
    # defaut de torch est 1, et c'est le pire des trois.
    torch.set_num_threads(args.threads)

    text = voice_bench.lines()[args.line]
    print(u'replique "%s" : %s' % (args.line, text))

    started = time.time()
    model = TTSModel.load_model(args.language)
    print("modele '%s' charge en %.1f s" % (args.language, time.time() - started))

    out = os.path.join(HERE, "out")
    if not os.path.isdir(out):
        os.makedirs(out)

    if args.catalogue:
        speak_catalogue(model, text, out, args)
        return

    for contact, reference in voice_bench.references(args.voices):
        if args.characters and contact not in args.characters:
            continue

        # Les deux couts, separement : c'est la mesure qui decide de l'architecture du mod.
        cloned = time.time()
        try:
            state = model.get_state_for_audio_prompt(reference)
        except ValueError as refused:
            raise SystemExit(CLONING_GATED % refused)
        cloning = time.time() - cloned

        spoke = time.time()
        audio = model.generate_audio(state, text)
        speaking = time.time() - spoke

        target = os.path.join(out, "pocket-%s-%s%s.wav" % (contact, args.line, args.tag))
        write_wav(target, model.sample_rate, audio)
        voice_bench.report(contact, speaking, target, "  clonage %.2f s" % cloning)


def catalogue_names():
    """Les voix pretes du modele.

    Le paquet n'expose pas de liste publique : elle vit dans un dictionnaire prive, dont les
    valeurs disent ce que ces voix SONT -- des clips de reference, pas des voix entrainees.
    La plupart viennent de VCTK et EARS, donc de locuteurs anglais, ce qui est la limite du
    catalogue pour un mod francais.
    """
    from pocket_tts.utils import utils
    return sorted(getattr(utils, "_ORIGINS_OF_PREDEFINED_VOICES", {}))


def speak_catalogue(model, text, out, args):
    """Les voix pretes du modele, sans clonage.

    C'est la moitie qui tourne sans compte Hugging Face, et elle repond a sa propre question :
    un repli doit distinguer beaucoup de PNJ, et un catalogue de vingt-six voix en distingue
    plus que les trois que Windows installe.
    """
    voices = args.characters or catalogue_names()
    for name in voices:
        spoke = time.time()
        state = model.get_state_for_audio_prompt(name)
        audio = model.generate_audio(state, text)
        target = os.path.join(out, "pocket-voix-%s-%s%s.wav" % (name, args.line, args.tag))
        write_wav(target, model.sample_rate, audio)
        voice_bench.report(name, time.time() - spoke, target)


if __name__ == "__main__":
    main()
