# Security Policy

## Supported Versions

Security fixes are provided for the latest published RoomDeck Audio release. This project is beta software.

## Reporting A Vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub private vulnerability reporting from the repository Security tab. Remove Sonos tokens, OAuth codes, callback URLs, Client Secrets, account data, and room names from reports.

Maintainers should acknowledge a complete report within seven days and provide remediation or a status update within 30 days, subject to severity and upstream coordination.

## Security Boundaries

- The Sonos Client Secret belongs only in the Worker secret store.
- Access and refresh tokens are stored in macOS Keychain with device-only, unlocked-device accessibility.
- The Worker temporarily handles authorization codes, tokens, OAuth state, and short-lived session tickets.
- API paths are built from validated path components; redirects are rejected and responses are bounded.
- Artwork URLs must use HTTPS and cannot contain credentials or fragments.
- The public app contains no local-network control implementation or private catalogue endpoint.

## Maintainer Checklist

1. Run `./Scripts/validate.sh`.
2. Review CodeQL, dependency alerts, secret scanning, and the legal-release guard.
3. Deploy and test the matching Worker revision.
4. Confirm no credentials or private account responses are present.
5. Sign and notarize official builds with protected repository secrets.
6. Verify the release checksum from a clean download.

Automated checks do not prove that software is secure. Public deployments need independent review and operational monitoring.
