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

function responses(post: () => Promise<unknown>, available = true) {
  let registered = false;
  const fetcher = vi.fn(async (path: string, options?: RequestInit) => {
    if (options?.method === "POST") {
      const result = await post();
      registered = true;
      return result;
    }
    return {
      ok: true,
      json: async () =>
        path === "/api/project-registration"
          ? {
              available,
              directory: "C:\\Projects",
              token: "token",
              guidance: "Configure the projects directory.",
            }
          : {
              items: registered
                ? [{ id: "p", name: "Atlas", available: true }]
                : [],
            },
    };
  });
  vi.stubGlobal("fetch", fetcher);
  return fetcher;
}

it("adds a project from the empty page and refreshes immediately", async () => {
  const fetcher = responses(async () => ({
    ok: true,
    json: async () => ({
      project: { name: "Atlas" },
      already_registered: false,
    }),
  }));
  render(<App />);
  fireEvent.click(screen.getByRole("button", { name: "Add project" }));
  fireEvent.change(await screen.findByLabelText("Project directory"), {
    target: { value: "Atlas" },
  });
  fireEvent.click(
    within(screen.getByRole("dialog")).getByRole("button", {
      name: "Add project",
    }),
  );
  expect(await screen.findByText("Atlas was added.")).toBeTruthy();
  expect(await screen.findByText("Atlas")).toBeTruthy();
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(fetcher).toHaveBeenCalledWith(
    "/api/projects",
    expect.objectContaining({
      method: "POST",
      body: '{"path":"Atlas"}',
      headers: expect.objectContaining({ "X-Factory-Token": "token" }),
    }),
  );
});

it("keeps the path after errors and prevents duplicate pending submissions", async () => {
  let finish: (value: unknown) => void = () => {};
  const fetcher = responses(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  render(<App />);
  fireEvent.click(screen.getByRole("button", { name: "Add project" }));
  const input = (await screen.findByLabelText(
    "Project directory",
  )) as HTMLInputElement;
  fireEvent.change(input, { target: { value: "Atlas" } });
  const submit = within(screen.getByRole("dialog")).getByRole("button", {
    name: "Add project",
  });
  fireEvent.click(submit);
  fireEvent.click(submit);
  expect(input.disabled).toBe(true);
  expect(
    fetcher.mock.calls.filter(([, options]) => options?.method === "POST"),
  ).toHaveLength(1);
  finish({
    ok: false,
    json: async () => ({ error: "Folder is unavailable." }),
  });
  expect(await screen.findByRole("alert")).toBeTruthy();
  expect(input.value).toBe("Atlas");
  expect(input.disabled).toBe(false);
  fireEvent(
    screen.getByRole("dialog"),
    new Event("cancel", { bubbles: true, cancelable: true }),
  );
  await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
});

it("shows setup instructions when registration is unconfigured", async () => {
  responses(async () => ({}), false);
  render(<App />);
  fireEvent.click(screen.getByRole("button", { name: "Add project" }));
  expect(
    await screen.findByText("Configure the projects directory."),
  ).toBeTruthy();
  expect(screen.queryByLabelText("Project directory")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).toBeNull();
});
