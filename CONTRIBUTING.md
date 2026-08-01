# Contributing

Thank you for helping improve RoomDeck Audio.

## Before Starting

- Keep changes focused and discuss large protocol, authentication, or architecture work first.
- Never use a real Client Secret, token, OAuth code, account response, or personal room name in tests.
- Do not add private or reverse-engineered Sonos interfaces.
- Do not add copied logos, screenshots, artwork, or source without documented permission and provenance.
- Prefer platform APIs over new dependencies.

## Development

Requirements are macOS 14 or later, Xcode with Swift 6, and Node.js 20 or later. Command Line Tools alone may not include XCTest.

```sh
./Scripts/validate.sh
```

New network, authentication, grouping, and playback behavior should include deterministic tests that do not require a Sonos account.

## Pull Requests

A pull request must pass CI and CodeQL, include relevant tests and documentation, preserve independent-project notices, update the asset register for new files, and contain no credentials or private user data.

## Coding Style

- Prefer Swift concurrency and value types at network boundaries.
- Validate external identifiers before constructing URLs.
- Bound requests and responses.
- Keep secrets out of app bundles, defaults, logs, source, and errors.
- Keep controls accessible at supported window sizes and in dark appearance.
