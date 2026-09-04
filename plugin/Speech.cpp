#include "Speech.hpp"

#include "Audio.hpp"
#include "PocketVoice.hpp"
#include "SapiVoice.hpp"
#include "VoiceMake.hpp"

#include <chrono>
#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ainpc::speech
{
namespace
{
// Une file et pas un emplacement, et c'est la voie streamee qui l'a decide. Une reponse arrive
// en plusieurs phrases, chacune remise pendant que la precedente se synthetise encore, et un
// emplacement unique garderait la premiere et la derniere en perdant silencieusement tout ce
// qu'il y a entre.
//
// Bornee, parce que la file est les prochaines secondes de parole d'un personnage : passe une
// poignee, ce qui attend ne repond plus a rien de ce que le joueur a fait. C'est la plus
// ancienne qui part, pas la plus recente -- la fin d'une reponse porte ce qui a ete decide.
constexpr size_t kQueueLimit = 16;

struct Line
{
    std::string text;
    std::string contactId;

    // Le fichier de reference que la fiche du personnage nomme. Vide, ce personnage n'a pas de
    // voix clonable et la voie descend d'un palier.
    std::string voiceFile;

    // La voix de catalogue de la fiche. Ce qui parle quand aucun clone n'est possible -- et le
    // seul palier que le pack libre puisse offrir.
    std::string catalogueVoice;
    // La langue du doublage a chercher dans les archives du joueur. Sur le fil pour la meme
    // raison que le contact : le worker n'a pas de session a interroger.
    std::string language;

    // Une preparation, pas une replique : le tampon est jete au lieu d'etre joue. Elle passe
    // par la meme file pour la meme raison que tout le reste -- un modele qui se charge sur
    // deux fils est un modele charge deux fois.
    bool warmOnly = false;

    // Son rang dans la parole. Zero pour une preparation, qui ne s'entend pas.
    uint32_t line = 0;
};

struct Worker
{
    std::mutex mutex;
    std::condition_variable wake;
    std::deque<Line> pending;
    std::wstring pluginDirectory;

    // Ou en est chaque voix demandee. Par contact et pas un seul etat global : un appel a Judy
    // pendant que Rogue chauffe encore doit repondre sur Judy.
    std::map<std::string, std::string> warmth;

    // Le numero de la prochaine replique, et le texte de celles qui peuvent encore s'entendre.
    // Purgee au fil de la lecture : une conversation entiere n'a pas a rester en memoire pour
    // qu'une phrase s'affiche.
    uint32_t nextLine = 1;
    std::map<uint32_t, std::string> spoken;

    std::string result = "nothing said yet";
    bool running = false;
    bool stopping = false;
    std::thread thread;

    // A LA FIN DU PROCESSUS, pour la meme raison que ~Voice, et c'est le meme code de sortie.
    //
    // Le fil sort de lui-meme quand la file se vide, mais l'objet std::thread reste JOIGNABLE
    // tant que personne ne l'a joint, et detruire un std::thread joignable appelle
    // std::terminate. Shutdown() le fait quand on l'appelle ; rien ne garantit qu'on l'appelle.
    // Mesure du 2026-09-04 : le banc annoncait 251 controles et zero echec, puis sortait en
    // 0xC0000409 -- tout etait juste, et le processus mourait quand meme.
    //
    // Shutdown() a deja emporte le fil quand il est passe, donc ceci ne joint rien deux fois.
    ~Worker()
    {
        std::thread last;
        {
            std::lock_guard<std::mutex> guard(mutex);
            stopping = true;
            wake.notify_all();
            last = std::move(thread);
        }
        if (last.joinable())
        {
            last.join();
        }
    }
};

Worker& TheWorker()
{
    static Worker worker;
    return worker;
}

void SetResult(const std::string& aText)
{
    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    worker.result = aText;
}

// Le moteur qui a rempli le tampon, pour que le worker sache en quel format il est.
enum class Engine
{
    Pocket,
    Sapi,
};

// Rend une replique, du meilleur moteur disponible POUR CE CONTACT vers le plus modeste.
//
// La voie neuronale est essayee d'abord et son echec n'est pas fatal : un modele qui refuse de
// se charger, une reference illisible, et le personnage parle quand meme. Ce qui reste dans
// `aWhy` est la raison du repli, pas une erreur -- elle est journalisee telle quelle, parce que
// « ca parle avec la voix de Windows » sans explication est la question qui coute le plus de
// temps a quelqu'un qui vient d'installer le pack.
bool RenderBest(const std::wstring& aPluginDirectory, const Line& aLine,
                std::vector<uint8_t>& aSamples, Engine& aEngine, std::string& aWhy)
{
    // Le pack de clonage installe est ce qui autorise une reference, et sa premiere consequence
    // est ici : si ce personnage n'en a pas encore, on la fabrique maintenant, depuis les
    // archives du joueur. ~250 ms, une seule fois, et elles tombent dans l'attente du modele
    // que le joueur paie deja. Sans le pack, `Available` dit non et rien de tout cela n'arrive.
    if (voice::Available(aPluginDirectory) && !aLine.voiceFile.empty() &&
        !voice::HasVoiceFor(aPluginDirectory, aLine.voiceFile) && voicemake::Possible(aPluginDirectory))
    {
        std::string made;
        if (voicemake::Make(aPluginDirectory, aLine.contactId, aLine.voiceFile, aLine.language, made))
        {
            aWhy = "made a reference for " + aLine.contactId + " (" + made + "); ";
        }
        else
        {
            aWhy = "no reference for " + aLine.contactId + ": " + made + "; ";
        }
    }

    // Les paliers, du plus proche du personnage au plus modeste. Chacun est essaye seulement
    // s'il est reellement disponible, et par personnage : un joueur aura Judy clonee, Rogue au
    // catalogue et un contact tiers sur la voix de Windows, dans la meme partie.
    if (voice::Available(aPluginDirectory))
    {
        std::string tier;
        if (voice::HasVoiceFor(aPluginDirectory, aLine.voiceFile))
        {
            tier = aLine.voiceFile;
        }
        else if (voice::HasCatalogueVoice(aPluginDirectory, aLine.catalogueVoice))
        {
            tier = aLine.catalogueVoice;
        }

        if (!tier.empty())
        {
            // La voie neuronale JOUE ELLE-MEME, morceau par morceau : c'est ce qui fait sortir
            // le premier son en ~123 ms au lieu d'attendre la fin de la synthese. Elle ne rend
            // donc aucun tampon, et il n'y a rien a remettre au chemin audio apres elle.
            std::string neural;
            if (voice::Render(aPluginDirectory, tier, aLine.text, false, neural))
            {
                aEngine = Engine::Pocket;
                return true;
            }
            aSamples.clear();
            aWhy += "neural voice fell back: " + neural + "; ";
        }
    }

    aEngine = Engine::Sapi;
    std::string fallback;
    if (sapi::Render(aLine.text, aSamples, fallback))
    {
        return true;
    }
    aWhy += fallback;
    return false;
}

// Fait tout ce qu'une premiere replique ferait, sauf la dire. Le texte est le plus court qui
// produise un rendu : ce qui compte est le chemin traverse, pas ce qu'il rend.
bool WarmVoice(const std::wstring& aPluginDirectory, const Line& aLine, std::string& aWhy)
{
    if (!voice::HasVoiceFor(aPluginDirectory, aLine.voiceFile) && voicemake::Possible(aPluginDirectory))
    {
        std::string made;
        if (!voicemake::Make(aPluginDirectory, aLine.contactId, aLine.voiceFile, aLine.language, made))
        {
            aWhy = made;
        }
    }
    const std::string tier = voice::HasVoiceFor(aPluginDirectory, aLine.voiceFile)
                                 ? aLine.voiceFile
                                 : (voice::HasCatalogueVoice(aPluginDirectory, aLine.catalogueVoice)
                                        ? aLine.catalogueVoice
                                        : std::string());
    if (tier.empty())
    {
        return false;
    }
    // La replique la plus courte qui traverse tout le chemin, et MUETTE : ce qui compte est le
    // chemin traverse, pas ce qu'il rend. Un prechauffage qui parlerait ferait dire « Oui. » a
    // un personnage pendant que son telephone sonne.
    std::string neural;
    if (!voice::Render(aPluginDirectory, tier, "Oui.", true, neural))
    {
        aWhy = neural;
        return false;
    }
    return true;
}

void Run()
{
    for (;;)
    {
        Line line;
        std::wstring pluginDirectory;
        {
            Worker& worker = TheWorker();
            std::unique_lock<std::mutex> lock(worker.mutex);
            worker.wake.wait(lock, [&worker]() { return worker.stopping || !worker.pending.empty(); });
            if (worker.stopping)
            {
                break;
            }
            line = std::move(worker.pending.front());
            worker.pending.pop_front();
            pluginDirectory = worker.pluginDirectory;
        }

        // Tout ce qui sera pousse jusqu'a la replique suivante appartient a celle-ci, quel que
        // soit le moteur qui la produit.
        audio::SetLine(line.line);

        const auto started = std::chrono::steady_clock::now();
        std::vector<uint8_t> samples;
        Engine engine = Engine::Sapi;
        std::string why;

        // Une preparation ne descend jamais jusqu'a la voix de secours : elle n'a rien a dire,
        // et SAPI n'a rien a preparer. Ce qu'elle chauffe est le modele, la reference et l'etat
        // de voix ; le tampon produit est jete.
        if (line.warmOnly)
        {
            const bool ready = voice::Available(pluginDirectory) && WarmVoice(pluginDirectory, line, why);
            const auto elapsed =
                std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started)
                    .count();
            {
                Worker& worker = TheWorker();
                std::lock_guard<std::mutex> guard(worker.mutex);
                worker.warmth[line.contactId] = ready ? "ready" : "unavailable";
            }
            SetResult(std::string(ready ? "warmed " : "not warmed ") + line.contactId + " in " +
                      std::to_string(elapsed) + " ms" + (why.empty() ? "" : " -- " + why));
            continue;
        }

        if (!RenderBest(pluginDirectory, line, samples, engine, why))
        {
            SetResult("no voice: " + why);
            continue;
        }

        // La voie neuronale a deja joue, morceau par morceau, et c'est ce qui fait sortir le
        // premier son en ~123 ms. Il ne reste donc rien a remettre ici : ce bloc n'est que pour
        // la voix de secours.
        //
        // SAPI ecrit ce qu'on lui a demande, mais un flux qui porterait un en-tete RIFF serait
        // silencieusement injouable en PCM brut -- donc la forme est lue plutot que supposee.
        audio::Status status = audio::Status::Ok;
        if (engine == Engine::Sapi)
        {
            if (samples.size() > 4 && samples[0] == 'R' && samples[1] == 'I' && samples[2] == 'F' &&
                samples[3] == 'F')
            {
                status = audio::PlayWav(samples.data(), samples.size());
            }
            else
            {
                audio::Format format;
                format.sampleRate = sapi::SampleRate();
                format.channels = sapi::Channels();
                format.bitsPerSample = sapi::BitsPerSample();
                status = audio::Play(samples.data(), samples.size(), format);
            }
        }

        // Le nombre dont depend la voie parlee : ce que le joueur attend entre une replique
        // remise et le premier son. Le nom du moteur l'accompagne, parce que trois secondes de
        // la voix du personnage et trois secondes de celle de Windows ne veulent pas dire la
        // meme chose.
        const auto milliseconds =
            std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started)
                .count();
        SetResult(std::string(engine == Engine::Pocket ? "pocket" : "sapi") + " -- " +
                  std::string(audio::Describe(status)) + " -- " + std::to_string(samples.size()) +
                  " bytes in " + std::to_string(milliseconds) + " ms" + (why.empty() ? "" : " -- " + why));
    }
}
} // namespace

