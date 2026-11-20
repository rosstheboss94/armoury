// @vitest-environment jsdom
import React from "react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
  waitFor,
} from "@testing-library/react";
import { App } from "./main";

beforeEach(() => {
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  window.history.replaceState(null, "", window.location.pathname);
});

function projects(
  items: { id: string; name: string; available: boolean }[],
  del: () => Promise<unknown>,
) {
  let listed = items;
  const fetcher = vi.fn(async (path: string, options?: RequestInit) => {
    if (options?.method === "DELETE") {
      const result = await del();
      if ((result as { status?: number }).status === 204)
        listed = listed.filter((p) => !path.endsWith("/" + p.id));
      return result;
    }
    return {
      ok: true,
      json: async () =>
        path === "/api/project-registration"
          ? {
              available: false,
              directory: null,
              token: "token",
              guidance: "Configure the projects directory.",
            }
          : { items: listed },
    };
  });
  vi.stubGlobal("fetch", fetcher);
  return fetcher;
}

it("removes available, unavailable, and host cards without navigating", async () => {
  projects(
    [
      { id: "host", name: "Host", available: true },
      { id: "gone", name: "Beacon", available: false },
    ],
    async () => ({ status: 204, ok: true, json: async () => ({}) }),
  );
  render(<App />);
  expect(await screen.findByText("Host")).toBeTruthy();
  expect(screen.getByRole("button", { name: "Remove Host" })).toBeTruthy();
  const trash = screen.getByRole("button", { name: "Remove Beacon" });
  trash.focus();
  fireEvent.click(trash);
  expect(window.location.hash).toBe("");
  expect(await screen.findByText("Remove Beacon?")).toBeTruthy();
  expect(
    screen.getByText(
      "This removes the project from this dashboard. Its files, Software Factory installation, and history will be kept.",
    ),
  ).toBeTruthy();
  fireEvent.click(
    within(screen.getByRole("dialog")).getByRole("button", { name: "Cancel" }),
  );
  await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  expect(document.activeElement).toBe(trash);
  expect(screen.getByText("Beacon")).toBeTruthy();
  fireEvent.click(screen.getByText("Host"));
  expect(window.location.hash).toBe("#host");
});

it("announces removal, refreshes the list, and restores focus", async () => {
  const fetcher = projects(
    [{ id: "p", name: "Atlas", available: true }],
    async () => ({ status: 204, ok: true, json: async () => ({}) }),
  );
  render(<App />);
  const trash = await screen.findByRole("button", { name: "Remove Atlas" });
  trash.focus();
  fireEvent.click(trash);
  const submit = await waitFor(() => {
    const button = within(screen.getByRole("dialog")).getByRole("button", {
      name: "Remove",
    });
    if ((button as HTMLButtonElement).disabled) throw new Error("waiting");
    return button;
  });
  fireEvent.click(submit);
  expect(await screen.findByText("Atlas was removed.")).toBeTruthy();
  await waitFor(() => expect(screen.queryByText("Atlas")).toBeNull());
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(fetcher).toHaveBeenCalledWith(
    "/api/projects/p",
    expect.objectContaining({
      method: "DELETE",
      headers: expect.objectContaining({ "X-Factory-Token": "token" }),
    }),
  );
});

it("keeps the card after errors and ignores a second submit", async () => {
  let finish: (value: unknown) => void = () => {};
  const fetcher = projects(
    [{ id: "p", name: "Atlas", available: true }],
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  render(<App />);
  fireEvent.click(await screen.findByRole("button", { name: "Remove Atlas" }));
  const submit = await waitFor(() => {
    const button = within(screen.getByRole("dialog")).getByRole("button", {
      name: "Remove",
    });
    if ((button as HTMLButtonElement).disabled) throw new Error("waiting");
    return button;
  });
  fireEvent.click(submit);
  fireEvent.click(submit);
  expect(
    fetcher.mock.calls.filter(([, options]) => options?.method === "DELETE"),
  ).toHaveLength(1);
  finish({
    ok: false,
    status: 409,
    json: async () => ({ error: "Factory state is locked." }),
  });
  expect(await screen.findByRole("alert")).toBeTruthy();
  expect(screen.getByText("Atlas")).toBeTruthy();
  fireEvent.click(
    within(screen.getByRole("dialog")).getByRole("button", { name: "Remove" }),
  );
  expect(
    fetcher.mock.calls.filter(([, options]) => options?.method === "DELETE"),
  ).toHaveLength(2);
});
