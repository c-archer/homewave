# Architecture

## Components

- `RoomDeckAudioApp.swift`: SwiftUI app, state model, documented cloud controls, and media-key integration
- `SonosCloudConnector.swift`: OAuth handoff, token refresh, and Keychain persistence
- `SonosCloudControl.swift`: documented Sonos Control API groups, favorites, volume, metadata, and playback
- `NetworkSecurity.swift`: HTTPS URL policy, path validation, redirect rejection, bounded responses, and error sanitization
- `Workers/roomdeck-audio-auth`: server-side OAuth code exchange and refresh

No private Sonos web interface, local SSDP discovery, UPnP/SOAP control, or music-service catalogue reverse engineering is included in the public source.

## Authentication Flow

1. The app creates a random UUID and opens `GET /sonos/login` on the configured Worker.
2. The Worker replaces it with a server-side OAuth state stored temporarily in KV.
3. Sonos redirects to the Worker's registered HTTPS callback.
4. The Worker validates state, exchanges the code, and creates a two-minute ticket.
5. The browser opens `roomdeck-audio://sonos-auth` with the ticket and original app state.
6. The app validates the deep link and redeems the ticket with a JSON POST.
7. Tokens are saved to Keychain. Refresh goes through the Worker so the Client Secret stays server-side.

## Trust Boundaries

Sonos responses, artwork URLs, deep links, Worker requests, and build-time configuration are untrusted input. The Worker is privileged because it stores the Client Secret and briefly receives account tokens. The app is privileged because it stores tokens and controls the user's system. Neither component should log credentials or private account responses.

## Testing Strategy

Unit tests cover deterministic URL policy and auth callback validation. Worker tests cover state handling, one-time tickets, validation, and response headers. CI also creates and validates the arm64 app bundle. Tests do not contact Sonos or use real credentials.

Live testing remains necessary for account permissions, speaker firmware, grouping, playback, artwork, OAuth registration, and media keys.
