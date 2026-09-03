# -*- coding: utf-8 -*-
"""Reconcilie `vendor\\PocketTTS.cpp\\pocket_tts.cpp` avec le modele francais.

    python tools\\pocket-engine\\patch-runtime.py

Idempotent : relancer ne fait rien. `git checkout pocket_tts.cpp` dans le vendor annule tout.

Le runtime amont a ete bati et valide contre le seul checkpoint `english_2026-01`, et **il
n'ouvre aucun YAML**. Chaque champ de configuration ou le francais s'ecarte de ce modele est
donc un champ qu'il ne connait pas. Trois des quatre retouches ci-dessous viennent de la, et
chacune a ete trouvee a l'oreille ; le detail est dans `docs\\MEASURE_VOICE_ENGINE.md`.

La quatrieme est d'une autre nature : `ptt_create` n'expose pas `eos_extra`, que seul le drapeau
de la ligne de commande porte. Un hote qui embarque le moteur ne peut donc pas poser le reglage
dont le francais a besoin, et il lui faut un accesseur.
"""
import io
import sys
from pathlib import Path

BOS_HELPER_ANCHOR = "    Tensor encode_voice(const std::string& path) {"
BOS_HELPER = '''    // Le vecteur appris que la configuration du modele nomme `insert_bos_before_voice`, sorti du
    // checkpoint par export-models.py. Vide quand le fichier est absent, et c'est le
    // comportement amont : `english_2026-01` est le seul des treize modeles a n'en pas vouloir.
    std::vector<float> load_bos(const std::string& path) const {
        std::ifstream f(path, std::ios::binary);
        if (!f) return {};
        f.seekg(0, std::ios::end);
        const std::streamoff sz = f.tellg();
        f.seekg(0, std::ios::beg);
        if (sz <= 0 || sz % 4 != 0) return {};
        std::vector<float> v(size_t(sz) / 4);
        f.read(reinterpret_cast<char*>(v.data()), sz);
        return v;
    }

''' + BOS_HELPER_ANCHOR

# Le prefixe appartient au conditionnement, pas a l'encodage. Place dans `encode_voice`, il
# entre dans le tenseur que `voice_hash` echantillonne -- et cette fonction ne lit que les SEIZE
# PREMIERS flottants. Un BOS commun rend alors toutes les voix egales pour le cache d'etats, et
# le deuxieme personnage parle avec la voix du premier.
COND_ANCHOR = """            {
                auto _ = g_prof.time("voice_conditioning_pass");
                cond_pass(v.ptr(), v.numel(), v.shape);
            }"""
COND = """            {
                auto _ = g_prof.time("voice_conditioning_pass");
                // L'etat se batit sur [BOS, latents], jamais sur les latents seuls : sans cette
                // rangee le modele babille, et rien dans la sortie ne dit pourquoi.
                const std::vector<float> bos = tts.load_bos(tts.cfg_.models_dir + "/bos_before_voice.bin");
                if (!bos.empty() && v.shape.size() == 3 && size_t(v.shape[2]) == bos.size()) {
                    const std::vector<int64_t> sh = {v.shape[0], v.shape[1] + 1, v.shape[2]};
                    std::vector<float> merged;
                    merged.reserve(bos.size() + v.data.size());
                    merged.insert(merged.end(), bos.begin(), bos.end());
                    merged.insert(merged.end(), v.data.begin(), v.data.end());
                    cond_pass(merged.data(), merged.size(), sh);
                } else {
                    cond_pass(v.ptr(), v.numel(), v.shape);
                }
            }"""

CHUNK_ANCHOR = "    AudioData generate(const std::string& text, const std::string& voice, int max_frames = 500) {"
CHUNK = '''    // Le paquet Python empile les phrases jusqu'a ce budget avant de generer, la ou le runtime
    // en generait une par passe. Une phrase courte generee seule degenere : « Laisse tomber. »
    // en fin de replique etait inaudible, la meme phrase seule ne l'etait pas.
    static constexpr int MAX_TOKEN_PER_CHUNK = 50;

    std::vector<std::string> chunk_text(const std::string& text) {
        auto sentences = split_sentences(text);
        if (sentences.empty()) return {text};

        std::vector<std::string> chunks;
        std::string current;
        int current_tokens = 0;
        for (const auto& sentence : sentences) {
            const int n = int(tok_->encode(sentence).size());
            if (!current.empty() && current_tokens + n > MAX_TOKEN_PER_CHUNK) {
                chunks.push_back(current);
                current.clear();
                current_tokens = 0;
            }
            if (!current.empty()) current += " ";
            current += sentence;
            current_tokens += n;
        }
        if (!current.empty()) chunks.push_back(current);
        return chunks;
    }

''' + CHUNK_ANCHOR

