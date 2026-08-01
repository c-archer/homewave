# Changelog

All notable changes to RoomDeck Audio are documented here.

## Unreleased

### Added

- Native Apple Silicon macOS controller interface
- Sonos account OAuth through a deployable Worker
- Cloud groups, favorites, playback, artwork, volume, and media-key controls
- Swift and Worker regression tests
- CI, CodeQL, Dependabot, release automation, asset provenance, and legal-release checks

### Changed

- Renamed the product after a preliminary name-conflict review
- Replaced the earlier broadcast-wave icon with RoomDeck Audio room-and-pulse artwork
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
