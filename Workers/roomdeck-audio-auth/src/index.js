const AUTH_STATE_TTL_SECONDS = 10 * 60;
const SESSION_TICKET_TTL_SECONDS = 2 * 60;
const MAX_JSON_BODY_BYTES = 24 * 1024;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);

      if ((request.method === "GET" || request.method === "HEAD") && url.pathname === "/sonos/health") {
        return request.method === "HEAD" ? secureResponse(null) : json({ status: "ok" });
      }

      const configurationError = validateEnvironment(env);
      if (configurationError) return json({ error: configurationError }, 503);

      if (request.method === "GET" && url.pathname === "/sonos/login") {
        return startLogin(url, env);
      }
      if (request.method === "GET" && url.pathname === "/sonos/callback") {
        return finishLogin(url, env);
      }
      if (request.method === "POST" && url.pathname === "/sonos/session") {
        return readSession(request, env);
      }
      if (request.method === "POST" && url.pathname === "/sonos/refresh") {
        return refreshSession(request, env);
      }

      if (url.pathname.startsWith("/sonos/")) {
        return json({ error: "Method not allowed" }, 405, { Allow: allowedMethods(url.pathname) });
      }
      return json({ error: "Not found" }, 404);
    } catch (error) {
      console.error("RoomDeck Audio auth request failed", error instanceof Error ? error.name : "UnknownError");
      return json({ error: "The sign-in service could not process this request" }, 500);
    }
  },
};

async function startLogin(url, env) {
  const clientState = url.searchParams.get("state");
  if (!isUUID(clientState)) {
    return json({ error: "A valid sign-in state is required" }, 400);
  }

  const serverState = crypto.randomUUID();
  await env.OAUTH_SESSIONS.put(
    `auth:${serverState}`,
    JSON.stringify({ clientState }),
    { expirationTtl: AUTH_STATE_TTL_SECONDS },
  );

  const authorize = new URL("https://api.sonos.com/login/v3/oauth");
  authorize.search = new URLSearchParams({
    client_id: env.SONOS_CLIENT_ID,
    response_type: "code",
    state: serverState,
    scope: "playback-control-all",
    redirect_uri: env.SONOS_REDIRECT_URI,
  }).toString();
  return Response.redirect(authorize.toString(), 302);
}

async function finishLogin(url, env) {
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  const loginError = url.searchParams.get("error");
  if (!isUUID(state)) return errorPage("This sign-in link is invalid. Return to RoomDeck Audio and try again.");

  const savedState = await env.OAUTH_SESSIONS.get(`auth:${state}`, "json");
  await env.OAUTH_SESSIONS.delete(`auth:${state}`);

  if (!savedState || !isUUID(savedState.clientState)) {
    return errorPage("This sign-in link has expired. Return to RoomDeck Audio and try again.");
  }
  if (loginError) return errorPage("Sonos sign-in was declined. Return to RoomDeck Audio and try again.");
  if (!code || code.length > 4096) return errorPage("Sonos did not return a valid authorization code.");

  try {
    const tokens = await requestTokens(env, {
      grant_type: "authorization_code",
      code,
      redirect_uri: env.SONOS_REDIRECT_URI,
    });
    const ticket = crypto.randomUUID();
    await env.OAUTH_SESSIONS.put(
      `ticket:${ticket}`,
      JSON.stringify({ tokens, clientState: savedState.clientState }),
      { expirationTtl: SESSION_TICKET_TTL_SECONDS },
    );

    const callback = new URL(env.APP_CALLBACK_URL);
    callback.searchParams.set("ticket", ticket);
    callback.searchParams.set("state", savedState.clientState);
    return completionPage(callback.toString());
  } catch (error) {
    console.error("Sonos token exchange failed", error instanceof Error ? error.name : "UnknownError");
    return errorPage("Could not complete Sonos sign-in. Return to RoomDeck Audio and try again.");
  }
}

async function readSession(request, env) {
  try {
    const body = await readJSON(request);
    const ticket = body?.ticket;
    if (!isUUID(ticket)) return json({ error: "A valid session ticket is required" }, 400);

    const session = await env.OAUTH_SESSIONS.get(`ticket:${ticket}`, "json");
    if (!session) return json({ error: "This sign-in ticket has expired" }, 404);
    await env.OAUTH_SESSIONS.delete(`ticket:${ticket}`);
    return json(session);
  } catch (error) {
    if (error instanceof RequestValidationError) return json({ error: error.message }, error.status);
    throw error;
  }
}