bool Render(const std::string& aUtf8Text, std::vector<uint8_t>& aSamples, std::string& aWhy)
{
    return sapi::Render(aUtf8Text, aSamples, aWhy);
}

uint32_t SampleRate()
{
    return sapi::SampleRate();
}

uint16_t Channels()
{
    return sapi::Channels();
}

uint16_t BitsPerSample()
{
    return sapi::BitsPerSample();
}

bool Speak(const std::string& aUtf8Text, const std::string& aContactId,
           const std::string& aVoiceFile, const std::string& aCatalogueVoice,
           const std::string& aLanguage)
{
    if (aUtf8Text.empty())
    {
        return false;
    }

    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    if (worker.stopping)
    {
        return false;
    }
    if (!worker.running)
    {
        worker.running = true;
        worker.thread = std::thread(&Run);
    }

    const uint32_t line = worker.nextLine;
    worker.nextLine += 1;
    worker.spoken[line] = aUtf8Text;

    worker.pending.push_back(
        Line{aUtf8Text, aContactId, aVoiceFile, aCatalogueVoice, aLanguage, false, line});
    while (worker.pending.size() > kQueueLimit)
    {
        worker.spoken.erase(worker.pending.front().line);
        worker.pending.pop_front();
    }
    worker.wake.notify_one();
    return true;
}

