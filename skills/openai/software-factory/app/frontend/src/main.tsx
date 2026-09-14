import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import Markdown from "react-markdown";
import "bulma/css/bulma.min.css";
import "./style.css";
import { RecordData, date, display, duration, timeline } from "./model";
import { AddProject } from "./AddProject";

async function get(path: string, signal?: AbortSignal) {
  const response = await fetch("/api/" + path, { signal });
  const result = await response.json();
  if (!response.ok)
    throw new Error(result.error || `Request failed: ${response.status}`);
  return result;
}

export function usePoll(path: string, revision = 0) {
  const [data, setData] = useState<RecordData | null>(null);
  const [loadedPath, setLoadedPath] = useState("");
  const [error, setError] = useState("");
  const [updated, setUpdated] = useState("");
  useEffect(() => {
    setData(null);
    setError("");
    setUpdated("");
    let controller: AbortController | null = null;
    let alive = true;
    const poll = async () => {
      if (document.hidden || controller) return;
      controller = new AbortController();
      try {
        const result = await get(path, controller.signal);
        if (alive) {
          setData(result);
          setLoadedPath(path);
          setError("");
          setUpdated(new Date().toLocaleTimeString());
        }
      } catch (e) {
        if (alive && !controller.signal.aborted) setError(String(e));
      } finally {
        controller = null;
      }
    };
    void poll();
    const timer = setInterval(poll, 2000);
    const visible = () => {
      if (document.hidden) controller?.abort();
      else void poll();
    };
    document.addEventListener("visibilitychange", visible);
    return () => {
      alive = false;
      clearInterval(timer);
      controller?.abort();
      document.removeEventListener("visibilitychange", visible);
    };
  }, [path, revision]);
  return { data: loadedPath === path ? data : null, error, updated };
}

const tag = (value: unknown) => (
  <span className={"tag status-" + value}>{display(value)}</span>
);
const jump = (parts: string[]) => {
  window.location.hash = parts.map(encodeURIComponent).join("/");
};
function Json({ value }: { value: unknown }) {
  return <pre>{JSON.stringify(value ?? "Unavailable", null, 2)}</pre>;
}

export function Reader({ record }: { record: RecordData }) {
  const [raw, setRaw] = useState(false),
    [current, setCurrent] = useState(false);
  const content = current ? record.current?.content : record.content;
  const hash = current ? record.current?.hash : record.hash;
  return (
    <article className="box reader">
      <h3>{record.file}</h3>
      <div className="reader-controls">
        <label>
          <input
            type="checkbox"
            checked={raw}
            onChange={(e) => setRaw(e.target.checked)}
          />{" "}
          Raw source
        </label>
        {"current" in record && (
          <label>
            <input
              type="checkbox"
              checked={current}
              onChange={(e) => setCurrent(e.target.checked)}
            />{" "}
            Current version
          </label>
        )}
        {record.changed && tag("changed")}
      </div>
      <p className="muted">{hash ? `SHA-256 ${hash}` : ""}</p>
      {content === undefined ? (
        <p>Current file is unavailable.</p>
      ) : raw ? (
        <pre>{content}</pre>
      ) : (
        <div className="content">
          <Markdown
            skipHtml
            components={{
              img: () => null,
              a: ({ children }) => <span>{children}</span>,
            }}
          >
            {content}
          </Markdown>
        </div>
      )}
    </article>
  );
}

function ReaderPanel({ path, close }: { path: string; close: () => void }) {
  const { data, error, updated } = usePoll(path);
  return (
    <>
      <button className="button" onClick={close}>
        Close reader
      </button>
      <p className="muted" role="status">
        Reader {error ? "disconnected" : "connected"} · Last update{" "}
        {updated || "Unavailable"}
      </p>
      {error && (
        <p role="alert" className="notification is-warning">
          {error}
        </p>
      )}
      {data && <Reader record={data} />}
    </>
  );
}

