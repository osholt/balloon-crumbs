const ORACLE_ORIGIN = "https://relay.balloon-crumbs.tailendcharlie.app";
const NOMINATIM_ORIGIN = "https://nominatim.openstreetmap.org";
const GEOCODE_CACHE_SECONDS = 7 * 24 * 60 * 60;

const STATIC_SECURITY_HEADERS = {
  "Content-Security-Policy":
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self'; worker-src blob:; child-src blob:; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  "Permissions-Policy": "geolocation=(self)",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
};

export function isOracleProxyPath(pathname) {
  return (
    pathname.startsWith("/api/") ||
    pathname === "/health/live" ||
    pathname === "/weather/v1/forecast" ||
    pathname.startsWith("/maps/styles/") ||
    pathname.startsWith("/maps/basemap/") ||
    pathname.startsWith("/maps/fonts/") ||
    pathname.startsWith("/maps/openaip/")
  );
}

export function isGeocodePath(pathname) {
  return pathname === "/geocode/v1/search";
}

export function geocodeSearchUrl(requestUrl) {
  const source = new URL(requestUrl);
  const query = (source.searchParams.get("q") ?? "").trim().replace(/\s+/g, " ");
  if (query.length < 2 || query.length > 100) {
    throw new RangeError("Search text must be between 2 and 100 characters.");
  }
  const url = new URL("/search", NOMINATIM_ORIGIN);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("limit", "5");
  url.searchParams.set("countrycodes", "gb");
  url.searchParams.set("accept-language", "en-GB");
  return url;
}

export function oracleUrl(requestUrl) {
  const source = new URL(requestUrl);
  return new URL(`${source.pathname}${source.search}`, ORACLE_ORIGIN).toString();
}

export function assetPath(pathname) {
  if (pathname === "/planner.html") return "/index.html";
  return pathname;
}

export function isReservedBackendPath(pathname) {
  return (
    pathname === "/metrics" ||
    pathname.startsWith("/api/") ||
    pathname.startsWith("/health/") ||
    pathname.startsWith("/weather/") ||
    pathname.startsWith("/geocode/") ||
    pathname.startsWith("/maps/")
  );
}

async function proxyToOracle(request) {
  const upstreamRequest = new Request(oracleUrl(request.url), request);
  upstreamRequest.headers.delete("cookie");
  return fetch(upstreamRequest);
}

function jsonResponse(body, status, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

function normaliseGeocodeResults(payload) {
  if (!Array.isArray(payload)) return [];
  return payload.slice(0, 5).flatMap((result) => {
    const latitude = Number(result?.lat);
    const longitude = Number(result?.lon);
    const displayName = String(result?.display_name ?? "").trim();
    if (
      !displayName ||
      !Number.isFinite(latitude) ||
      latitude < -90 ||
      latitude > 90 ||
      !Number.isFinite(longitude) ||
      longitude < -180 ||
      longitude > 180
    ) {
      return [];
    }
    return [{ displayName, latitude, longitude }];
  });
}

async function searchPlaces(request, ctx) {
  if (request.method !== "GET") {
    return jsonResponse({ error: "Place search only accepts GET requests." }, 405, {
      Allow: "GET",
    });
  }

  let upstreamUrl;
  try {
    upstreamUrl = geocodeSearchUrl(request.url);
  } catch (error) {
    return jsonResponse({ error: error.message }, 400);
  }

  const requestUrl = new URL(request.url);
  requestUrl.search = new URLSearchParams({
    q: upstreamUrl.searchParams.get("q").toLocaleLowerCase("en-GB"),
  }).toString();
  const cacheKey = new Request(requestUrl.toString(), { method: "GET" });
  const cache = globalThis.caches?.default;
  const cached = await cache?.match(cacheKey);
  if (cached) return cached;

  let upstreamResponse;
  try {
    upstreamResponse = await fetch(
      new Request(upstreamUrl, {
        headers: {
          Accept: "application/json",
          Referer: "https://balloon-crumbs.pages.dev/",
          "User-Agent":
            "BalloonCrumbsPlanner/1.0 (+https://balloon-crumbs.pages.dev/)",
        },
      }),
    );
  } catch {
    return jsonResponse({ error: "The place-search provider is unavailable." }, 502);
  }
  if (!upstreamResponse.ok) {
    return jsonResponse({ error: "The place-search provider is unavailable." }, 502);
  }

  let payload;
  try {
    payload = await upstreamResponse.json();
  } catch {
    return jsonResponse({ error: "The place-search provider returned invalid data." }, 502);
  }
  const response = jsonResponse(
    { results: normaliseGeocodeResults(payload) },
    200,
    { "Cache-Control": `public, max-age=300, s-maxage=${GEOCODE_CACHE_SECONDS}` },
  );
  if (cache) {
    const cacheWrite = cache.put(cacheKey, response.clone());
    if (ctx?.waitUntil) ctx.waitUntil(cacheWrite);
    else await cacheWrite;
  }
  return response;
}

async function serveAsset(request, env) {
  const url = new URL(request.url);
  url.pathname = assetPath(url.pathname);
  const response = await env.ASSETS.fetch(new Request(url, request));
  const headers = new Headers(response.headers);

  for (const [name, value] of Object.entries(STATIC_SECURITY_HEADERS)) {
    headers.set(name, value);
  }
  if (url.pathname === "/index.html" || url.pathname === "/") {
    headers.set("Cache-Control", "no-store");
    headers.set("Pragma", "no-cache");
  }
  if (
    url.pathname === "/.well-known/apple-app-site-association" ||
    url.pathname === "/.well-known/assetlinks.json"
  ) {
    headers.set("Content-Type", "application/json");
    headers.set("Cache-Control", "no-store");
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (isOracleProxyPath(url.pathname)) {
      return proxyToOracle(request);
    }

    if (isGeocodePath(url.pathname)) {
      return searchPlaces(request, ctx);
    }

    if (isReservedBackendPath(url.pathname)) {
      return new Response(null, { status: 404 });
    }

    if (url.pathname === "/plan" || url.pathname === "/plan/") {
      url.pathname = "/";
      return Response.redirect(url, 308);
    }

    return serveAsset(request, env);
  },
};
