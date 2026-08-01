# Legal Notice And Release Gate

This document records engineering precautions, not legal advice or a guarantee of non-infringement. A qualified solicitor and formal trademark searches are still required before a commercial or App Store release.

## Independent Compatibility

RoomDeck Audio is independent software compatible with Sonos. It is not affiliated with, endorsed by, certified by, or sponsored by Sonos, Inc. Sonos is a trademark of Sonos, Inc.

The app must not display the Sonos logo, a certification badge, or language implying a commercial relationship. Public descriptions should use factual compatibility wording. The implementation is limited to the documented Sonos Control API and OAuth endpoints.

Relevant current publisher terms:

- [Sonos Platform Terms of Service](https://docs.sonos.com/docs/terms-of-service)
- [Sonos guidance for releasing a connected-home integration](https://docs.sonos.com/docs/connected-home-get-started)
- [Sonos Control API reference](https://docs.sonos.com/reference/about-control-api)

## Product Name

The earlier working name was removed after a preliminary search found an existing smart-home controller using that name. `RoomDeck Audio` is a new working name with no obvious conflicting audio-software use found in a preliminary web search.

That is not trademark clearance. Before a public commercial release, use the [UK IPO search](https://www.gov.uk/search-for-trademark), EUIPO, [WIPO Global Brand Database](https://www.wipo.int/en/web/global-brand-database), company-name registers, domains, and relevant app stores, then have counsel assess confusing similarity in the intended territories and classes. Record the search date and result in the release evidence.

## Copyright And Content

- No third-party music-service logos, station logos, album art, or catalogue data are shipped as functional app assets. Documentation screenshots may show content returned at runtime solely to illustrate compatibility and operation.
- Artwork and metadata returned for the signed-in user's Sonos system are displayed transiently and are not written to an app database.
- Contributors must not submit copied interface artwork, proprietary source code, credentials, or assets without a documented compatible licence.
- The MIT licence covers project contributions only. It does not license third-party content or trademarks.

See [Asset Provenance](docs/ASSET_PROVENANCE.md) and [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Privacy And Operations

The operator of a public OAuth Worker is responsible for an accurate privacy notice, controller identity and contact details, data-subject request handling, retention controls, processor terms, breach procedures, and any legally required records. The repository policy is in [PRIVACY.md](PRIVACY.md), but an operator must replace deployment-specific placeholders before serving the public.

## Mandatory Pre-Release Review

Do not describe a release as legally cleared until all of the following are complete:

1. Formal trademark clearance for the product name, icon, bundle identifier, and domain.
2. Sonos integration details and public descriptions reviewed against current platform and brand terms.
3. Privacy policy completed with the actual operator identity, contact method, processors, territories, and deletion process.
4. Apple Developer agreements, export declarations, signing, notarization, accessibility, and App Store requirements reviewed for the intended distribution channel.
5. Every bundled asset listed in the provenance register and every dependency licence reviewed.
6. A qualified lawyer has reviewed the intended release where commercial or jurisdictional risk warrants it.
