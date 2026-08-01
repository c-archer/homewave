# Releasing

## Repository Settings

Enable secret scanning, push protection, CodeQL, Dependabot, private vulnerability reporting, and branch protection requiring `CI` and `CodeQL`.

Set these repository variables:

- `SONOS_AUTH_BASE_URL`: public HTTPS origin of the deployed auth Worker
- `PRIVACY_POLICY_URL`: public HTTPS privacy notice for the actual Worker operator
- `LEGAL_RELEASE_APPROVED`: set to `true` only after completing [LEGAL.md](../LEGAL.md) for that release

## Signing Secrets

For Developer ID signing and notarization, add:

- `BUILD_CERTIFICATE_BASE64`
- `BUILD_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

Do not use repository variables for secrets. Without signing secrets, the workflow produces an ad-hoc-signed community build and must not present it as an official notarized release.

## Release Process

1. Complete the legal, privacy, trademark, asset, and Sonos terms review in `LEGAL.md`.
2. Deploy the Worker revision with `APP_CALLBACK_URL=roomdeck-audio://sonos-auth` and smoke-test it.
3. Run `./Scripts/validate.sh` locally.
4. Review CodeQL, dependency alerts, the changelog, and bundled assets.
5. Create and push an annotated semantic-version tag:

```sh
git tag -a v0.1.0 -m "RoomDeck Audio 0.1.0"
git push origin v0.1.0
```

6. The release workflow tests, packages, signs when configured, notarizes when configured, creates a ZIP and checksum, and publishes the GitHub release.
7. Verify the checksum and Gatekeeper result from a clean machine.
8. Confirm sign-in, grouping, ungrouping, volume, favorites, playback, artwork, and media keys against a real system.

Tags with a pre-release suffix, such as `v0.1.0-beta.1`, are published as GitHub pre-releases. They still require HTTPS authentication and privacy-policy origins, but do not satisfy or bypass the stable-release legal approval gate. Clearly identify ad-hoc-signed builds and do not describe pre-releases as notarized or legally cleared.