SPLIT_ANCHOR = """    auto sentences = split_sentences(text);
    if (sentences.empty()) sentences.push_back(text);"""
SPLIT = "    auto sentences = chunk_text(text);"

# Le francais demande huit images apres l'EOS, et `ptt_create` n'expose pas ce reglage : seul le
# drapeau `--eos-extra` de la ligne de commande le porte, donc un hote qui embarque le moteur ne
# peut pas le poser. Ajout additif -- la signature amont ne bouge pas.
EOS_ANCHOR = "    const Config& config() const { return cfg_; }"
EOS = """    const Config& config() const { return cfg_; }

    // `model_recommended_frames_after_eos` de la configuration du modele, que le runtime n'ouvre
    // pas. L'hote la lit a cote des modeles et la pose ici.
    void set_eos_extra(int frames) { cfg_.eos_extra_frames = frames; }"""

CAPI_ANCHOR = """void ptt_destroy(void* handle) {
    delete static_cast<pocket_tts::PocketTTS*>(handle);
}"""

# Un modele livre seulement en fp32 est lu en fp32, quelle que soit la precision demandee.
#
# Le runtime ajoute `_int8` aux trois modeles quantifiables sans regarder ce qui est sur le
# disque, et notre recette livre `flow_lm_flow` en fp32 -- pas par oubli : quantifie, il deforme
# la voix. Resultat mesure en jeu le 2026-09-01, `ptt_create` echoue et le journal ne dit que
# « the speech model refused to load ». Le repli sur le nom sans suffixe rend le pack
# auto-descriptif : ce qui est livre est ce qui est charge.
PRECISION_ANCHOR = "    Tensor encode_voice(const std::string& path) {"
PRECISION = """    std::string model_path(const std::string& name, const std::string& sfx) const {
        const std::string preferred = cfg_.models_dir + "/" + name + sfx + ".onnx";
        std::ifstream probe(preferred, std::ios::binary);
        if (probe) return preferred;
        return cfg_.models_dir + "/" + name + ".onnx";
    }

""" + PRECISION_ANCHOR

SESSION_ANCHOR = """        main_ = std::make_unique<OrtSession>(env, cfg_.models_dir + "/flow_lm_main" + sfx + ".onnx", opts_ar, "flow_lm_main" + sfx);
        flow_ = std::make_unique<OrtSession>(env, cfg_.models_dir + "/flow_lm_flow" + sfx + ".onnx", opts_ar, "flow_lm_flow" + sfx);
        dec_ = std::make_unique<OrtSession>(env, cfg_.models_dir + "/mimi_decoder" + sfx + ".onnx", opts_dec, "mimi_decoder" + sfx);"""
SESSION = """        main_ = std::make_unique<OrtSession>(env, model_path("flow_lm_main", sfx), opts_ar, "flow_lm_main");
        flow_ = std::make_unique<OrtSession>(env, model_path("flow_lm_flow", sfx), opts_ar, "flow_lm_flow");
        dec_ = std::make_unique<OrtSession>(env, model_path("mimi_decoder", sfx), opts_dec, "mimi_decoder");"""


# Les voix de CATALOGUE : un etat deja conditionne, livre avec les modeles.
#
# C'est ce qui fait parler le pack libre. Son encodeur est a zero, donc il ne peut pas fabriquer
# une voix a partir d'un son -- mais il peut en charger une deja faite, et Kyutai en livre
# vingt-six. `tools\pocket-engine\export-catalogue.py` les convertit vers ce format.
#
# Un nom qui n'est pas un `.wav` en designe une. Le contrat tient dans cette phrase, et il evite
# un second reglage : la fiche du personnage nomme `judy.wav` ou `eve`, et le moteur sait lequel
# des deux il tient.
CATALOGUE_ANCHOR = """    const Tensor& get_voice(const std::string& p) {
        voice_kv_path_ = p;
        auto it = vcache_.find(p);
        if (it != vcache_.end()) return it->second;"""