void Warm(const std::string& aContactId, const std::string& aVoiceFile,
          const std::string& aCatalogueVoice, const std::string& aVoiceOverLocale)
{
    if (aContactId.empty())
    {
        return;
    }

    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    if (worker.stopping)
    {
        return;
    }
    if (!worker.running)
    {
        worker.running = true;
        worker.thread = std::thread(&Run);
    }

    worker.warmth[aContactId] = "pending";

    // DEVANT, et c'est la seule chose qui la distingue d'une replique dans cette file. Une
    // preparation qui arriverait apres la premiere replique n'aurait rien prepare du tout.
    worker.pending.push_front(
        Line{"", aContactId, aVoiceFile, aCatalogueVoice, aVoiceOverLocale, true});
    worker.wake.notify_one();
}

std::string Speaking()
{
    const uint32_t line = audio::PlayingLine();
    if (line == 0)
    {
        return {};
    }

    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);

    // Ce qui est derriere la replique entendue ne se dira plus : personne ne peut remonter la
    // file. La purge tient donc la table a la taille de ce qui reste a entendre.
    for (auto it = worker.spoken.begin(); it != worker.spoken.end();)
    {
        it = it->first < line ? worker.spoken.erase(it) : std::next(it);
    }

    const auto found = worker.spoken.find(line);
    return found == worker.spoken.end() ? std::string{} : found->second;
}

void Silence()
{
    // La marque d'abandon d'abord : le worker peut etre au milieu d'une tranche, et la file
    // videe derriere lui ne l'arreterait pas.
    voice::CancelCurrent();

    {
        Worker& worker = TheWorker();
        std::lock_guard<std::mutex> guard(worker.mutex);
        worker.pending.clear();
        worker.spoken.clear();
    }

    audio::Stop();
    SetResult("silenced");
}

std::string VoiceState(const std::string& aContactId)
{
    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    const auto found = worker.warmth.find(aContactId);
    return found == worker.warmth.end() ? std::string("unknown") : found->second;
}

std::string LastResult()
{
    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    return worker.result;
}

void SetPluginDirectory(const std::wstring& aPluginDirectory)
{
    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    worker.pluginDirectory = aPluginDirectory;
}

void Shutdown()
{
    Worker& worker = TheWorker();
    std::thread thread;
    {
        std::lock_guard<std::mutex> guard(worker.mutex);
        worker.stopping = true;
        worker.wake.notify_all();
        thread = std::move(worker.thread);
    }
    if (thread.joinable())
    {
        thread.join();
    }
    audio::Stop();
    voice::Shutdown();
}
} // namespace ainpc::speech
