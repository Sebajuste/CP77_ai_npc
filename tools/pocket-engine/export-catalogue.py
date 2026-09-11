# -*- coding: utf-8 -*-
"""Convertit les voix de catalogue de Kyutai vers le cache d'etats que le moteur sait relire.

    python tools\\pocket-engine\\export-catalogue.py --out models\\fr --language french_24l

Ecrit `<out>\\catalogue\\<nom>.kv`, une par voix nommee dans une fiche de personnage. C'est ce
qui fait parler le pack LIBRE : sans encodeur, le moteur ne peut pas fabriquer une voix a partir
d'un son, mais il peut en charger une deja faite.

CE QUE SONT CES FICHIERS. Pas des embeddings malgre leur nom : l'etat KV complet du transformeur
apres conditionnement, 26 Mo par voix en fp32. Exactement le meme objet que le cache `.kv` que
le runtime ecrit lui-meme apres avoir clone un WAV -- d'ou la conversion, qui n'est qu'un
rempaquetage.

DEUX ORDRES QUI NE SONT PAS LE MEME, et c'est le piege de ce fichier. Les cles safetensors se
listent en ordre de CHAINE -- `layers.0`, `layers.1`, `layers.10`, ... `layers.2` -- tandis que
les entrees `state_*` du graphe ONNX sont en ordre NUMERIQUE : `state_0..2` est la couche 0.
Suivre l'ordre du fichier melangerait les couches, et un etat melange donne une voix qui
babille sans que rien ne le signale.

LE FP16 EST LU EN TRANCHE. `restore_from_disk` compare la forme livree a celle que le graphe
attend et replace une tranche dans le tampon complet : on ecrit donc les 133 images telles
quelles, sans les completer jusqu'a 1000.
"""
import argparse
import glob
import os
import re
import struct
import sys

# Les valeurs du type ONNX que le blob porte, telles que le runtime les compare.
ONNX_FLOAT16 = 10
ONNX_INT64 = 7

KV_MAGIC = 0x3143564B  # "KVC1"


def kv_blob(layers):
    """Le blob que `StateBufferIO::restore_from_disk` relit.

    En-tete : current_buf, puis le nombre d'etats. Ensuite, par etat : ndims, la forme, le type,
    le nombre d'octets, les octets. `current_buf` vaut zero -- le runtime le pose tel quel, et
    un etat charge n'a pas d'historique de double tampon a restituer.
    """
    import torch

    out = bytearray()
    out += struct.pack("<ii", 0, len(layers) * 3)
    for cache, offset in layers:
        k = cache[0].contiguous().to(dtype=torch.float16).numpy()
        v = cache[1].contiguous().to(dtype=torch.float16).numpy()
        for half in (k, v):
            data = half.tobytes()
            out += struct.pack("<i", len(half.shape))
            out += struct.pack("<%dq" % len(half.shape), *half.shape)
            out += struct.pack("<i", ONNX_FLOAT16)
            out += struct.pack("<q", len(data))
            out += data
        step = struct.pack("<q", int(offset))
        out += struct.pack("<i", 1)
        out += struct.pack("<q", 1)
        out += struct.pack("<i", ONNX_INT64)
        out += struct.pack("<q", len(step))
        out += step
    return bytes(out)


def read_voice(path):
    """Les 24 couches d'une voix, remises en ordre numerique."""
    from safetensors import safe_open

    caches = {}
    offsets = {}
    with safe_open(path, "pt") as handle:
        for key in handle.keys():
            match = re.match(r"transformer\.layers\.(\d+)\.self_attn/(cache|offset)", key)
            if match is None:
                raise SystemExit("cle inattendue dans %s : %s" % (path, key))
            layer = int(match.group(1))
            if match.group(2) == "cache":
                caches[layer] = handle.get_tensor(key)
            else:
                offsets[layer] = int(handle.get_tensor(key).reshape(-1)[0])

    if sorted(caches) != list(range(len(caches))) or sorted(caches) != sorted(offsets):
        raise SystemExit("%s : couches manquantes ou dupliquees" % path)
    return [(caches[i], offsets[i]) for i in sorted(caches)]


# Ecartees a la mesure du 2026-09-01 (tools\tts-lab\assign-fallback.py) : `marius` ne rend
# presque rien, `stuart_bell` est tres bas, `lola` etire une phrase sur 11 s.
UNUSABLE = ("marius", "stuart_bell", "lola")


def shipped_voices(directories):
    """Tout le catalogue, moins les voix inutilisables.

    Pas seulement celles que le casting d'ai_npc nomme : GetVoice() laisse n'importe quel mod
    nommer une voix du catalogue, et une voix absente du pack fait parler son personnage avec
    la voix de Windows, sans rien signaler.
    """
    names = set()
    for directory in directories:
        for path in glob.glob(os.path.join(directory, "*.safetensors")):
            names.add(os.path.splitext(os.path.basename(path))[0])
    return sorted(names - set(UNUSABLE))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, help="le dossier de modeles a completer")
    parser.add_argument("--language", default="french_24l")
    parser.add_argument("voices", nargs="*", help="par defaut, celles que les fiches nomment")
    args = parser.parse_args()

    pattern = os.path.join(
        os.path.expanduser("~"), ".cache", "huggingface", "hub",
        "models--kyutai--pocket-tts-without-voice-cloning", "snapshots", "*",
        "languages", args.language, "embeddings")
    directories = [d for d in glob.glob(pattern) if os.path.isdir(d)]
    if not directories:
        raise SystemExit("les voix de %s ne sont pas dans le cache Hugging Face ; "
                         "lancer export-models.py d'abord" % args.language)

    names = args.voices or shipped_voices(directories)

    target = os.path.join(args.out, "catalogue")
    os.makedirs(target, exist_ok=True)

    total = 0
    for name in names:
        source = None
        for directory in directories:
            candidate = os.path.join(directory, name + ".safetensors")
            if os.path.isfile(candidate):
                source = candidate
                break
        if source is None:
            print("  %-16s ABSENTE du catalogue %s" % (name, args.language))
            continue

        blob = kv_blob(read_voice(source))
        path = os.path.join(target, name + ".kv")
        with open(path, "wb") as handle:
            handle.write(struct.pack("<I", KV_MAGIC))
            handle.write(struct.pack("<Q", len(blob)))
            handle.write(blob)
        size = os.path.getsize(path) / 1e6
        total += size
        print("  %-16s %6.1f Mo" % (name, size))

    print("  %-16s %6.1f Mo" % ("TOTAL", total))


if __name__ == "__main__":
    sys.exit(main())