CATALOGUE = """    static bool is_catalogue_voice(const std::string& p) {
        return !p.empty() && (p.size() < 4 || p.compare(p.size() - 4, 4, ".wav") != 0);
    }

    // Le nom exact plutot que seize flottants echantillonnes. `voice_hash` suffisait tant que
    // chaque voix avait des latents a elle ; une voix de catalogue n'en a aucun, et deux
    // tenseurs vides sont egaux -- le deuxieme personnage parlerait avec la voix du premier.
    static uint64_t name_hash(const std::string& s) {
        uint64_t h = 14695981039346656037ull;
        for (unsigned char c : s) { h ^= c; h *= 1099511628211ull; }
        return h;
    }

    Tensor empty_voice_;

    const Tensor& get_voice(const std::string& p) {
        voice_kv_path_ = p;
        if (is_catalogue_voice(p)) return empty_voice_;
        auto it = vcache_.find(p);
        if (it != vcache_.end()) return it->second;"""

HASH_ANCHOR = """        uint64_t vh = voice_hash(v);
        
        // Tier 1: in-memory cache hit"""
HASH = """        uint64_t vh = voice_kv_path_.empty() ? voice_hash(v) : name_hash(voice_kv_path_);
        
        // Tier 1: in-memory cache hit"""

LOAD_ANCHOR = """        // Tier 2: disk cache hit
        if (cfg_.voice_cache && !voice_kv_path_.empty()) {"""
LOAD = """        // Une voix de catalogue EST un etat : elle se charge, elle ne se calcule pas. Aucune
        // des trois strates suivantes ne s'y applique -- il n'y a ni WAV a encoder, ni cache a
        // invalider contre lui.
        if (is_catalogue_voice(voice_kv_path_)) {
            const std::string path = cfg_.models_dir + "/catalogue/" + voice_kv_path_ + ".kv";
            StateBufferIO::DiskSnapshot ds;
            if (!ds.load_from_disk(path)) {
                throw std::runtime_error("no catalogue voice at " + path);
            }
            main_runner_->restore_from_disk(ds);
            voice_kv_snap_ = std::make_unique<VoiceKVSnapshot>(main_runner_->take_snapshot());
            voice_kv_hash_ = vh;
            return LatentGen(*this, *voice_kv_snap_, t, max, eos_extra);
        }

        // Tier 2: disk cache hit
        if (cfg_.voice_cache && !voice_kv_path_.empty()) {"""

CAPI = """void ptt_destroy(void* handle) {
    delete static_cast<pocket_tts::PocketTTS*>(handle);
}

void ptt_set_eos_extra(void* handle, int frames) {
    if (handle) static_cast<pocket_tts::PocketTTS*>(handle)->set_eos_extra(frames);
}"""



def main():
    root = Path(__file__).resolve().parent.parent.parent
    source = root / "vendor" / "PocketTTS.cpp" / "pocket_tts.cpp"
    if not source.is_file():
        raise SystemExit("introuvable : %s -- lancer build.ps1 -Fetch" % source)

    text = io.open(source, encoding="utf-8").read()
    if "load_bos" in text:
        print("deja patche")
        return 0

    for anchor, count in ((BOS_HELPER_ANCHOR, 1), (COND_ANCHOR, 1), (CHUNK_ANCHOR, 1),
                          (SPLIT_ANCHOR, 2), (EOS_ANCHOR, 1), (CAPI_ANCHOR, 1),
                          (PRECISION_ANCHOR, 1), (SESSION_ANCHOR, 1),
                          (CATALOGUE_ANCHOR, 1), (HASH_ANCHOR, 1), (LOAD_ANCHOR, 1)):
        seen = text.count(anchor)
        if seen != count:
            raise SystemExit(
                "ancre attendue %d fois, vue %d -- la source amont a bouge et le patch doit etre "
                "relu avant d'etre reapplique :\n%s" % (count, seen, anchor.splitlines()[0]))

    text = text.replace(BOS_HELPER_ANCHOR, BOS_HELPER)
    text = text.replace(COND_ANCHOR, COND)
    text = text.replace(CHUNK_ANCHOR, CHUNK)
    text = text.replace(SPLIT_ANCHOR, SPLIT)
    text = text.replace(EOS_ANCHOR, EOS)
    text = text.replace(CAPI_ANCHOR, CAPI)
    text = text.replace(SESSION_ANCHOR, SESSION)
    text = text.replace(CATALOGUE_ANCHOR, CATALOGUE)
    text = text.replace(HASH_ANCHOR, HASH)
    text = text.replace(LOAD_ANCHOR, LOAD)
    text = text.replace(PRECISION_ANCHOR, PRECISION)
    if "#include <fstream>" not in text:
        text = text.replace("#include <deque>", "#include <deque>\n#include <fstream>")

    io.open(source, "w", encoding="utf-8", newline="\n").write(text)
    print("patche : BOS, conditionnement, regroupement, eos-extra, precision, catalogue")
    return 0


if __name__ == "__main__":
    sys.exit(main())
