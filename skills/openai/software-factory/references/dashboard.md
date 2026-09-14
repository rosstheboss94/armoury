# Factory dashboard

Both model packages include a local dashboard. Run
`python .agents/skills/software-factory/scripts/dashboard.py` when asked to open it.
The default runtime is Docker. Host Python 3.10 or newer and a local Docker
engine with Compose and Linux containers are required. The launcher builds the
UI and installs application dependencies inside Docker, then opens the browser.
It never installs host Python or Node packages in Docker mode. Image builds use
only declared application inputs, excluding project records and local environments.
Images are cached by their build inputs and rebuilt when those inputs change.

Use `--runtime native` explicitly to use the previous local environment setup.
Native mode requires Node.js 20.19 or newer and installs dependencies beneath the
factory. Docker failures never cause an automatic switch to native mode.

The default host port is 4601, published only on `127.0.0.1`. An occupied port
makes the launcher choose an available port. Each canonical dashboard host owns
one container. The launcher verifies Docker ownership labels, configuration,
image identity, health, and HTTP identity before reuse. Changes to application
inputs or project mounts replace that host's managed container.

Use `--status` to inspect the managed Docker container and `--stop` to remove it.
These options preserve records and cached images. Logs are available through
`docker logs <container-name>`. The launcher returns the container name.
Build logs, generated Compose configuration, and container path mappings live
under `.runtime/docker-dashboard/`. Metadata lives in `state/dashboard/docker-server.json`.
Existing native servers and environments are preserved when switching to Docker.

Pass repeated `--project <project-directory>` arguments to register selected
projects. A factory directory is also accepted. Use `--root <host-factory>` to
choose the factory that owns the registration list. Keep using that host when
adding projects. Registration resolves worktree links to their canonical factory.
It never scans for projects. Unavailable registered projects stay listed.

The container mounts canonical factory directories read-only at paths based on
project IDs. It reads current host records while the controller continues writing
them locally. Host paths remain unchanged in saved records and in the UI.
Rerun the launcher after adding projects or making an unavailable directory
accessible. This reconciles the container's mounts. Remote Docker engines are
unsupported because the records belong to the local filesystem.

## Direct Docker Compose startup

After reinstalling the factory, run from the project root:

```powershell
docker compose -f .agents/skills/software-factory/compose.yaml up --build -d --wait
```

Open `http://localhost:4601`. Stop it with:

```powershell
docker compose -f .agents/skills/software-factory/compose.yaml down
```

This standalone Compose service reads the factory beside its Compose file.
It needs no launcher-generated configuration. It discovers the factory's existing
`state/project.json`, including one created after startup. An unused factory has
an empty project list until the agent creates a workflow or registers the project.
Without a configured projects directory, it never changes project records.

Set `FACTORY_PORT` to choose another host port and `FACTORY_DIRECTORY` to mount
another canonical factory directory. On Linux, set `FACTORY_USER` to your numeric
UID and GID if the default container user cannot read the records. For example,
use `export FACTORY_USER="$(id -u):$(id -g)"` in Bash. Use Compose's `-p` option
with distinct names for multiple standalone instances.

The Python launcher remains the option for several registered projects and
automatic port selection. Its `--status` and `--stop` options manage its own
containers; use Compose commands for the standalone service.

## Add projects in the browser

Configure one existing parent directory to enable Add project. For the launcher,
pass `--projects-directory <absolute-parent-directory>` with either runtime.
For direct Compose, set `FACTORY_PROJECTS_DIRECTORY` to the absolute host path
before starting or recreating the service. Native servers also accept that
environment variable. No parent directory is chosen automatically.

On Projects, select Add project and enter an existing folder's absolute host
path or a path relative to that parent. Missing factories receive the same
model package as the dashboard. Existing factories are registered without an
upgrade. Installation does not create Git repositories, workflows, discovery
links, or project folders. Existing records and specifications remain intact.

