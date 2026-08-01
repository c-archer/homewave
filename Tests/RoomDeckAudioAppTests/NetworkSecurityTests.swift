import Foundation
import XCTest

@testable import RoomDeckAudioApp

final class NetworkSecurityTests: XCTestCase {
    func testAuthBaseURLRequiresHTTPSAndNoCredentialsOrQuery() {
        XCTAssertEqual(
            NetworkSecurityPolicy.validatedHTTPSBaseURL("https://auth.example.com/base")?
                .absoluteString,
            "https://auth.example.com/base"
        )
        XCTAssertNil(NetworkSecurityPolicy.validatedHTTPSBaseURL("http://auth.example.com"))
        XCTAssertNil(
            NetworkSecurityPolicy.validatedHTTPSBaseURL(
                "https://user:password@auth.example.com"
            )
        )
        XCTAssertNil(
            NetworkSecurityPolicy.validatedHTTPSBaseURL(
                "https://auth.example.com?token=value"
            )
        )
        XCTAssertNil(NetworkSecurityPolicy.validatedHTTPSBaseURL("not a URL"))
    }

    func testRemoteArtworkRequiresHTTPSWithoutCredentialsOrFragments() {
        XCTAssertNotNil(
            NetworkSecurityPolicy.validatedRemoteAssetURL(
                "https://images.example.com/cover.jpg?size=512"
            )
        )
        XCTAssertNil(
            NetworkSecurityPolicy.validatedRemoteAssetURL(
                "http://images.example.com/cover.jpg"
            )
        )
        XCTAssertNil(
            NetworkSecurityPolicy.validatedRemoteAssetURL(
                "https://user:pass@images.example.com/cover.jpg"
            )
        )
        XCTAssertNil(
            NetworkSecurityPolicy.validatedRemoteAssetURL(
                "https://images.example.com/cover.jpg#token"
            )
        )
        XCTAssertNil(
            NetworkSecurityPolicy.validatedRemoteAssetURL(
                String(repeating: "x", count: 4_097)
            )
        )
    }

    func testAPIPathComponentsRejectTraversalAndSeparators() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://api.example.com/v1"))
        XCTAssertEqual(
            try NetworkSecurityPolicy.validatedAPIURL(
                baseURL: baseURL,
                pathComponents: ["groups", "group-id", "playback"]
            ).absoluteString,
            "https://api.example.com/v1/groups/group-id/playback"
        )
        XCTAssertThrowsError(
            try NetworkSecurityPolicy.validatedAPIURL(
                baseURL: baseURL,
                pathComponents: ["groups", "../admin"]
            )
        )
        XCTAssertThrowsError(
            try NetworkSecurityPolicy.validatedAPIURL(
                baseURL: baseURL,
                pathComponents: ["groups", "a/b"]
            )
        )
    }

    func testServerMessagesAreTrimmedBoundedAndControlFree() {
        XCTAssertEqual(
            NetworkSecurityPolicy.sanitizedServerMessage("  failed\n\u{0}again  "),
            "failedagain"
        )
        XCTAssertEqual(
            NetworkSecurityPolicy.sanitizedServerMessage(
                String(repeating: "x", count: 500)
            )?.count,
            300
        )
        XCTAssertNil(NetworkSecurityPolicy.sanitizedServerMessage("\n\t"))
    }
}
