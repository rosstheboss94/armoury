import React, { useEffect, useRef, useState } from "react";

type Settings = {
  available: boolean;
  directory: string | null;
  token: string;
  guidance: string;
};

export function AddProject({
  close,
  added,
}: {
  close: () => void;
  added: (name: string, existing: boolean) => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [settings, setSettings] = useState<Settings | null>(null);
  const [path, setPath] = useState("");
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    dialog.current?.showModal();
    const controller = new AbortController();
    void fetch("/api/project-registration", { signal: controller.signal })
      .then(async (response) => {
        const result = await response.json();
        if (!response.ok)
          throw new Error(result.error || "Could not load project settings.");
        if (!controller.signal.aborted) setSettings(result);
      })
      .catch((e) => {
        if (!controller.signal.aborted) setError(String(e));
      });
    return () => {
      controller.abort();
      opener?.focus();
    };
  }, []);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (pending || !settings?.available || !path.trim()) return;
    setPending(true);
    setError("");
    try {
      const response = await fetch("/api/projects", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Factory-Token": settings.token,
        },
        body: JSON.stringify({ path: path.trim() }),
      });
      const result = await response.json();
      if (!response.ok)
        throw new Error(result.error || "Could not add the project.");
      added(result.project.name, result.already_registered);
    } catch (e) {
      setError(String(e));
      setPending(false);
    }
  }

  return (
    <dialog
      ref={dialog}
      className="add-project"
      aria-labelledby="add-project-title"
      onCancel={(event) => {
        event.preventDefault();
        if (!pending) close();
      }}
    >
      <form onSubmit={submit} aria-busy={pending}>
        <h2 id="add-project-title">Add project</h2>
        {!settings && !error && (
          <p role="status">Loading project settings...</p>
        )}
        {settings?.available ? (
          <>
            <p>
              Projects directory:{" "}
              <span className="path">{settings.directory}</span>
            </p>
            <label htmlFor="project-directory">Project directory</label>
            <input
              id="project-directory"
              className="input"
              autoFocus
              required
              value={path}
              disabled={pending}
              onChange={(event) => setPath(event.target.value)}
              aria-describedby="project-directory-help"
            />
            <p id="project-directory-help" className="muted">
              Enter an existing folder's full path or a path relative to the
              projects directory. Software Factory will be installed if missing.
            </p>
          </>
        ) : (
          settings && <p>{settings.guidance}</p>
        )}
        {error && (
          <p role="alert" className="notification is-danger">
            {error}
          </p>
        )}
        {pending && <p role="status">Adding project...</p>}
        <div className="buttons">
          <button
            type="button"
            className="button"
            disabled={pending}
            onClick={close}
          >
            Cancel
          </button>
          {settings?.available && (
            <button
              type="submit"
              className="button is-link"
              disabled={pending || !path.trim()}
            >
              Add project
            </button>
          )}
        </div>
      </form>
    </dialog>
  );
}
