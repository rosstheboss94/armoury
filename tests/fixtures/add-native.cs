using System;
using System.IO;
using System.Text;

// Offline gh.exe. No network or process forwarding is available.
public static class AddNative
{
    static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    static bool Equal(string[] actual, string[] expected)
    {
        if (actual.Length != expected.Length) return false;
        for (int i = 0; i < actual.Length; i++) if (actual[i] != expected[i]) return false;
        return true;
    }
    public static int Main(string[] args)
    {
        Console.OutputEncoding = Utf8;
        string folder = Environment.GetEnvironmentVariable("FACTORY_ADD_FIXTURE");
        if (String.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return 90;
        if (!String.IsNullOrEmpty(Environment.GetEnvironmentVariable("GH_DEBUG"))) return 91;
        string record = Path.Combine(folder, "call." + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(record);
        File.WriteAllLines(Path.Combine(record, "arguments"), args, Utf8);
        using (var writer = new BinaryWriter(File.Create(Path.Combine(record, "argv")), Utf8))
        {
            writer.Write(args.Length);
            foreach (string argument in args) writer.Write(argument);
        }
        string mode = File.ReadAllText(Path.Combine(folder, "mode"), Utf8);
        if (mode == "quote-probe")
        {
            string[] expected;
            using (var reader = new BinaryReader(File.OpenRead(Path.Combine(folder, "expected.argv")), Utf8))
            {
                expected = new string[reader.ReadInt32()];
                for (int i = 0; i < expected.Length; i++) expected[i] = reader.ReadString();
            }
            if (!Equal(args, expected)) return 92;
            Console.Error.WriteLine("Separate stderr diagnostic.");
            Console.Write("exact executable arguments");
            return 0;
        }
        string host = File.ReadAllText(Path.Combine(folder, "host"), Utf8);
        string label = File.ReadAllText(Path.Combine(folder, "label"), Utf8);
        string[] repo = { "repo", "view", "--json", "nameWithOwner,url", "--template", "{{.nameWithOwner}}{{\"\\n\"}}{{.url}}{{\"\\n\"}}" };
        string[] lookup = { "api", "--hostname", host, "-X", "GET", "repos/fixture/project/labels/" + Uri.EscapeDataString(label), "--template", "{{.name}}" };
        string template = "{{printf \"%v\\n%s\\n\" .number .html_url}}{{range .labels}}{{printf \"%s\\n\" .name}}{{end}}";
        if (Equal(args, repo))
        {
            if (mode == "repo-fail" || mode == "auth-fail") { Console.Error.WriteLine("Repository or authentication rejected."); return 23; }
            Console.Write(mode == "invalid-repo" ? "fixture/project\nhttp://github.com/fixture/project\n" : File.ReadAllText(Path.Combine(folder, "context"), Utf8));
            return 0;
        }
        if (Equal(args, lookup))
        {
            if (mode == "missing-label" || mode == "label-fail") { Console.Error.WriteLine("Label lookup rejected."); return 23; }
            Console.WriteLine(label);
            return 0;
        }
        string payload = args.Length == 10 ? args[7] : "";
        string[] post = { "api", "--hostname", host, "-X", "POST", "repos/fixture/project/issues", "--input", payload, "--template", template };
        string temp = Path.GetFullPath(Path.GetTempPath());
        if (Equal(args, post) && Path.GetFileName(payload) == "payload.json" &&
            Path.GetFullPath(payload).StartsWith(temp, StringComparison.OrdinalIgnoreCase) && File.Exists(payload))
        {
            File.WriteAllText(Path.Combine(record, "payload-path"), payload, Utf8);
            File.Copy(payload, Path.Combine(record, "payload.json"));
            if (mode == "post-reject" || mode == "ambiguous")
            {
                // Exceed pipe capacity on both streams to detect sequential draining.
                Console.WriteLine(new string('x', 70000));
                Console.Error.WriteLine(new string('y', 70000));
                Console.Error.WriteLine("Submission diagnostic: caf\u00e9.");
                return 23;
            }
            if (mode == "malformed") Console.WriteLine("invalid response");
            else if (mode == "invalid-url") Console.WriteLine("42\nhttps://attacker.invalid/issues/42\nfactory");
            else if (mode == "missing-returned-label") Console.WriteLine("42\nhttps://github.com/fixture/project/issues/42");
            else
            {
                Console.Error.WriteLine("Successful stderr must not enter response parsing.");
                Console.Write(File.ReadAllText(Path.Combine(folder, "result"), Utf8));
            }
            return 0;
        }
        Console.Error.WriteLine("Unexpected executable fixture arguments.");
        return 92;
    }
}
