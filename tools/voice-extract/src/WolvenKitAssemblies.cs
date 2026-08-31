using System.Reflection;
using System.Runtime.Loader;

namespace VoiceExtract;

// WolvenKit n'est pas redistribue : le binaire est charge depuis l'installation du
// joueur, et ses dependances transitives ne sont pas dans notre dossier de sortie.
internal static class WolvenKitAssemblies
{
    private static string _directory;

    public static string Directory => _directory;

    public static void UseDirectory(string directory)
    {
        _directory = directory;
        AssemblyLoadContext.Default.Resolving += Resolve;
    }

    public static Assembly Load(string simpleName)
        => Assembly.LoadFrom(Path.Combine(_directory, simpleName + ".dll"));

    private static Assembly Resolve(AssemblyLoadContext context, AssemblyName name)
    {
        var candidate = Path.Combine(_directory, name.Name + ".dll");
        return File.Exists(candidate) ? context.LoadFromAssemblyPath(candidate) : null;
    }
}
