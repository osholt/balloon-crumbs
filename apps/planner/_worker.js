const ORACLE_ORIGIN = "https://relay.balloon-crumbs.tailendcharlie.app";

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
    pathname.startsWith("/maps/")
  );
}

async function proxyToOracle(request) {
  const upstreamRequest = new Request(oracleUrl(request.url), request);
  upstreamRequest.headers.delete("cookie");
  return fetch(upstreamRequest);
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
  if (url.pathname === "/.well-known/apple-app-site-association") {
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
  async fetch(request, env) {
    const url = new URL(request.url);

    if (isOracleProxyPath(url.pathname)) {
      return proxyToOracle(request);
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
