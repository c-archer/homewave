# Changelog

All notable changes to RoomDeck Audio are documented here.

## Unreleased

## 0.1.0-beta.4 - 2026-08-01

### Added

- Homebrew Cask and tap installation instructions
- Search and content-type filters for music saved to the signed-in Sonos account
- Sonos playlist discovery and playback through the documented Control API

### Fixed

- Sonos OAuth callbacks now return to the existing app window instead of opening another sign-in window
- Replayed OAuth callback tickets are ignored rather than redeemed twice

## 0.1.0-beta.2 - 2026-08-01

### Changed

- Replaced the app icon with an original paired-room waveform mark

### Fixed

- Release checksums now use the downloadable archive filename instead of the CI staging path

## 0.1.0-beta.1 - 2026-08-01

### Added

- Native Apple Silicon macOS controller interface
- Sonos account OAuth through a deployable Worker
- Cloud groups, favorites, playback, artwork, volume, and media-key controls
- Swift and Worker regression tests
- CI, CodeQL, Dependabot, release automation, asset provenance, and legal-release checks

### Changed

- Renamed the product after a preliminary name-conflict review
- Restored the original audio-wave icon after design review
- Added temporary compatibility for the legacy OAuth app callback during migration
- Limited the public implementation to documented Sonos Control API and OAuth endpoints

### Removed

- Private music-service catalogue integration
- Custom third-party station and service graphics
- Local SSDP and UPnP/SOAP control implementation

### Security

- HTTPS-only authentication configuration and artwork loading
- Keychain token storage with device-only accessibility
- Strict deep-link validation
- Redirect rejection, request timeouts, response bounds, short Worker tickets, and reduced error disclosure
