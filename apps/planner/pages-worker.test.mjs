import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workerSource = await readFile(new URL("./_worker.js", import.meta.url), "utf8");
const homeSource = await readFile(new URL("./index.html", import.meta.url), "utf8");
const plannerSource = await readFile(new URL("./planner.html", import.meta.url), "utf8");
const worker = await import(
  `data:text/javascript;base64,${Buffer.from(workerSource).toString("base64")}`
);

test("only bounded relay and provider paths are proxied", () => {
  for (const pathname of [
    "/api/v1/plans",
    "/api/v1/reference/inspire",
    "/health/live",
    "/weather/v1/forecast",
    "/maps/styles/balloon-crumbs.json",
    "/maps/basemap/7/63/42.pbf",
    "/maps/fonts/Noto/0-255.pbf",
    "/maps/openaip/7/63/42.png",
    "/maps/os/outdoor/16/32311/21782.png",
  ]) {
    assert.equal(worker.isOracleProxyPath(pathname), true, pathname);
  }

  for (const pathname of [
    "/health/ready",
    "/metrics",
    "/weather/v1/forecast/extra",
    "/geocode/v1/search",
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
    "/geocode/v1/other",
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

test("place search builds a bounded UK Nominatim query", () => {
  assert.equal(worker.isGeocodePath("/geocode/v1/search"), true);
  assert.equal(worker.isGeocodePath("/geocode/v1/search/extra"), false);
  const url = worker.geocodeSearchUrl(
    "https://balloon-crumbs.pages.dev/geocode/v1/search?q=%20Tuckers%20%20Grave%20",
  );
  assert.equal(url.origin, "https://nominatim.openstreetmap.org");
  assert.equal(url.pathname, "/search");
  assert.equal(url.searchParams.get("q"), "Tuckers Grave");
  assert.equal(url.searchParams.get("format"), "jsonv2");
  assert.equal(url.searchParams.get("limit"), "5");
  assert.equal(url.searchParams.get("countrycodes"), "gb");
  assert.throws(
    () => worker.geocodeSearchUrl("https://balloon-crumbs.pages.dev/geocode/v1/search?q=x"),
    /between 2 and 100/,
  );
});

test("place search identifies the planner, sanitises results and caches them", async () => {
  const originalFetch = globalThis.fetch;
  const originalCaches = globalThis.caches;
  let upstreamRequest;
  let cachedRequest;
  let cachedResponse;
  const backgroundTasks = [];
  globalThis.fetch = async (request) => {
    upstreamRequest = request;
    return Response.json([
      {
        display_name: "Tuckers Grave Inn, Faulkland, Somerset, England",
        lat: "51.30312",
        lon: "-2.34762",
        ignored: "provider-specific data",
      },
      { display_name: "Invalid", lat: "not-a-number", lon: "-2.3" },
    ]);
  };
  globalThis.caches = {
    default: {
      async match() {
        return null;
      },
      async put(request, response) {
        cachedRequest = request;
        cachedResponse = response;
      },
    },
  };

  try {
    const response = await worker.default.fetch(
      new Request("https://balloon-crumbs.pages.dev/geocode/v1/search?q=Tuckers%20Grave"),
      { ASSETS: { fetch: assert.fail } },
      { waitUntil(task) { backgroundTasks.push(task); } },
    );
    await Promise.all(backgroundTasks);
    assert.equal(response.status, 200);
    assert.match(response.headers.get("Cache-Control"), /s-maxage=604800/);
    assert.equal(upstreamRequest.headers.get("Referer"), "https://balloon-crumbs.pages.dev/");
    assert.match(upstreamRequest.headers.get("User-Agent"), /BalloonCrumbsPlanner/);
    assert.equal(
      new URL(upstreamRequest.url).searchParams.get("countrycodes"),
      "gb",
    );
    assert.deepEqual(await response.json(), {
      results: [
        {
          displayName: "Tuckers Grave Inn, Faulkland, Somerset, England",
          latitude: 51.30312,
          longitude: -2.34762,
        },
      ],
    });
    assert.equal(
      cachedRequest.url,
      "https://balloon-crumbs.pages.dev/geocode/v1/search?q=tuckers+grave",
    );
    assert.deepEqual(await cachedResponse.json(), {
      results: [
        {
          displayName: "Tuckers Grave Inn, Faulkland, Somerset, England",
          latitude: 51.30312,
          longitude: -2.34762,
        },
      ],
    });
  } finally {
    globalThis.fetch = originalFetch;
    if (originalCaches === undefined) delete globalThis.caches;
    else globalThis.caches = originalCaches;
  }
});

test("place search rejects invalid queries and non-GET requests", async () => {
  const env = { ASSETS: { fetch: assert.fail } };
  const invalid = await worker.default.fetch(
    new Request("https://balloon-crumbs.pages.dev/geocode/v1/search?q=x"),
    env,
  );
  assert.equal(invalid.status, 400);
  const post = await worker.default.fetch(
    new Request("https://balloon-crumbs.pages.dev/geocode/v1/search?q=Tuckers", {
      method: "POST",
    }),
    env,
  );
  assert.equal(post.status, 405);
  assert.equal(post.headers.get("Allow"), "GET");
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

  assert.equal(requestedPath, "/planner.html");
  assert.equal(await response.text(), "planner");
  assert.equal(response.headers.get("X-Frame-Options"), "DENY");
});

test("mobile association files are served as uncached JSON", async () => {
  for (const path of [
    "/.well-known/apple-app-site-association",
    "/.well-known/assetlinks.json",
  ]) {
    const response = await worker.default.fetch(
      new Request(`https://balloon-crumbs.tailendcharlie.app${path}`),
      {
        ASSETS: {
          async fetch() {
            return new Response("{}", {
              headers: { "Content-Type": "application/octet-stream" },
            });
          },
        },
      },
    );

    assert.equal(response.headers.get("Content-Type"), "application/json");
    assert.equal(response.headers.get("Cache-Control"), "no-store");
  }
});

test("the old Pages planner path redirects to the named planner URL", async () => {
  const response = await worker.default.fetch(
    new Request("https://balloon-crumbs.pages.dev/plan/?example=yes"),
    { ASSETS: { fetch: assert.fail } },
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get("Location"),
    "https://balloon-crumbs.pages.dev/planner.html?example=yes",
  );
});

test("the root serves the product home rather than the planner", async () => {
  let requestedPath;
  const response = await worker.default.fetch(
    new Request("https://balloon-crumbs.pages.dev/"),
    {
      ASSETS: {
        async fetch(request) {
          requestedPath = new URL(request.url).pathname;
          return new Response("home", { headers: { "Content-Type": "text/html" } });
        },
      },
    },
  );

  assert.equal(requestedPath, "/");
  assert.equal(await response.text(), "home");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("the product home leads to the separately styled planner", () => {
  assert.match(homeSource, /One balloon\./);
  assert.match(homeSource, /href="\/planner\.html"/);
  assert.doesNotMatch(homeSource, /id="map"/);
  assert.match(plannerSource, /id="map"/);
  assert.match(plannerSource, /href="planner\.css"/);
});