async function refreshSession(request, env) {
  try {
    const body = await readJSON(request);
    if (!isBoundedString(body?.refresh_token, 16_384)) {
      return json({ error: "A valid refresh token is required" }, 400);
    }
    const tokens = await requestTokens(env, {
      grant_type: "refresh_token",
      refresh_token: body.refresh_token,
    });
    return json(tokens);
  } catch (error) {
    const status = error instanceof RequestValidationError ? error.status : 502;
    return json({ error: status === 502 ? "Could not refresh the Sonos session" : error.message }, status);
  }
}

async function requestTokens(env, values) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch("https://api.sonos.com/login/v3/oauth/access", {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${env.SONOS_CLIENT_ID}:${env.SONOS_CLIENT_SECRET}`)}`,
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        Accept: "application/json",
      },
      body: new URLSearchParams(values),
      signal: controller.signal,
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || !validTokenPayload(payload)) {
      throw new Error("Sonos token request failed");
    }
    return payload;
  } finally {
    clearTimeout(timeout);
  }
}

async function readJSON(request) {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new RequestValidationError("Content-Type must be application/json", 415);
  }
  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (declaredLength > MAX_JSON_BODY_BYTES) {
    throw new RequestValidationError("Request body is too large", 413);
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_JSON_BODY_BYTES) {
    throw new RequestValidationError("Request body is too large", 413);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new RequestValidationError("Request body must be valid JSON", 400);
  }
}

function validateEnvironment(env) {
  if (!env?.OAUTH_SESSIONS?.get || !env?.OAUTH_SESSIONS?.put || !env?.OAUTH_SESSIONS?.delete) {
    return "The sign-in service is not configured";
  }
  if (!isBoundedString(env.SONOS_CLIENT_ID, 512) || !isBoundedString(env.SONOS_CLIENT_SECRET, 4096)) {
    return "The sign-in service is not configured";
  }
  try {
    const redirect = new URL(env.SONOS_REDIRECT_URI);
    if (redirect.protocol !== "https:" || redirect.username || redirect.password || redirect.search || redirect.hash) {
      return "The sign-in service is not configured";
    }
  } catch {
    return "The sign-in service is not configured";
  }
  try {
    const callback = new URL(env.APP_CALLBACK_URL);
    if (callback.protocol !== "roomdeck-audio:" || callback.hostname !== "sonos-auth"
      || callback.username || callback.password || callback.search || callback.hash
      || (callback.pathname && callback.pathname !== "/")) {
      return "The sign-in service is not configured";
    }
  } catch {
    return "The sign-in service is not configured";
  }
  return null;
}

function validTokenPayload(payload) {
  return payload
    && isBoundedString(payload.access_token, 16_384)
    && isBoundedString(payload.refresh_token, 16_384)
    && Number.isFinite(payload.expires_in)
    && payload.expires_in > 0;
}

function isBoundedString(value, maximumLength) {
  return typeof value === "string" && value.length > 0 && value.length <= maximumLength;
}

function isUUID(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function allowedMethods(pathname) {
  if (pathname === "/sonos/login" || pathname === "/sonos/callback") return "GET";
  if (pathname === "/sonos/session" || pathname === "/sonos/refresh") return "POST";
  if (pathname === "/sonos/health") return "GET, HEAD";
  return "";
}

function secureHeaders(extra = {}) {
  return {
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    ...extra,
  };
}

function secureResponse(body, init = {}) {
  return new Response(body, { ...init, headers: secureHeaders(init.headers) });
}

function json(value, status = 200, extraHeaders = {}) {
  return secureResponse(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...extraHeaders },
  });
}

function completionPage(callbackURL) {
  const escapedURL = escapeHTML(callbackURL);
  return secureResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="0;url=${escapedURL}"><title>RoomDeck Audio connected</title></head><body><main><h1>Sonos connected</h1><p>Returning to RoomDeck Audio...</p><p><a href="${escapedURL}">Open RoomDeck Audio</a></p></main></body></html>`, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function errorPage(message) {
  return secureResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>RoomDeck Audio sign-in</title></head><body><main><h1>Sign-in could not finish</h1><p>${escapeHTML(message)}</p></main></body></html>`, {
    status: 400,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function escapeHTML(value) {
  return String(value).replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character]);
}

class RequestValidationError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "RequestValidationError";
    this.status = status;
  }
}

export const testables = {
  escapeHTML,
  isUUID,
  validTokenPayload,
  validateEnvironment,
};
