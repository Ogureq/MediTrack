import { describe, expect, it } from "vitest";
import { Router } from "../src/router";

interface FakeEnv {
  marker: string;
}

describe("Router", () => {
  it("matches an exact method+path route", async () => {
    const router = new Router<FakeEnv>();
    router.get("/health", () => new Response("ok"));

    const response = await router.handle(new Request("https://example.com/health"), { marker: "x" }, {} as ExecutionContext);
    expect(response).not.toBeNull();
    expect(await response?.text()).toBe("ok");
  });

  it("passes request/env/execCtx through to the handler", async () => {
    const router = new Router<FakeEnv>();
    router.post("/v1/echo", ({ env }) => new Response(env.marker));

    const response = await router.handle(
      new Request("https://example.com/v1/echo", { method: "POST" }),
      { marker: "hello" },
      {} as ExecutionContext
    );
    expect(await response?.text()).toBe("hello");
  });

  it("returns null when no route matches the path", async () => {
    const router = new Router<FakeEnv>();
    router.get("/health", () => new Response("ok"));

    const response = await router.handle(new Request("https://example.com/nope"), { marker: "x" }, {} as ExecutionContext);
    expect(response).toBeNull();
  });

  it("returns null when the path matches but the method doesn't", async () => {
    const router = new Router<FakeEnv>();
    router.get("/health", () => new Response("ok"));

    const response = await router.handle(
      new Request("https://example.com/health", { method: "POST" }),
      { marker: "x" },
      {} as ExecutionContext
    );
    expect(response).toBeNull();
  });

  it("treats a trailing slash as equivalent to the route without one", async () => {
    const router = new Router<FakeEnv>();
    router.get("/v1/usage/me", () => new Response("ok"));

    const response = await router.handle(new Request("https://example.com/v1/usage/me/"), { marker: "x" }, {} as ExecutionContext);
    expect(response).not.toBeNull();
  });

  it("match() is case-insensitive on method", () => {
    const router = new Router<FakeEnv>();
    router.post("/v1/thing", () => new Response("ok"));
    expect(router.match("post", "/v1/thing")).toBeDefined();
    expect(router.match("POST", "/v1/thing")).toBeDefined();
  });
});
