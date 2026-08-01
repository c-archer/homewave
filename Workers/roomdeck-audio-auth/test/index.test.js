import assert from "node:assert/strict";
import test from "node:test";

import worker, { testables } from "../src/index.js";

const clientState = "f5f15a91-f2d1-4f01-830d-e75dabb50a61";
const ticket = "144712aa-08f5-4e90-86f8-223459c0126d";

class MemoryKV {
  constructor() {
    this.values = new Map();
  }

  async put(key, value) {
    this.values.set(key, value);
  }

  async get(key, type) {
    const value = this.values.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }

  async delete(key) {
    this.values.delete(key);
  }
}

function environment(kv = new MemoryKV()) {
  return {
    OAUTH_SESSIONS: kv,
    SONOS_CLIENT_ID: "test-client-id",
    SONOS_CLIENT_SECRET: "test-client-secret",
    SONOS_REDIRECT_URI: "https://auth.example.com/sonos/callback",
    APP_CALLBACK_URL: "roomdeck-audio://sonos-auth",
  };
}

test("health is public and applies defensive response headers", async () => {
  const response = await worker.fetch(new Request("https://auth.example.com/sonos/health"), {});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
});

test("login rejects malformed state without writing to KV", async () => {
  const env = environment();
  const response = await worker.fetch(
    new Request("https://auth.example.com/sonos/login?state=attacker-controlled"),
    env,
  );
  assert.equal(response.status, 400);
  assert.equal(env.OAUTH_SESSIONS.values.size, 0);
});

test("login stores app state behind server state and redirects to Sonos", async () => {
  const env = environment();
  const response = await worker.fetch(
    new Request(`https://auth.example.com/sonos/login?state=${clientState}`),
    env,
  );
  assert.equal(response.status, 302);

  const location = new URL(response.headers.get("location"));
  assert.equal(location.origin, "https://api.sonos.com");
  assert.equal(location.searchParams.get("client_id"), env.SONOS_CLIENT_ID);
  assert.equal(location.searchParams.get("redirect_uri"), env.SONOS_REDIRECT_URI);
  assert.match(location.searchParams.get("state"), /^[0-9a-f-]{36}$/i);
  assert.equal(env.OAUTH_SESSIONS.values.size, 1);
});

test("session tickets require JSON POST and are deleted after use", async () => {
  const kv = new MemoryKV();
  const env = environment(kv);
  await kv.put(`ticket:${ticket}`, JSON.stringify({ clientState, tokens: { access_token: "a" } }));

  const request = new Request("https://auth.example.com/sonos/session", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ticket }),
  });
  const response = await worker.fetch(request, env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).clientState, clientState);
  assert.equal(await kv.get(`ticket:${ticket}`), null);

  const replay = await worker.fetch(
    new Request("https://auth.example.com/sonos/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ticket }),
    }),
    env,
  );
  assert.equal(replay.status, 404);
});

test("session endpoint rejects credentials in URLs and wrong content types", async () => {
  const env = environment();
  const getResponse = await worker.fetch(
    new Request(`https://auth.example.com/sonos/session?ticket=${ticket}`),
    env,
  );
  assert.equal(getResponse.status, 405);
  assert.equal(getResponse.headers.get("allow"), "POST");

  const formResponse = await worker.fetch(
    new Request("https://auth.example.com/sonos/session", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `ticket=${ticket}`,
    }),
    env,
  );
  assert.equal(formResponse.status, 415);
});

test("environment and token validation reject unsafe values", () => {
  assert.equal(testables.validateEnvironment(environment()), null);
  assert.notEqual(
    testables.validateEnvironment({ ...environment(), SONOS_REDIRECT_URI: "http://auth.example.com/callback" }),
    null,
  );
  assert.notEqual(
    testables.validateEnvironment({ ...environment(), APP_CALLBACK_URL: "https://attacker.example.com" }),
    null,
  );
  assert.equal(
    testables.validTokenPayload({ access_token: "access", refresh_token: "refresh", expires_in: 3600 }),
    true,
  );
  assert.equal(testables.validTokenPayload({ access_token: "access", expires_in: 3600 }), false);
});

test("HTML escaping covers attribute and text contexts", () => {
  assert.equal(
    testables.escapeHTML(`<a href='x'>&"`),
    "&lt;a href=&#39;x&#39;&gt;&amp;&quot;",
  );
});
