# -*- coding: utf-8 -*-
"""Ouvre ww2ogg sur des tampons memoire, pour qu'il tienne dans ai_npc.dll.

    python tools\\pocket-engine\\patch-decoder.py

Idempotent. `git checkout` dans vendor\\ww2ogg annule tout.

POURQUOI. ww2ogg est ecrit comme un outil de ligne de commande : il ouvre un `ifstream` sur un
nom de fichier et ecrit dans un `ofstream`. Dans le jeu il n'y a ni l'un ni l'autre -- la
replique sort d'une archive deja ouverte et va directement au decodeur, et le mod n'a le droit
d'ecrire que dans `r6\\storages\\`. Un fichier intermediaire par replique serait sept ecritures
par personnage pour rien.

Le patch est mecanique et ne touche a aucune logique : `ifstream` devient `istream` la ou c'est
un parametre, le membre devient un `istringstream`, et la sortie devient un `ostream`. Les
lectures elles-memes (`seekg`, `read`, `get`, `tellg`) existent a l'identique sur les deux.

La bibliotheque de codebooks n'est PAS touchee : elle lit un fichier, et ce fichier est livre a
cote des modeles. Cyberpunk en a besoin -- mesure du 2026-09-01, ses .wem refusent les codebooks
integres avec « nonsense codeword length » et passent avec packed_codebooks_aoTuV_603.bin, que
ww2ogg distribue sous la meme licence que son code.
"""
import io
import sys
from pathlib import Path

# (fichier, ancien, nouveau, occurrences attendues)
EDITS = [
    # `istringstream` a besoin de son en-tete : l'amont n'incluait que <fstream>, n'ayant jamais
    # lu autre chose qu'un fichier.
    ("src/wwriff.h", "#include <fstream>", "#include <fstream>" + chr(10) + "#include <sstream>", 1),

    # L'entree du convertisseur.
    ("src/wwriff.h", "    ifstream _infile;", "    istringstream _infile;", 1),
    ("src/wwriff.h",
     "    Wwise_RIFF_Vorbis(\n      const string& name,",
     "    Wwise_RIFF_Vorbis(\n      const string& name,\n      const char * bytes,\n      long byte_count,",
     1),
    ("src/wwriff.h", "    void generate_ogg(ofstream& of);", "    void generate_ogg(ostream& of);", 1),
    ("src/wwriff.cpp", "Packet(ifstream& i,", "Packet(istream& i,", 1),
    ("src/wwriff.cpp", "Packet_8(ifstream& i,", "Packet_8(istream& i,", 1),
    ("src/wwriff.cpp", "void Wwise_RIFF_Vorbis::generate_ogg(ofstream& of)",
     "void Wwise_RIFF_Vorbis::generate_ogg(ostream& of)", 1),
    ("src/wwriff.cpp",
     "    _infile(name.c_str(), ios::binary),",
     "    _infile(string(bytes, byte_count), ios::binary),",
     1),
    ("src/wwriff.cpp",
     "Wwise_RIFF_Vorbis::Wwise_RIFF_Vorbis(\n    const string& name,",
     "Wwise_RIFF_Vorbis::Wwise_RIFF_Vorbis(\n    const string& name,\n    const char * bytes,\n    long byte_count,",
     1),
]

def main():
    root = Path(__file__).resolve().parent.parent.parent / "vendor" / "ww2ogg"
    if not (root / "src" / "wwriff.cpp").is_file():
        raise SystemExit("introuvable : %s -- lancer build.ps1 -Fetch" % root)

    if "istringstream _infile" in io.open(root / "src" / "wwriff.h", encoding="utf-8").read():
        print("deja patche")
        return 0

    for name, old, new, count in EDITS:
        path = root / name
        text = io.open(path, encoding="utf-8").read()
        seen = text.count(old)
        if seen != count:
            raise SystemExit("%s : ancre attendue %d fois, vue %d -- la source amont a bouge :\n%s"
                             % (name, count, seen, old.splitlines()[0]))
        io.open(path, "w", encoding="utf-8", newline="\n").write(text.replace(old, new, count))

    print("patche : ww2ogg lit et ecrit en memoire")
    return 0


if __name__ == "__main__":
    sys.exit(main())
