// Packs a depot tree into a .archive, which is what WolvenKit's Pack Project does to the
// same folder. Reflection rather than typed calls: HashService and the logger live in
// assemblies whose surface changes between WolvenKit releases, and a missing method here
// must fail with a name, not a compile error against a DLL that is not in the repo.
//
// args: <depot dir> <out .archive>
using System.IO;
using System.Reflection;

// The WolvenKit install to reflect against. Not redistributed and not on NuGet, so it is a
// local folder: the WolvenKitDir environment variable names it, and the fallback is only
// where an install lands if you unzip it beside the mods. Same property the .csproj resolves,
// so the DLLs loaded at run time are the ones the build compiled against.
var WK = Environment.GetEnvironmentVariable("WolvenKitDir");
if (string.IsNullOrWhiteSpace(WK))
    WK = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                      "Documents", "CP77_mods", "WolvenKit-8.20.0");
if (!WK.EndsWith(Path.DirectorySeparatorChar)) WK += Path.DirectorySeparatorChar;
if (!File.Exists(WK + "WolvenKit.RED4.dll"))
    throw new DirectoryNotFoundException(
        $"WolvenKit.RED4.dll not found under {WK}. Set the WolvenKitDir environment variable "
        + "to your WolvenKit 8.20 install (the folder holding WolvenKit.RED4.dll).");

var srcDir  = Path.GetFullPath(args[0]);
var outPath = Path.GetFullPath(args[1]);

if (!Directory.Exists(srcDir))
    throw new DirectoryNotFoundException($"no depot tree at {srcDir}");

// HashService decompresses its embedded hash table with Oodle, so the native kraken.dll
// has to be found before the first WolvenKit type is touched. It sits next to the managed
// DLLs, which is not a directory this process would search on its own.
var core0 = Assembly.LoadFrom(WK + "WolvenKit.Core.dll");
System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(core0, (name, asm, path) =>
    name == "kraken" ? System.Runtime.InteropServices.NativeLibrary.Load(WK + "kraken.dll") : IntPtr.Zero);

var common = Assembly.LoadFrom(WK + "WolvenKit.Common.dll");
var core   = core0;
var red4   = Assembly.LoadFrom(WK + "WolvenKit.RED4.dll");

var hashService = Activator.CreateInstance(common.GetType("WolvenKit.Common.Services.HashService"));
var logger      = Activator.CreateInstance(core.GetType("WolvenKit.SerilogWrapper"));

var writerType = red4.GetType("WolvenKit.RED4.Archive.IO.ArchiveWriter");
var writer     = Activator.CreateInstance(writerType, new[] { hashService, logger });
var write      = writerType.GetMethod("WriteArchive");

Directory.CreateDirectory(Path.GetDirectoryName(outPath));
using (var fs = File.Create(outPath))
    write.Invoke(writer, new object[] { new DirectoryInfo(srcDir), (Stream)fs });

var files = Directory.GetFiles(srcDir, "*", SearchOption.AllDirectories);
Console.WriteLine($"packed {files.Length} file(s) into {outPath} ({new FileInfo(outPath).Length} bytes)");
foreach (var f in files)
    Console.WriteLine("   " + Path.GetRelativePath(srcDir, f).Replace("/", "\\").ToLowerInvariant());
