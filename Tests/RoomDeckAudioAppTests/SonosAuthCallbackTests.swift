import Foundation
import XCTest

@testable import RoomDeckAudioApp

final class SonosAuthCallbackTests: XCTestCase {
    private let ticket = "144712aa-08f5-4e90-86f8-223459c0126d"
    private let state = "f5f15a91-f2d1-4f01-830d-e75dabb50a61"

    func testParsesExpectedCallback() throws {
        let url = try XCTUnwrap(
            URL(
                string: "roomdeck-audio://sonos-auth?ticket=\(ticket)&state=\(state)"
            )
        )
        let callback = SonosAuthCallback(url: url)
        XCTAssertEqual(callback?.ticket, ticket)
        XCTAssertEqual(callback?.state, state)
    }

    func testParsesLegacyCallbackDuringProductMigration() throws {
        let url = try XCTUnwrap(
            URL(
                string: "homewave://sonos-auth?ticket=\(ticket)&state=\(state)"
            )
        )
        let callback = SonosAuthCallback(url: url)
        XCTAssertEqual(callback?.ticket, ticket)
        XCTAssertEqual(callback?.state, state)
    }

    func testRejectsDuplicateSecurityParameters() throws {
        let url = try XCTUnwrap(
            URL(
                string: "roomdeck-audio://sonos-auth?ticket=\(ticket)&ticket=\(ticket)&state=\(state)"
            )
        )
        XCTAssertNil(SonosAuthCallback(url: url))
    }

    func testRejectsWrongSchemeHostPathAndMalformedUUIDs() throws {
        let invalidURLs = [
            "https://sonos-auth?ticket=\(ticket)&state=\(state)",
            "roomdeck-audio://other?ticket=\(ticket)&state=\(state)",
            "roomdeck-audio://sonos-auth/extra?ticket=\(ticket)&state=\(state)",
            "roomdeck-audio://sonos-auth?ticket=bad&state=\(state)",
        ]

        for value in invalidURLs {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(SonosAuthCallback(url: url), value)
        }
    }
}
