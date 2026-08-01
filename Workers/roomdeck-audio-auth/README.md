# RoomDeck Audio Auth Worker

This Cloudflare Worker keeps the Sonos Client Secret out of the macOS app. It starts OAuth, exchanges authorization codes, issues short-lived app tickets, and refreshes Sonos access tokens.

Deploy this Worker before distributing a build that points to it. The current app uses `POST /sonos/session`; older Worker revisions that expose the ticket in a GET query are incompatible.

## Required Configuration

- KV binding `OAUTH_SESSIONS`
- Text variable `SONOS_CLIENT_ID`
- Encrypted secret `SONOS_CLIENT_SECRET`
- Text variable `SONOS_REDIRECT_URI`, for example `https://auth.example.com/sonos/callback`
- Text variable `APP_CALLBACK_URL`, set exactly to `roomdeck-audio://sonos-auth`
- A public HTTPS route covering `/sonos/*`

The redirect URI must exactly match the URI registered in the Sonos integration. Do not add the custom `roomdeck-audio://` URL to the Sonos integration; the Worker performs that final handoff.

## Cloudflare Dashboard

1. Create a Worker and paste `src/index.js` into the code editor, or deploy it with Wrangler.
2. Create a Workers KV namespace.
3. Bind it to the Worker as `OAUTH_SESSIONS`.
4. Add `SONOS_CLIENT_ID`, `SONOS_REDIRECT_URI`, and `APP_CALLBACK_URL` as plaintext variables.
5. Add `SONOS_CLIENT_SECRET` as an encrypted secret.
6. Route an HTTPS domain or path to the Worker.
7. Confirm `GET https://auth.example.com/sonos/health` returns `{"status":"ok"}`.

For Wrangler, copy `wrangler.toml.example` to an untracked `wrangler.toml`, replace the placeholders, and add the secret separately:

```sh
npx wrangler secret put SONOS_CLIENT_SECRET
npx wrangler deploy
```

Never place the Client Secret in `wrangler.toml`, source code, GitHub Actions variables, screenshots, issues, or the macOS app.

## Routes

- `GET /sonos/login?state=<uuid>`
- `GET /sonos/callback`
- `POST /sonos/session` with JSON `{ "ticket": "<uuid>" }`
- `POST /sonos/refresh` with JSON `{ "refresh_token": "..." }`
- `GET|HEAD /sonos/health`

Responses disable caching, framing, MIME sniffing, and referrer forwarding. Request bodies and token fields are bounded, redirects use strict state validation, and app tickets expire after two minutes.

## Test

```sh
node --check src/index.js
node --test test/index.test.js
```

The tests use an in-memory KV implementation and do not contact Sonos.

## Operational Security

- Enable Cloudflare rate limiting for `/sonos/login`, `/sonos/session`, and `/sonos/refresh` before a public launch.
- Keep Worker logs free of request bodies, codes, tickets, and tokens.
- Treat access to the Worker account and KV namespace as privileged.
- Rotate the Sonos Client Secret after suspected disclosure.
- Monitor 4xx/5xx rates without retaining sensitive URL query data.
- Remember that Workers KV is eventually consistent. Tickets are short-lived and deleted after redemption, but KV alone is not a transactional one-time-token store. A higher-risk deployment should move ticket redemption to a strongly consistent Durable Object.
