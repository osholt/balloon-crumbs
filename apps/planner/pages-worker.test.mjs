import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workerSource = await readFile(new URL("./_worker.js", import.meta.url), "utf8");
const worker = await import(
  `data:text/javascript;base64,${Buffer.from(workerSource).toString("base64")}`
);

test("only bounded relay and provider paths are proxied", () => {
  for (const pathname of [
    "/api/v1/plans",
    "/health/live",
    "/weather/v1/forecast",
    "/maps/styles/balloon-crumbs.json",
    "/maps/basemap/7/63/42.pbf",
    "/maps/fonts/Noto/0-255.pbf",
    "/maps/openaip/7/63/42.png",
  ]) {
    assert.equal(worker.isOracleProxyPath(pathname), true, pathname);
  }

  for (const pathname of [
    "/health/ready",
    "/metrics",
    "/weather/v1/forecast/extra",
    "/maps/other/example",
    "/plan/",
  ]) {
    assert.equal(worker.isOracleProxyPath(pathname), false, pathname);
  }
});

test("unrecognised backend paths cannot fall through to the static site", async () => {
  for (const pathname of [
    "/health/ready",
    "/metrics",
    "/weather/v1/forecast/extra",
    "/maps/other/example",
  ]) {
    assert.equal(worker.isReservedBackendPath(pathname), true, pathname);
    const response = await worker.default.fetch(
      new Request(`https://balloon-crumbs.pages.dev${pathname}`),
      { ASSETS: { fetch: assert.fail } },
    );
    assert.equal(response.status, 404, pathname);
  }
});

test("the proxy preserves the bounded path and query on the Oracle origin", () => {
  assert.equal(
    worker.oracleUrl(
      "https://balloon-crumbs.pages.dev/weather/v1/forecast?latitude=51.5&longitude=-0.1",
    ),
    "https://relay.balloon-crumbs.tailendcharlie.app/weather/v1/forecast?latitude=51.5&longitude=-0.1",
  );
});

test("the API proxy preserves a POST body without forwarding Pages cookies", async () => {
  const originalFetch = globalThis.fetch;
  let upstreamRequest;
  globalThis.fetch = async (request) => {
    upstreamRequest = request;
    return new Response("created", { status: 201 });
  };

  try {
    const response = await worker.default.fetch(
      new Request("https://balloon-crumbs.pages.dev/api/v1/plans", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Cookie: "pages-session=private",
        },
        body: JSON.stringify({ name: "smoke", gpx: "<gpx/>" }),
      }),
      { ASSETS: { fetch: assert.fail } },
    );

    assert.equal(response.status, 201);
    assert.equal(
      upstreamRequest.url,
      "https://relay.balloon-crumbs.tailendcharlie.app/api/v1/plans",
    );
    assert.equal(upstreamRequest.headers.get("cookie"), null);
    assert.deepEqual(await upstreamRequest.json(), {
      name: "smoke",
      gpx: "<gpx/>",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("the associated-domain planner path serves the planner shell", async () => {
  let requestedPath;
  const response = await worker.default.fetch(
    new Request("https://balloon-crumbs.pages.dev/planner.html?code=ABCD1234"),
    {
      ASSETS: {
        async fetch(request) {
          requestedPath = new URL(request.url).pathname;
          return new Response("planner", {
            headers: { "Content-Type": "text/html" },
          });
        },
      },
    },
  );

  assert.equal(requestedPath, "/index.html");
  assert.equal(await response.text(), "planner");
  assert.equal(response.headers.get("X-Frame-Options"), "DENY");
});

test("the old Pages planner path redirects to the root planner URL", async () => {
  const response = await worker.default.fetch(
    new Request("https://balloon-crumbs.pages.dev/plan/?example=yes"),
    { ASSETS: { fetch: assert.fail } },
  );

  assert.equal(response.status, 308);
  assert.equal(response.headers.get("Location"), "https://balloon-crumbs.pages.dev/?example=yes");
});