export function App() {
  const [adding, setAdding] = useState(false);
  const [revision, setRevision] = useState(0);
  const [notice, setNotice] = useState("");
  const [route, setRoute] = useState(() =>
    window.location.hash
      .slice(1)
      .split("/")
      .filter(Boolean)
      .map(decodeURIComponent),
  );
  const [search, setSearch] = useState(""),
    [filter, setFilter] = useState("all");
  const [phaseId, setPhaseId] = useState("");
  const [reader, setReader] = useState("");
  useEffect(() => {
    const change = () => {
      setRoute(
        window.location.hash
          .slice(1)
          .split("/")
          .filter(Boolean)
          .map(decodeURIComponent),
      );
      setPhaseId("");
      setReader("");
      setSearch("");
      setFilter("all");
      setAdding(false);
      setNotice("");
    };
    window.addEventListener("hashchange", change);
    return () => window.removeEventListener("hashchange", change);
  }, []);
  const [project, session, workflow] = route;
  const base = `projects/${encodeURIComponent(project || "")}`;
  const path = !project
    ? "projects"
    : session === "specs"
      ? base + "/specs"
      : !session
        ? base + "/sessions"
        : !workflow
          ? base + "/sessions/" + encodeURIComponent(session)
          : base + "/workflows/" + encodeURIComponent(workflow);
  const { data, error, updated } = usePoll(path, revision);
  const read = (path: string) => setReader(path);
  const phase = data?.attempts?.find((a: RecordData) => a.id === phaseId);
  const blocks = timeline(data?.attempts || []);
  const trackWidth = Math.max(820, ...blocks.map((a) => a.left + a.width + 20));
  const events =
    data?.events?.filter((e: RecordData) => e.attempt_id === phaseId) || [];
  const title = !project
    ? "Projects"
    : session === "specs"
      ? "Specifications"
      : !session
        ? "Sessions"
        : !workflow
          ? data?.task || "Session"
          : data?.request?.task || "Workflow";
  return (
    <>
      <header>
        <a href="#" className="brand">
          Software factory
        </a>
        <nav aria-label="Breadcrumb">
          <button onClick={() => jump([])}>Projects</button>
          {route.map((part, i) => (
            <React.Fragment key={i}>
              <span>/</span>
              <button
                aria-current={i === route.length - 1 ? "page" : undefined}
                onClick={() => jump(route.slice(0, i + 1))}
              >
                {part === "specs" ? part : part.slice(0, 8)}
              </button>
            </React.Fragment>
          ))}
        </nav>
        <span className="connection" role="status">
          {error ? "Disconnected" : updated ? "Connected" : "Connecting"} ·{" "}
          {updated ? `Updated ${updated}` : "No update yet"}
        </span>
      </header>
      <main>
        <div className="heading">
          <div>
            <p className="eyebrow">LOCAL WORKSPACE</p>
            <h1>{title}</h1>
          </div>
          {!project && (
            <button className="button is-link" onClick={() => setAdding(true)}>
              Add project
            </button>
          )}
          {project && !session && (
            <button className="button" onClick={() => jump([project, "specs"])}>
              Browse specifications
            </button>
          )}
        </div>
        {adding && !project && (
          <AddProject
            close={() => setAdding(false)}
            added={(name, existing) => {
              setAdding(false);
              setNotice(
                existing
                  ? `${name} is already registered.`
                  : `${name} was added.`,
              );
              setRevision((value) => value + 1);
            }}
          />
        )}
        {notice && <p role="status">{notice}</p>}
        <p className="muted">
          Read-only records. A started phase does not confirm an agent is still
          running.
        </p>
        {error && (
          <div className="notification is-danger" role="alert">
            {error}. Showing the last received records when available.
          </div>
        )}
        {data && data.errors?.length > 0 && (
          <details className="box">
            <summary>{data.errors.length} unavailable records</summary>
            <Json value={data.errors} />
          </details>
        )}
        {!data && !error && <p>Loading records...</p>}
        {data && !project && (
          <div className="cards">
            {data.items.map((p: RecordData) => (
              <button
                className="box project-card"
                key={p.id}
                disabled={!p.available}
                onClick={() => jump([p.id])}
              >
                <div className="card-top">
                  <span className="project-icon">▦</span>
                  {tag(p.available ? "available" : "unavailable")}
                </div>
                <h2>{p.name}</h2>
                <p className="path">{p.factory}</p>
                <div className="metrics">
                  <span>{p.active_sessions ?? "—"} open sessions</span>
                  <span>{p.blocked_workflows ?? "—"} blocked workflows</span>
                </div>
                <p className="muted">Last activity {date(p.updated_at)}</p>
                {p.error && <p>{p.error}</p>}
              </button>
            ))}
            {!data.items.length && (
              <p>
                No projects registered. Use Add project to add a local project.
              </p>
            )}
          </div>
        )}
        {data && project && !session && (
          <>
            <div className="filters">
              <input
                className="input"
                aria-label="Search sessions"
                placeholder="Search sessions"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
              <select
                className="input"
                aria-label="Session status"
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
              >
                {["all", "open", "blocked", "complete", "empty"].map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
            </div>
            <div className="cards">
              {data.items
                .filter(
                  (s: RecordData) =>
                    s.task?.toLowerCase().includes(search.toLowerCase()) &&
                    (filter === "all" || s.status === filter),
                )
                .map((s: RecordData) => (
                  <button
                    className="box"
                    key={s.id}
                    onClick={() => jump([project, s.id])}
                  >
                    <div className="card-top">
                      {tag(s.status)}
                      <span>{s.workflows.length} workflows</span>
                    </div>
                    <h2>{s.task}</h2>
                    <p className="muted">{date(s.updated_at)}</p>
                    <p>
                      Current activity: {display(s.workflows.at(-1)?.phase)}
                    </p>
                    <div className="preview">
                      {s.workflows.map((w: RecordData) => (
                        <span key={w.id}>
                          {w.route?.mode} / {w.phase}
                        </span>
                      ))}
                    </div>
                    {s.legacy && (
                      <p>
                        Legacy grouping. Timing and context history unavailable.
                      </p>
                    )}
                  </button>
                ))}
            </div>
            {!data.items.length && <p>No sessions recorded yet.</p>}
          </>
        )}
        {data && session === "specs" && (
          <>
            <p>
              Current project files. This browser does not record or imply a
              workflow read.
            </p>
            <div className="box spec-list">
              {data.items.map((file: string) => (
                <button
                  key={file}
                  onClick={() =>
                    read(base + "/spec?file=" + encodeURIComponent(file))
                  }
                >
                  {file}
                </button>
              ))}
              {!data.items.length && <p>No Markdown specifications.</p>}
            </div>
          </>
        )}
        {data && session && session !== "specs" && !workflow && (
          <>
            <p className="goal">{data.goal}</p>
            {data.legacy && (
              <p>
                Legacy compatibility grouping. Historical timings and context
                are unavailable.
              </p>
            )}
            <div className="workflow-list">
              {data.workflows.map((w: RecordData) => (
                <button
                  className="box"
                  key={w.id}
                  onClick={() => jump([project, session, w.id])}
                >
                  <div className="card-top">
                    <h2>
                      {w.route?.operation} / {w.route?.mode}
                    </h2>
                    {tag(w.blocker ? "blocked" : w.phase)}
                  </div>
                  <p>
                    {display(w.identity?.branch)} · Review round {w.round}
                  </p>
                  <p className="muted">
                    {date(w.created_at)} to {date(w.updated_at)}
                  </p>
                  <div className="preview">
                    {(w.attempts || []).map((a: RecordData) => (
                      <span key={a.id}>{a.phase}</span>
                    ))}
                  </div>
                  <p>
                    {(w.checks || [])
                      .map((c: RecordData) => `${c.name}: ${c.status}`)
                      .join(" · ") || "Checks unavailable"}
                  </p>
                </button>
              ))}
            </div>
            {!data.workflows.length && <p>No workflows in this session.</p>}
          </>
        )}
        {data && workflow && (
          <>
            <div className="gates">
              {tag(data.phase)}
              <span>
                Local review:{" "}
                {data.reviewed ? display(data.gate) : "Unavailable"}
              </span>
              <span>
                Publication eligible: {display(data.publication_eligible)}
              </span>
              <span>PR ready: {display(data.ready)}</span>
              <span>Round {data.round}</span>
            </div>
            {data.blocker && (
              <p className="notification is-warning">{data.blocker}</p>
            )}
            {data.legacy ? (
              <div className="box">
                <p>
                  Legacy workflow. Phase timing and specification context
                  history are unavailable.
                </p>
                <details>
                  <summary>Preserved history</summary>
                  <Json value={data.history} />
                </details>
              </div>
            ) : (
              <div className="timeline" aria-label="Workflow timeline">
                <div className="timeline-caption">
                  Recorded phase attempts · short blocks widened for readability
                  · select for exact timing and evidence
                </div>
                {[
                  ...new Set<string>(
                    (data.attempts || []).map((a: RecordData) => a.role),
                  ),
                ].map((role) => (
                  <div className={"lane role-" + role} key={role}>
                    <div className="lane-label">
                      <strong>{role}</strong>
                      <span>
                        {display(data.request?.roles?.[role + "_observed"])}
                      </span>
                    </div>
                    <div className="track" style={{ minWidth: trackWidth }}>
                      {blocks
                        .filter((a) => a.role === role)
                        .map((a) => (
                          <button
                            className="phase-block"
                            key={a.id}
                            aria-pressed={phaseId === a.id}
                            style={{
                              left: a.left,
                              width: a.width,
                            }}
                            onClick={() =>
                              setPhaseId(phaseId === a.id ? "" : a.id)
                            }
                            title={`${a.phase}, round ${a.round}, ${a.status}`}
                          >
                            <strong>
                              {a.phase} · {a.round}
                            </strong>
                            <span>{duration(a)}</span>
                            <small>{a.status}</small>
                          </button>
                        ))}
                    </div>
                  </div>
                ))}
              </div>
            )}
            {phase && (
              <section className="box phase-detail">
                <h2>
                  {phase.phase} · Round {phase.round}
                </h2>
                <button
                  className="delete"
                  aria-label="Close phase details"
                  onClick={() => setPhaseId("")}
                />
                <p>
                  {tag(phase.status)} {date(phase.started_at)} to{" "}
                  {date(phase.ended_at)} · Duration {duration(phase)}
                </p>
                <p>
                  Requested model: {display(phase.requested_model)} · Observed
                  model: {display(phase.observed_model)}
                </p>
                <details open>
                  <summary>Assignment</summary>
                  <Json value={phase.assignment} />
                </details>
                <h3>Specs used</h3>
                <p className="muted">
                  Context supplied to the agent. This does not prove
                  understanding.
                </p>
                {events
                  .filter((e: RecordData) => e.kind === "context_supplied")
                  .map((e: RecordData) => (
                    <button
                      className="spec-row"
                      key={e.id}
                      onClick={() =>
                        read(
                          base + "/workflows/" + workflow + "/context/" + e.id,
                        )
                      }
                    >
                      {e.file}
                      <small>
                        {e.hash.slice(0, 12)} · {date(e.at)} · {e.role}
                      </small>
                    </button>
                  ))}
                {!events.some(
                  (e: RecordData) => e.kind === "context_supplied",
                ) && <p>No specification context recorded.</p>}
                <details>
                  <summary>Events, checks, findings, and outputs</summary>
                  <Json value={events} />
                </details>
              </section>
            )}
          </>
        )}
        {reader && (
          <ReaderPanel key={reader} path={reader} close={() => setReader("")} />
        )}
      </main>
    </>
  );
}

if (document.getElementById("root"))
  createRoot(document.getElementById("root")!).render(<App />);
