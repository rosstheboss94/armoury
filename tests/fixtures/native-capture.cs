using System;
using System.IO;
using System.Text;

// Offline executable boundary fixture. It never launches GitHub CLI or another process.
public static class NativeCapture
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string folder = Environment.GetEnvironmentVariable("FACTORY_NATIVE_CAPTURE");
        if (String.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return 99;
        string name = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
        if (name == "agent")
        {
            using (var output = File.Create(Path.Combine(folder, "stdin.bin")))
                Console.OpenStandardInput().CopyTo(output);
            Console.WriteLine("{\"fixture\":true}");
            return 0;
        }
        if (args.Length < 2 || args[0] != "pr") return 98;
        using (var output = new BinaryWriter(File.Create(Path.Combine(folder, args[1] + ".argv")), Encoding.UTF8))
        {
            output.Write(args.Length);
            foreach (string argument in args) output.Write(argument);
        }
        if (Environment.GetEnvironmentVariable("FACTORY_NATIVE_FAIL") == "1")
        {
            Console.WriteLine("fixture stdout diagnostic");
            Console.Error.WriteLine("fixture stderr diagnostic");
            return 23;
        }
        switch (args[1])
        {
            case "list":
                if (!File.Exists(Path.Combine(folder, "created"))) Console.WriteLine("[]");
                else Console.WriteLine("[{\"number\":1,\"url\":\"https://github.com/example/project/pull/1\",\"state\":\"OPEN\",\"isDraft\":true,\"headRefOid\":\"" + Environment.GetEnvironmentVariable("FACTORY_NATIVE_COMMIT") + "\"}]");
                return 0;
            case "create":
                File.WriteAllText(Path.Combine(folder, "created"), "offline");
                Console.WriteLine("https://github.com/example/project/pull/1");
                return 0;
            case "ready":
                File.WriteAllText(Path.Combine(folder, "ready"), "offline");
                return 0;
            default: return 97;
        }
    }
}
