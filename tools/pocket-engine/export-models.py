# -*- coding: utf-8 -*-
"""Fabrique le jeu de modeles ONNX que le moteur C++ charge, pour une langue.

    python tools\\pocket-engine\\export-models.py --out models\\fr
    python tools\\pocket-engine\\export-models.py --out models\\fr-clonage --cloning

Sortie : le pack libre par defaut, le pack de clonage avec --cloning. Les deux ne different
que par `mimi_encoder.onnx` -- verifie le 2026-09-01, les autres fichiers sortent identiques
octet pour octet des deux jeux de poids.

INSTALLATION -- elle est de l'utilisateur, pas d'un agent : le modele francais pese 672 Mo au
telechargement et l'export en ecrit 1,6 Go d'intermediaires.

    py -3.10 -m venv .venv-pocket
    .venv-pocket\\Scripts\\pip install pocket-tts==2.1.0 onnx onnxruntime
    .venv-pocket\\Scripts\\python tools\\pocket-engine\\export-models.py --out models\\fr

LA VERSION EST FIGEE ET NE SE CHOISIT PAS. `export_onnx.py` remplace a chaud des internes du
paquet, et sur les onze versions publiees **2.1.0 est la seule** a offrir a la fois
`_LinearKVCacheBackend` et une configuration `french_24l` : les 1.x n'ont qu'une langue, les
3.x ont supprime la classe. Elle pointe sur les memes revisions de poids que la 3.0.2, donc le
cache Hugging Face se partage.
"""
import argparse
import io
import shutil
import sys
from pathlib import Path

# Le pack libre laisse tomber l'encodeur : ses poids sont a zero dans
# `pocket-tts-without-voice-cloning`, donc le fichier ne saurait produire qu'un conditionnement
# vide a partir d'un WAV. Mesure du 2026-09-01, ecart-type nul sur toutes ses matrices.
FREE_MODELS = ["text", "main", "flow", "decoder"]

# Ce que la quantification a le droit de toucher.
#
# `flow_lm_flow` EN EST EXCLU, et c'est le contraire de l'intuition : le gros `flow_lm_main`,
# 302 M parametres, supporte l'INT8 sans qu'on l'entende, tandis que ce petit reseau de 9,8 M
# rend une voix deformee, avec des erreurs et de la musique. C'est un solveur qui raffine un
# latent par integration, donc l'erreur de quantification y est reinjectee a chaque pas au lieu
# d'etre diluee. Le garder en fp32 coute 29 Mo.
QUANTISED = ["flow_lm_main", "mimi_decoder"]


def load_exporter(runtime_dir):
    """Le script d'export amont, avec beartype neutralise avant l'import de pocket_tts."""
    sys.path.insert(0, str(runtime_dir))

    import beartype
    import beartype.claw
    beartype.beartype = lambda func: func
    beartype.claw.beartype_this_package = lambda *a, **kw: None
    beartype.claw.beartype_package = lambda *a, **kw: None

    import export_onnx
    return export_onnx


def quantise(exporter, out_dir):
    from onnxruntime.quantization import QuantType, quantize_dynamic

    for name in QUANTISED:
        src = out_dir / (name + ".onnx")
        dst = out_dir / (name + "_int8.onnx")
        quantize_dynamic(model_input=str(src), model_output=str(dst),
                         weight_type=QuantType.QInt8, op_types_to_quantize=["MatMul"])
        print("  %s -> %s (%.1f Mo)" % (src.name, dst.name, dst.stat().st_size / 1e6))
        src.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, help="dossier de sortie")
    parser.add_argument("--language", default="french_24l")
    parser.add_argument("--cloning", action="store_true",
                        help="poids sur liste d'autorisation, et l'encodeur qui va avec ; "
                             "ce pack ne se publie pas")
    parser.add_argument("--runtime", default=None,
                        help="la copie de PocketTTS.cpp qui porte export_onnx.py")
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    runtime = Path(args.runtime) if args.runtime else here.parent.parent / "vendor" / "PocketTTS.cpp"
    if not (runtime / "export_onnx.py").is_file():
        raise SystemExit("export_onnx.py introuvable dans %s -- lancer build.ps1 -Fetch" % runtime)

    exporter = load_exporter(runtime)

    from pocket_tts.default_parameters import (
        DEFAULT_EOS_THRESHOLD, DEFAULT_LSD_DECODE_STEPS, DEFAULT_NOISE_CLAMP, DEFAULT_TEMPERATURE,
    )
    from pocket_tts.models.tts_model import TTSModel
    from pocket_tts.utils.config import CONFIGS_DIR, load_config
    from pocket_tts.utils.utils import download_if_necessary
    from safetensors import safe_open

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    config = load_config(CONFIGS_DIR / (args.language + ".yaml"))
    if not args.cloning:
        config.weights_path = config.weights_path_without_voice_cloning

    weights = download_if_necessary(config.weights_path)
    shutil.copy(download_if_necessary(config.flow_lm.lookup_table.tokenizer_path),
                out / "tokenizer.model")

    print("chargement de %s (%s)..." % (args.language, "clonage" if args.cloning else "libre"))
    model = TTSModel._from_pydantic_config_with_weights(
        config,
        temp=DEFAULT_TEMPERATURE,
        lsd_decode_steps=DEFAULT_LSD_DECODE_STEPS,
        noise_clamp=DEFAULT_NOISE_CLAMP,
        eos_threshold=DEFAULT_EOS_THRESHOLD,
    )
    model.eval()

    # L'exporteur fige les 6 couches du modele anglais dans une constante de classe ; toutes les
    # variantes `_24l` en ont 24, et l'export echoue sinon en depilant les etats KV.
    exporter.FlowLMMainWrapper.NUM_LAYERS = len(model.flow_lm.transformer.layers)

    exporter.export_text_conditioner(model, out / "text_conditioner.onnx")
    exporter.export_flow_lm_main(model, out / "flow_lm_main.onnx", exporter.MAX_SEQ_LEN)
    exporter.export_flow_lm_flow(model, out / "flow_lm_flow.onnx")
    exporter.export_mimi_decoder(model, out / "mimi_decoder.onnx")
    if args.cloning:
        exporter.export_mimi_encoder(model, out / "mimi_encoder.onnx")

    quantise(exporter, out)

    # Le vecteur que la config appelle `insert_bos_before_voice` et que l'export amont ignore.
    # Sans lui l'etat de conditionnement est bati sans sa premiere rangee, et le modele babille.
    if config.flow_lm.insert_bos_before_voice:
        with safe_open(weights, "pt") as handle:
            bos = handle.get_tensor("flow_lm.bos_before_voice").float().reshape(-1)
        (out / "bos_before_voice.bin").write_bytes(bos.numpy().tobytes())

    # La valeur que le runtime ne peut pas lire : il n'ouvre aucun YAML. Ecrite a cote des
    # modeles pour que le lanceur la passe en `--eos-extra`.
    frames = config.model_recommended_frames_after_eos
    if frames is not None:
        io.open(out / "frames_after_eos.txt", "w", encoding="ascii").write(str(frames))

    total = 0.0
    for f in sorted(out.glob("*")):
        if f.is_file():
            total += f.stat().st_size / 1e6
            print("  %-30s %8.2f Mo" % (f.name, f.stat().st_size / 1e6))
    print("  %-30s %8.2f Mo" % ("TOTAL", total))


if __name__ == "__main__":
    main()
