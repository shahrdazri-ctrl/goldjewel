using System.Reflection;
using System.Security.Cryptography;
using System.Text.Encodings.Web;
using System.Text.Json;
using Mono.Cecil;

namespace OracleCapture;

// Captures the shipped IL of a set of types without executing any vendor code.
// Reading IL is what makes this possible outside Rhino: CSBlocks.mgp is a
// mixed-mode plugin, so calling into it requires the Rhino host (see the
// execution block written into every corpus file). Metadata and instruction
// operands, by contrast, are fully readable and are the ground truth this
// corpus preserves: every string, numeric constant, call edge and field access
// for the target types, with IL offsets.
internal static class Program
{
    private const string ToolVersion = "OracleCapture/1";
    private const string Schema = "goldjewel.oracle.corpus/1";

    private static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("usage: OracleCapture <assembly> <out.json> <type-prefix> [<type-prefix> ...]");
            return 2;
        }

        string assemblyPath = Path.GetFullPath(args[0]);
        string outputPath = Path.GetFullPath(args[1]);
        string[] prefixes = args.Skip(2).ToArray();

        // The lab lives on D:. Refuse any write elsewhere instead of trusting
        // the caller's environment to keep the C: volume clean.
        string? root = Path.GetPathRoot(outputPath);
        if (root is null || !root.Equals(@"D:\", StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine($"refusing to write outside D: ({outputPath})");
            return 3;
        }

        if (!File.Exists(assemblyPath))
        {
            Console.Error.WriteLine($"missing assembly: {assemblyPath}");
            return 4;
        }

        ModuleDefinition module;
        try
        {
            module = ModuleDefinition.ReadModule(assemblyPath, new ReaderParameters { ReadSymbols = false });
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"cannot read IL: {ex.GetType().Name}: {ex.Message}");
            return 5;
        }

        using (module)
        {
            string assemblySha = Sha256(assemblyPath);
            string decompiledRoot = Path.Combine(LabRoot(), "03-decompiled", "raw", "CSBlocks");
            var sourceIndex = SourceIndex.Build(decompiledRoot);

            var types = new List<object>();
            int methodCount = 0, instructionCount = 0, stringCount = 0, constantCount = 0, callCount = 0;

            foreach (TypeDefinition type in module.GetTypes())
            {
                if (!prefixes.Any(p => type.FullName.StartsWith(p, StringComparison.Ordinal)))
                    continue;

                var methods = new List<object>();
                foreach (MethodDefinition method in type.Methods)
                {
                    methodCount++;
                    var strings = new List<object>();
                    var constants = new List<object>();
                    var calls = new List<object>();
                    var fields = new List<object>();
                    int instructions = 0;

                    if (method.HasBody)
                    {
                        foreach (Mono.Cecil.Cil.Instruction ins in method.Body.Instructions)
                        {
                            instructions++;
                            switch (ins.OpCode.Code)
                            {
                                case Mono.Cecil.Cil.Code.Ldstr when ins.Operand is string literal:
                                    strings.Add(new { offset = ins.Offset, value = literal });
                                    stringCount++;
                                    break;
                                case Mono.Cecil.Cil.Code.Ldc_I4:
                                case Mono.Cecil.Cil.Code.Ldc_I4_S:
                                case Mono.Cecil.Cil.Code.Ldc_I8:
                                case Mono.Cecil.Cil.Code.Ldc_R4:
                                case Mono.Cecil.Cil.Code.Ldc_R8:
                                    constants.Add(new { offset = ins.Offset, opcode = ins.OpCode.Name, value = Number(ins.Operand) });
                                    constantCount++;
                                    break;
                                case Mono.Cecil.Cil.Code.Call:
                                case Mono.Cecil.Cil.Code.Callvirt:
                                case Mono.Cecil.Cil.Code.Newobj:
                                case Mono.Cecil.Cil.Code.Ldftn:
                                    if (ins.Operand is MethodReference callee)
                                    {
                                        calls.Add(new { offset = ins.Offset, kind = ins.OpCode.Name, target = callee.FullName });
                                        callCount++;
                                    }
                                    break;
                                case Mono.Cecil.Cil.Code.Ldfld:
                                case Mono.Cecil.Cil.Code.Stfld:
                                case Mono.Cecil.Cil.Code.Ldsfld:
                                case Mono.Cecil.Cil.Code.Stsfld:
                                    if (ins.Operand is FieldReference field)
                                    {
                                        fields.Add(new { offset = ins.Offset, kind = ins.OpCode.Name, target = field.FullName });
                                    }
                                    break;
                            }
                        }
                        instructionCount += instructions;
                    }

                    methods.Add(new
                    {
                        name = method.Name,
                        full_name = method.FullName,
                        access = Access(method),
                        @static = method.IsStatic,
                        @virtual = method.IsVirtual,
                        @abstract = method.IsAbstract,
                        special_name = method.IsSpecialName,
                        pinvoke = method.IsPInvokeImpl,
                        returns = method.ReturnType.FullName,
                        attributes = Attributes(method.CustomAttributes),
                        parameters = method.Parameters.Select(p => new
                        {
                            name = p.Name,
                            type = p.ParameterType.FullName,
                            by_ref = p.ParameterType.IsByReference,
                            optional = p.IsOptional,
                            has_default = p.HasConstant,
                            @default = p.HasConstant ? Render(p.Constant) : null,
                        }).ToArray(),
                        body = method.HasBody
                            ? new
                            {
                                instructions,
                                max_stack = method.Body.MaxStackSize,
                                exception_handlers = method.Body.ExceptionHandlers.Count,
                                strings,
                                constants,
                                calls,
                                field_access = fields,
                            }
                            : null,
                    });
                }

                types.Add(new
                {
                    full_name = type.FullName,
                    name = type.Name,
                    @namespace = type.Namespace,
                    @public = type.IsPublic || type.IsNestedPublic,
                    @abstract = type.IsAbstract,
                    @sealed = type.IsSealed,
                    @interface = type.IsInterface,
                    @enum = type.IsEnum,
                    base_type = type.BaseType?.FullName,
                    interfaces = type.Interfaces.Select(i => i.InterfaceType.FullName).ToArray(),
                    attributes = Attributes(type.CustomAttributes),
                    enum_values = type.IsEnum
                        ? type.Fields.Where(f => f.IsLiteral)
                            .Select(f => new { name = f.Name, value = Render(f.Constant), underlying = f.FieldType.FullName })
                            .ToArray()
                        : null,
                    fields = type.Fields.Select(f => new
                    {
                        name = f.Name,
                        type = f.FieldType.FullName,
                        @static = f.IsStatic,
                        @readonly = f.IsInitOnly,
                        literal = f.IsLiteral,
                        @const = f.HasConstant ? Render(f.Constant) : null,
                    }).ToArray(),
                    properties = type.Properties.Select(p => new
                    {
                        name = p.Name,
                        type = p.PropertyType.FullName,
                        getter = p.GetMethod is not null,
                        setter = p.SetMethod is not null,
                    }).ToArray(),
                    decompiled_paths = sourceIndex.Lookup(type.Name),
                    methods,
                });
            }

            var payload = new Dictionary<string, object?>
            {
                ["schema"] = Schema,
                ["generator"] = new
                {
                    tool = ToolVersion,
                    cecil = typeof(ModuleDefinition).Assembly.GetName().Version?.ToString(),
                    command = "dotnet run --project Tools/oracle/OracleCapture -- <assembly> <out.json> <type-prefix>...",
                },
                ["assembly"] = new
                {
                    name = module.Assembly.Name.Name,
                    version = module.Assembly.Name.Version?.ToString(),
                    file = Path.GetFileName(assemblyPath),
                    sha256 = assemblySha,
                    bytes = new FileInfo(assemblyPath).Length,
                    mvid = module.Mvid.ToString(),
                },
                ["targets"] = prefixes,
                ["captured_at_utc"] = DateTime.UtcNow.ToString("o"),
                ["mode"] = "il-static-no-execution",
                ["execution"] = new
                {
                    status = "not-run",
                    reason =
                        "CSBlocks.mgp is a mixed-mode Rhino plugin. Loading it outside Rhino fails in " +
                        "Rhino_DotNet.dll initialisation with 0x8007045A (ERROR_DLL_INIT_FAILED), so no vendor " +
                        "method is executed here. IL, metadata, strings, constants and call edges are read directly.",
                },
                ["summary"] = new
                {
                    types = types.Count,
                    methods = methodCount,
                    instructions = instructionCount,
                    strings = stringCount,
                    numeric_constants = constantCount,
                    call_edges = callCount,
                },
                ["types"] = types,
            };

            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            File.WriteAllText(
                outputPath,
                JsonSerializer.Serialize(payload, new JsonSerializerOptions
                {
                    WriteIndented = true,
                    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                }),
                new System.Text.UTF8Encoding(false));

            Console.WriteLine(
                $"types={types.Count} methods={methodCount} instructions={instructionCount} " +
                $"strings={stringCount} constants={constantCount} calls={callCount}");
            Console.WriteLine($"wrote {outputPath}");
        }

        return 0;
    }

    private static string LabRoot()
    {
        string? fromEnv = Environment.GetEnvironmentVariable("LAB_ROOT");
        if (!string.IsNullOrEmpty(fromEnv)) return fromEnv;
        return @"D:\REA-LAB";
    }

    private static string Access(MethodDefinition method)
    {
        if (method.IsPublic) return "public";
        if (method.IsFamily) return "protected";
        if (method.IsAssembly) return "internal";
        if (method.IsFamilyOrAssembly) return "protected internal";
        return "private";
    }

    private static object? Render(object? value) => value switch
    {
        null => null,
        string s => s,
        bool or byte or sbyte or short or ushort or int or uint or long or ulong or float or double or decimal => Number(value),
        TypeReference type => type.FullName,
        CustomAttributeArgument argument => Render(argument.Value),
        IEnumerable<CustomAttributeArgument> many => many.Select(a => Render(a.Value)).ToArray(),
        _ => value.ToString(),
    };

    // NaN and infinities are real IL constants and must stay in the corpus, but
    // JSON has no number form for them, so they are written as named strings.
    private static object? Number(object? value) => value switch
    {
        float f when float.IsNaN(f) || float.IsInfinity(f) => f.ToString("R", System.Globalization.CultureInfo.InvariantCulture),
        double d when double.IsNaN(d) || double.IsInfinity(d) => d.ToString("R", System.Globalization.CultureInfo.InvariantCulture),
        _ => value,
    };

    private static object[] Attributes(IEnumerable<CustomAttribute> attributes) =>
        attributes.Select(a => (object)new
        {
            type = a.AttributeType.FullName,
            arguments = a.ConstructorArguments.Select(x => Render(x.Value)).ToArray(),
            named = a.Properties.Select(p => new { name = p.Name, value = Render(p.Argument.Value) }).ToArray(),
        }).ToArray();

    private static string Sha256(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    // Maps a simple type name to the decompiled files that declare it, so every
    // corpus record points back at the source the port will be written from.
    private sealed class SourceIndex
    {
        private readonly Dictionary<string, string[]> _byName;

        private SourceIndex(Dictionary<string, string[]> byName) => _byName = byName;

        public static SourceIndex Build(string root)
        {
            var map = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            if (Directory.Exists(root))
            {
                foreach (string file in Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories))
                {
                    string name = Path.GetFileNameWithoutExtension(file);
                    if (!map.TryGetValue(name, out List<string>? list))
                        map[name] = list = new List<string>();
                    list.Add(Path.GetRelativePath(Path.GetDirectoryName(root)!, file).Replace('\\', '/'));
                }
            }
            return new SourceIndex(map.ToDictionary(kv => kv.Key, kv => kv.Value.ToArray(), StringComparer.OrdinalIgnoreCase));
        }

        public string[] Lookup(string name) => _byName.TryGetValue(name, out string[]? paths) ? paths : Array.Empty<string>();
    }
}
