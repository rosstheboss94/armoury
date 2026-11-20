"""Loopback dashboard reads and explicit local project registration."""

import os
import json
import secrets
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware

from records import Records, FactoryError
from registration import Registration, RegistrationConflict, ProjectDirectory
from starlette.concurrency import run_in_threadpool


def create_app(root, token="test", configuration=None, single_factory=None, projects_directory=None, projects_mount=None, registry_directory=None):
    settings = configuration or {}
    projects_directory = projects_directory or settings.get("projects_directory")
    projects_mount = projects_mount or settings.get("projects_mount")
    registry_directory = registry_directory or settings.get("registry_directory") or Path(root) / "state/dashboard"
    directory = ProjectDirectory(projects_directory, projects_mount) if projects_directory else None
    registration = Registration(root, registry_directory, directory)
    records = Records(root, configuration, single_factory, registration)
    write_token = secrets.token_urlsafe(32)
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=["127.0.0.1", "localhost", "testserver"])

    @app.middleware("http")
    async def access(request: Request, call_next):
        path = request.url.path.rstrip("/")
        adding = request.method == "POST" and path == "/api/projects"
        removing = request.method == "DELETE" and path.startswith("/api/projects/") and path.count("/") == 3
        if request.method not in ("GET", "HEAD") and not adding and not removing:
            return JSONResponse({"error": "Dashboard is read-only."}, status_code=405)
        origin = request.headers.get("origin")
        if origin and origin != str(request.base_url).rstrip("/"):
            return JSONResponse({"error": "Cross-origin access is unavailable."}, status_code=403)
        if adding or removing:
            if origin != str(request.base_url).rstrip("/") or not secrets.compare_digest(request.headers.get("x-factory-token", ""), write_token):
                action = "adding" if adding else "removing"
                return JSONResponse({"error": f"Refresh the page before {action} a project."}, status_code=403)
            if adding and request.headers.get("content-type", "").split(";")[0] != "application/json":
                return JSONResponse({"error": "Send a JSON project path."}, status_code=415)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'"
        response.headers["Cache-Control"] = "no-store"
        return response

    for exception in (FactoryError, OSError, ValueError, KeyError, TypeError):
        async def record_error(request, exc):
            return JSONResponse({"error": str(exc)}, status_code=404)
        app.add_exception_handler(exception, record_error)

    @app.get("/api/identity")
    def identity():
        return {"application": "software-factory-dashboard", "version": 1,
                "host": configuration["host"] if configuration else str(Path(root).resolve()), "token": token,
                **({"runtime": "docker", "fingerprint": configuration["fingerprint"]} if configuration else {})}

    @app.get("/api/projects")
    def projects():
        return records.projects()

    @app.get("/api/project-registration")
    def registration_settings():
        return {"available": directory is not None, "directory": str(directory.host) if directory else None,
                "token": write_token,
                "guidance": "Set FACTORY_PROJECTS_DIRECTORY to an existing parent folder and recreate the Compose service." if single_factory else
                "Restart the launcher with --projects-directory followed by an existing parent folder."}

    @app.post("/api/projects")
    async def add_project(request: Request):
        try:
            payload = await request.json()
            if not isinstance(payload, dict) or set(payload) != {"path"} or not isinstance(payload["path"], str):
                return JSONResponse({"error": "Supply a project path as text."}, status_code=400)
            return await run_in_threadpool(registration.add, payload["path"])
        except RegistrationConflict as exc:
            return JSONResponse({"error": str(exc)}, status_code=409)
        except PermissionError:
            return JSONResponse({"error": "The dashboard cannot write this project or its registry. Check folder permissions and FACTORY_USER for Docker."}, status_code=403)
        except (FactoryError, ValueError) as exc:
            return JSONResponse({"error": str(exc)}, status_code=400)
        except OSError as exc:
            return JSONResponse({"error": f"Could not add the project. Any completed installation is retained; retry after fixing the filesystem error: {exc}"}, status_code=409)

    @app.delete("/api/projects/{project_id}")
    async def remove_project(project_id: str):
        try:
            await run_in_threadpool(registration.remove, project_id, {p["id"] for p in records.sources()})
            return Response(status_code=204)
        except RegistrationConflict as exc:
            return JSONResponse({"error": str(exc)}, status_code=409)
        except PermissionError:
            return JSONResponse({"error": "The dashboard cannot write the project registry. Check folder permissions and FACTORY_USER for Docker."}, status_code=403)
        except FactoryError as exc:
            if str(exc) == "Project is not registered.":
                return JSONResponse({"error": str(exc)}, status_code=404)
            return JSONResponse({"error": str(exc)}, status_code=409)
        except OSError as exc:
            return JSONResponse({"error": f"Could not update the project registry: {exc}"}, status_code=409)

    @app.get("/api/projects/{project_id}/sessions")
    def sessions(project_id: str):
        return records.sessions(project_id)

    @app.get("/api/projects/{project_id}/sessions/{session_id}")
    def session(project_id: str, session_id: str):
        for item in records.sessions(project_id)["items"]:
            if item["id"] == session_id:
                return item
        raise FactoryError("Session is unavailable.")

    @app.get("/api/projects/{project_id}/workflows")
    def workflows(project_id: str):
        return records.workflows(project_id)

    @app.get("/api/projects/{project_id}/workflows/{run_id}")
    def workflow(project_id: str, run_id: str):
        return records.workflow(project_id, run_id)

    @app.get("/api/projects/{project_id}/workflows/{run_id}/phases/{attempt_id}")
    def phase(project_id: str, run_id: str, attempt_id: str):
        return records.phase(project_id, run_id, attempt_id)

    @app.get("/api/projects/{project_id}/workflows/{run_id}/context/{event_id}")
    def context(project_id: str, run_id: str, event_id: str):
        return records.context(project_id, run_id, event_id)

    @app.get("/api/projects/{project_id}/specs")
    def specs(project_id: str):
        return records.specs(project_id)

    @app.get("/api/projects/{project_id}/spec")
    def spec(project_id: str, file: str):
        return records.current_spec(project_id, file)

    assets = Path(root) / "app/frontend/dist"
    if assets.is_dir():
        app.mount("/", StaticFiles(directory=assets, html=True), name="dashboard")
    return app


configuration_path = os.environ.get("FACTORY_DASHBOARD_CONFIG")
configuration = json.loads(Path(configuration_path).read_text(encoding="utf-8")) if configuration_path else None
app = create_app(os.environ.get("FACTORY_DASHBOARD_ROOT", str(Path(__file__).resolve().parents[2])),
                 os.environ.get("FACTORY_DASHBOARD_TOKEN", "unavailable"), configuration,
                 os.environ.get("FACTORY_DASHBOARD_SINGLE_FACTORY"),
                 os.environ.get("FACTORY_PROJECTS_DIRECTORY"), os.environ.get("FACTORY_PROJECTS_MOUNT"),
                 os.environ.get("FACTORY_DASHBOARD_REGISTRY"))
