# Issue creation

`factory add <idea>` creates one GitHub issue for later work. It needs a Git
project, GitHub CLI, and authentication with issue-write permission. It needs
no initialized factory, checks, or agent CLI. It changes no project files or Git
state and never starts a job. Use `factory run` separately to process the queue.

## Native invocation

The host saves the exact idea in an exclusively created UTF-8 file without a
BOM. Pass the path through literal arguments and clean up the host-owned input
file afterward. Never interpolate the idea into a command. Caller-supplied
files remain untouched. The helper removes its own temporary JSON payload on
success and failure.

```powershell
& <skill-dir>/scripts/factory.ps1 add -ProjectPath <root> -File <idea-file> -Label factory
```

```sh
bash <skill-dir>/scripts/factory.sh --project <root> add --file <idea-file> --label factory
```

`-Label` and `--label` are optional and default to `factory`, the queue's label.
An override is one literal label. Empty or whitespace-only labels, commas, and
line breaks fail. Use the same label when reading `queue` for custom queues.
The label must already exist. A failed lookup stops creation. Create that label
separately or select an existing one. The helper never creates labels for you.

The helper resolves the repository and host through `gh repo view` in the
project, using the same GitHub context as `queue`. It pins both for subsequent
requests. Check that context before invoking `add` if you use `GH_REPO` or
multiple GitHub hosts.

## Exact issue content

The complete decoded idea is the body, including leading and trailing spaces,
blank lines, CRLF or LF line breaks, and trailing newlines. Quotes, Unicode,
Markdown, leading hyphens, and shell metacharacters remain literal text. NUL
bytes, invalid UTF-8, and a BOM fail. Empty and whitespace-only ideas fail before
any issue-creation request.

The title is the first nonblank LF or CRLF line. Trim surrounding Unicode
whitespace and replace internal tabs with ordinary spaces. Keep the longest
complete Unicode prefix whose UTF-8 encoding is at most 120 bytes. Add no
suffix. Both helpers use Unicode White_Space for blank detection and trimming.
For example, `  Add saved searches  ` produces title `Add saved searches`.
Only the title changes. The body retains that line's original spaces and all
later lines. Long bodies are never shortened. GitHub size errors return to the
caller without a retry.

Composition is deterministic and requires no model call. The helper writes
`title`, `body`, and a one-element `labels` array to a JSON file, then passes
that file to `gh api --input`. Idea text never enters process arguments.

## Result and recovery

Success prints only the HTTPS issue URL on stdout and exits zero. The response
must contain a positive issue number, the matching repository URL, and the
requested label. There is exactly one creation request and no automatic retry.

Missing tools, unreadable input, invalid repository context, authentication
errors, label failures, and rejected requests exit nonzero with diagnostics on
stderr. Install missing tools, check `gh auth status` and `gh repo view`, or
correct the reported input or label problem before another attempt.
The helper disables API debug logging for these requests so diagnostics do not
include request headers or the idea payload.

After submission, a timeout, connection error, or invalid response can leave an
issue on GitHub. Do not blindly retry. Inspect recent issues in the resolved
repository, including closed issues, and compare both title and body first.
You can use `gh issue list --repo <host/owner/repo> --state all` or the repository's
issue page. Each explicit invocation is a new creation attempt. There is no
automatic duplicate search.

If GitHub creates an issue but omits its label, the helper fails and reports the
existing issue URL. Correct that issue's label separately before running the
queue. Do not create a second issue to repair it.