Docker mounts the configured parent writable at `/workspace` and the dashboard
host's `state/dashboard` directory writable at `/registry`. The rest of the
container filesystem stays read-only. Use `FACTORY_USER` with your numeric UID
and GID on Linux when the default Compose user cannot write those directories.
Ensure the host's `state/dashboard` directory exists and is writable before
starting Compose. The launcher uses the current Linux user's UID and GID.
The projects parent must contain every new project's canonical factory.

Browser registrations appear immediately and survive restarts. Host paths remain
in saved identities, so host controller commands can use installed projects.
Paths outside the configured parent and incomplete installations report errors.
If installation succeeds but registration fails, the installation remains and
adding the same folder again retries registration. Existing factory links must
resolve within the configured parent; otherwise enter the canonical project path.
Changing the configured parent requires restarting the dashboard.

## Sessions and context

Create a feature session with the controller's `session --input <request.json>`
command. Supply `task` and optionally `goal`. To reuse it, supply `session_id`.
Include that `session_id` in each related workflow's start request. A start without
one creates a separate session. Retain this identifier in handoffs and resumptions.
Branch names alone do not establish a shared task.

For each specification needed during a monitored phase, call
`context-read --run <workflow-uuid> --input <request.json>` with `file` relative
to `specs/` and the consuming `role`, for example `editor` or `reviewer`.
Read the returned `content` as the specification context for that phase.
The command stores an immutable SHA-256 snapshot before adding its event to the
run. A later file change or deletion does not change that captured context.
The evidence means "context supplied to the agent" and does not prove understanding.
Do not claim that browsing current specifications records a workflow read.

Saved runs record timestamped phase attempts, assignments, results, checks,
review rounds, and controller operations through the existing state lock and
atomic writes. `resume` marks the unfinished attempt interrupted and starts a
new attempt. The exact interruption time remains unavailable. A started event
does not establish that an agent is currently running.

Existing runs retain their UUID and run.json. The dashboard groups each old run
under `legacy-<run-uuid>` and labels this as compatibility grouping. Its missing
timing and context history remain unavailable. File-free operations stay file-free.

## Reading the dashboard

Navigate projects, sessions, workflows, and phase attempts. Select a timeline
block to inspect its assignment, events, checks, findings, outputs, and specs.
The Markdown reader defaults to captured content and offers raw source and a
separate current version. Missing snapshots and malformed records show errors.
The dashboard distinguishes local review, publication eligibility, and PR readiness.
It polls every two seconds while visible and displays connection state and the
last successful update. A disconnected view may retain the last received data.

The API exposes GET reads and a single `POST /api/projects` registration route.
`GET /api/project-registration` returns setup guidance and a per-server write
token. Registration requires same-origin JSON and that token in `X-Factory-Token`.
Identifiers are scoped to registered projects. It never advances phases or invokes Git. Markdown raw
HTML, remote images, and executable links are disabled.

## Packaging and checks

Installation includes `app/` source, `package-lock.json`, and `requirements.lock`.
It excludes runtime environments, node_modules, compiled assets, and caches.
Docker build files are included. The image targets Linux AMD64 and ARM64 and
builds for the local engine architecture. Windows and macOS use Linux containers.
Reinstallation preserves `state/`, including project identities, sessions,
registrations, runs, and snapshots, and preserves `specs/`.

Run `npm test` and `npm run build` inside `app/frontend`. Run
`.runtime/python/Scripts/python.exe -m pytest app/backend/tests` from the factory
on Windows, or `.runtime/python/bin/python -m pytest app/backend/tests` on POSIX.
The repository controller checks remain `python scripts/check-factory.py`.
Run `python scripts/check-installers.py` to check installation and model parity.

Docker acceptance tests run with `FACTORY_DOCKER_TESTS=1` and the backend test
suite. They build isolated fixture images, test live reads, mount permissions,
port conflicts, reuse, rebuilds, project changes, and stop/restart. They remove
their managed containers and retain cached images. Without that environment
variable, the suite runs adapter tests and skips the real engine acceptance test.
