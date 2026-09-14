# Factory workspace

The factory's physical home is `<original-checkout>/.agents/skills/software-factory/`.
Other registered worktrees link their `.agents/skills/software-factory` directory to
that home. All instructions, specs, and delivery records are shared immediately.
Product implementation, tests, and build outputs use the selected worktree.

## Installation

The Armoury PowerShell and Bash installers call the same Python installer.
Both model variants install at the same project-local path. Python 3.10 or newer,
Git for worktree operations, and GitHub CLI for GitHub operations are required.
Installation writes no discovery links, root instruction files, or root config.
To activate it, ask the current agent to read `.agents/skills/software-factory/SKILL.md`.

Reinstallation replaces packaged instructions and scripts. It preserves `specs/`,
`state/`, unrelated local files, and neighboring skills in `.agents/skills/`. Local customization of packaged files should
be preserved elsewhere before updating. Existing standalone installations remain
until the user requests removal. Install into the canonical checkout, not through
a feature worktree's link. Both `.agents` and `.agents/skills` must be physical
directories when installing or registering a project.

The dashboard package also installs application source and dependency
lockfiles. Runtime environments, node_modules, compiled assets, and caches are
excluded. The launcher prepares these beneath the installed factory on demand.
Docker is the dashboard default. It keeps application dependencies and compiled
assets in Docker. Browser registration requires an explicitly configured writable
projects directory. Other project mounts stay read-only. Only explicit native mode
creates local application environments. Reinstallation includes Docker build files.

## Setup and verification

Use `factory.py prepare --input <request.json>` with absolute `project` and
`worktree` paths and verified `branch` and `base`. This creates or reuses the
dedicated feature worktree and shares the factory across registered worktrees.
Verify task ownership before reuse. Preserve changes in the original checkout;
transfer only selected product changes after inspecting staged and untracked
content. The controller does not guess which dirty files belong to a task.

For a user-selected existing checkout, run `share` with `project`. Run `verify`
with `project` during setup and resumption. Missing paths receive links; physical
collisions or links to other targets stop setup before any links are created.
Windows uses a directory junction, with a directory symlink fallback when the
host permits it. POSIX uses directory symlinks.

Keep factory paths out of product commits. The factory's `.gitignore` excludes
`specs/` and `state/` within the physical tree. A POSIX directory symlink can
still appear as an untracked entry in another worktree; never stage it. The
controller excludes that exact factory path when assessing product cleanliness
and rejects it in product commit lists. Installation does not modify Git's
exclude file outside the factory.

## Existing records

During explicitly requested setup of an existing project, run `migrate` with
`project` before creating new specifications. It adopts a single untracked
physical `specs/` tree from a registered checkout or the old shared Git metadata
location, and moves legacy Tldr Markdown into `state/legacy/`. It removes only
verified old spec links and empty former spec directories. Conflicting trees,
tracked records, and unknown links require reconciliation before replacement.
If interrupted, inventory surviving sources and destinations before continuing.

After migration, update checkpoint and specification links to their new
factory-relative owners. Preserve labels, decisions, approvals, closed history,
and review rounds. Check incoming links in product docs and report any that
need changes outside the current authorization. Use Specflow's artifact model
for the records themselves. Migration is not approval to rewrite intent.

## Cleanup

Retain worktrees until cleanup is requested. `cleanup` takes `project`,
`worktree`, `cleanup_authorized: true`, `commits_preserved: true`, and
`preservation_evidence`. Inspect commits and merge evidence, including squash
merges, before supplying these assertions. The command checks registration and
local changes, unlinks only the verified factory link, then invokes non-forced
Git worktree removal. It restores the link if Git refuses removal.

Never remove the canonical checkout through this command. If its relocation is
requested, stop factory writers, verify the exact source and unused destination,
move the whole factory intact, repair every registered link, and verify access
before removing the old checkout. Keep that operation separate from ordinary
feature cleanup. The factory is local shared storage, not a remote backup.
