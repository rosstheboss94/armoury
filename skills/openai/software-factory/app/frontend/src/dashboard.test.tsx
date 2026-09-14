// @vitest-environment jsdom
import React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import { App, Reader, usePoll } from "./main";
import { duration, timeline } from "./model";

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  window.location.hash = "";
});

describe("recorded evidence", () => {
  it("never invents an end time for interrupted or open attempts", () => {
    expect(duration({ started_at: "2026-09-13T10:00:00Z" })).toBe(
      "Unavailable",
    );
    expect(
      duration({
        started_at: "2026-09-13T10:00:00Z",
        ended_at: "2026-09-13T10:00:12Z",
      }),
    ).toBe("12.0s");
    const attempts = timeline([
      {
        id: "a",
        started_at: "2026-09-13T10:00:00Z",
        ended_at: "2026-09-13T10:00:12Z",
      },
      { id: "b", started_at: "2026-09-13T10:00:12Z" },
    ]);
    expect(attempts[0].left).toBe(0);
    expect(attempts[1].left).toBeGreaterThan(
      attempts[0].left + attempts[0].width,
    );
  });
  it("defaults to the captured version and disables executable Markdown", () => {
    const { container } = render(
      <Reader
        record={{
          file: "spec.md",
          content:
            "# Original\n<script>alert(1)</script>\n[x](javascript:alert(1))\n![remote](https://example.com/pixel)",
          current: { content: "# New" },
          changed: true,
        }}
      />,
    );
    expect(screen.getByText("Original")).toBeTruthy();
    expect(container.querySelector("script,img,a")).toBeNull();
    fireEvent.click(screen.getByLabelText("Current version"));
    expect(screen.getByText("New")).toBeTruthy();
    fireEvent.click(screen.getByLabelText("Raw source"));
    expect(screen.getByText("# New")).toBeTruthy();
  });
  it("polls visible data and pauses in hidden tabs", async () => {
    vi.useFakeTimers();
    const fetcher = vi
      .fn()
      .mockResolvedValue({ ok: true, json: async () => ({ items: [] }) });
    vi.stubGlobal("fetch", fetcher);
    let hidden = false;
    vi.spyOn(document, "hidden", "get").mockImplementation(() => hidden);
    function Poll() {
      const result = usePoll("projects");
      return <p>{result.updated}</p>;
    }
    render(<Poll />);
    await act(async () => {
      await Promise.resolve();
    });
    expect(fetcher).toHaveBeenCalledTimes(1);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2000);
    });
    expect(fetcher).toHaveBeenCalledTimes(2);
    hidden = true;
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6000);
    });
    expect(fetcher).toHaveBeenCalledTimes(2);
    hidden = false;
    await act(async () => {
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(fetcher).toHaveBeenCalledTimes(3);
    vi.restoreAllMocks();
  });
  it("navigates projects, sessions, workflows, and phases without reusing another view's records", async () => {
    const workflow = {
      id: "w",
      phase: "review",
      round: 0,
      request: { task: "Implement search" },
      route: { operation: "specflow", mode: "implement" },
      attempts: [
        {
          id: "a",
          role: "editor",
          phase: "work",
          round: 0,
          status: "complete",
          assignment: { task: "Implement search" },
        },
      ],
      events: [],
    };
    const session = {
      id: "s",
      task: "Search feature",
      goal: "Find project records",
      status: "open",
      workflows: [workflow],
    };
    const responses: Record<string, unknown> = {
      "/api/projects": { items: [{ id: "p", name: "Atlas", available: true }] },
      "/api/projects/p/sessions": { items: [session] },
      "/api/projects/p/sessions/s": session,
      "/api/projects/p/workflows/w": workflow,
    };
    vi.stubGlobal(
      "fetch",
      vi.fn(async (path: string) => ({
        ok: true,
        json: async () => responses[path],
      })),
    );
    render(<App />);
    expect(await screen.findByText("Atlas")).toBeTruthy();
    async function navigate(hash: string) {
      await act(async () => {
        window.location.hash = hash;
        window.dispatchEvent(new Event("hashchange"));
      });
    }
    await navigate("p");
    expect(await screen.findByText("Search feature")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Search sessions"), {
      target: { value: "missing" },
    });
    expect(screen.queryByText("Search feature")).toBeNull();
    fireEvent.change(screen.getByLabelText("Search sessions"), {
      target: { value: "" },
    });
    await navigate("p/s");
    expect(await screen.findByText("Find project records")).toBeTruthy();
    await navigate("p/s/w");
    expect(await screen.findByText("Implement search")).toBeTruthy();
    fireEvent.click(screen.getByTitle("work, round 0, complete"));
    expect(screen.getByText("Specs used")).toBeTruthy();
    expect(screen.getByText("No specification context recorded.")).toBeTruthy();
    await navigate("");
    expect(await screen.findByText("Atlas")).toBeTruthy();
    expect(screen.queryByText("Specs used")).toBeNull();
  });
  it("retains the last response on disconnect and recovers on the next poll", async () => {
    vi.useFakeTimers();
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ phase: "work" }),
      })
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValue({ ok: true, json: async () => ({ phase: "review" }) });
    vi.stubGlobal("fetch", fetcher);
    function Poll() {
      const { data, error } = usePoll("workflow");
      return (
        <p>
          {data?.phase} {error}
        </p>
      );
    }
    render(<Poll />);
    await act(async () => {
      await Promise.resolve();
    });
    expect(screen.getByText("work")).toBeTruthy();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2000);
    });
    expect(screen.getByText("work Error: offline")).toBeTruthy();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2000);
    });
    expect(screen.getByText("review")).toBeTruthy();
  });
});
