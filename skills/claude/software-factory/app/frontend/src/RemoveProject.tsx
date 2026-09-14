import React, { useEffect, useRef, useState } from "react";

type Project = { id: string; name: string };

export function RemoveProject({
  project,
  close,
  removed,
}: {
  project: Project;
  close: () => void;
  removed: (name: string) => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [token, setToken] = useState("");
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
        if (!controller.signal.aborted) setToken(result.token);
      })
      .catch((e) => {
        if (!controller.signal.aborted) setError(String(e));
      });
    return () => {
      controller.abort();
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (pending || !token) return;
    setPending(true);
    setError("");
    try {
      const response = await fetch(
        "/api/projects/" + encodeURIComponent(project.id),
        { method: "DELETE", headers: { "X-Factory-Token": token } },
      );
      if (response.status === 204) {
        removed(project.name);
        return;
      }
      const result = await response.json();
      throw new Error(result.error || "Could not remove the project.");
    } catch (e) {
      setError(String(e));
      setPending(false);
    }
  }

  return (
    <dialog
      ref={dialog}
      className="add-project"
      aria-labelledby="remove-project-title"
      onCancel={(event) => {
        event.preventDefault();
        if (!pending) close();
      }}
    >
      <form onSubmit={submit} aria-busy={pending}>
        <h2 id="remove-project-title">Remove {project.name}?</h2>
        <p>
          This removes the project from this dashboard. Its files, Software
          Factory installation, and history will be kept.
        </p>
        {error && (
          <p role="alert" className="notification is-danger">
            {error}
          </p>
        )}
        {pending && <p role="status">Removing project...</p>}
        <div className="buttons">
          <button
            type="button"
            className="button"
            disabled={pending}
            onClick={close}
          >
            Cancel
          </button>
          <button
            type="submit"
            className="button is-link"
            disabled={pending || !token}
          >
            Remove
          </button>
        </div>
      </form>
    </dialog>
  );
}
