# Privacy

RoomDeck Audio is a controller, not a music service. The repository does not include analytics, advertising, telemetry, or third-party crash-reporting SDKs.

## Data Used By The App

- Sonos access and refresh tokens are stored in the current user's macOS Keychain.
- A random pending OAuth state value is stored briefly in macOS user defaults.
- Room and group names, player membership, playback state, volume, favorites, track metadata, service names, and artwork URLs are requested from Sonos as needed and held in memory.
- Remote artwork is loaded over HTTPS and is not intentionally written to an app database.

The app does not intentionally persist listening history, favorites, room names, searches, or playback metadata. Disconnecting removes the Sonos session from Keychain and clears account data held by the running app.

## Authentication Worker

The configured Worker receives the Sonos OAuth callback and token-refresh requests. OAuth state is retained for at most ten minutes. A token-bearing handoff ticket is retained for at most two minutes and deleted when redeemed. Refresh tokens pass through the Worker during refresh and are not intentionally logged or stored by the Worker code.

Cloudflare and the Worker operator process network metadata and may have independent logs and legal obligations. Users should only sign in through an operator they trust. Forks can self-host the Worker.

## External Recipients

Account authorization and control requests are sent to Sonos. Artwork requests are sent to the HTTPS hosts supplied by Sonos metadata. Apple processes normal macOS networking and Keychain operations, and Cloudflare processes Worker traffic when that deployment is used.

## Public Deployment Requirement

Before operating a public Worker, publish a deployment-specific privacy notice naming the controller, contact method, purposes and lawful bases, processors, international transfers, retention, user rights, complaint route, and deletion process. This repository cannot supply those facts for an unknown operator.

## Diagnostics

Issue reports must remove tokens, authorization codes, callback URLs, Client Secrets, account identifiers, private room names, and personal playback data. RoomDeck Audio does not automatically upload diagnostics.
