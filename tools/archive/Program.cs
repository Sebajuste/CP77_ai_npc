// Packs a depot tree into a .archive, which is what WolvenKit's Pack Project does to the
// same folder. Reflection rather than typed calls: HashService and the logger live in
// assemblies whose surface changes between WolvenKit releases, and a missing method here
// must fail with a name, not a compile error against a DLL that is not in the repo.
//
// args: <depot dir> <out .archive>
using System.IO;
using System.Reflection;

const string WK = @"C:\Users\sebaj\Documents\CP77_mods\WolvenKit-8.20.0\";

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
