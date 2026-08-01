import XCTest

@testable import RoomDeckAudioApp

final class CloudModelTests: XCTestCase {
    func testPlaybackStateClassification() {
        XCTAssertTrue(group(state: "PLAYBACK_STATE_PLAYING").isPlaying)
        XCTAssertTrue(group(state: "PLAYBACK_STATE_BUFFERING").isPlaying)
        XCTAssertFalse(group(state: "PLAYBACK_STATE_PAUSED").isPlaying)
        XCTAssertFalse(group(state: "PLAYBACK_STATE_IDLE").isPlaying)
        XCTAssertFalse(group(state: "").isPlaying)
    }

    func testCloudGroupRetainsSafeDisplayMetadata() {
        let value = CloudGroup(
            id: "group-id",
            name: "Kitchen",
            coordinatorID: "player-a",
            playerIDs: ["player-a", "player-b"],
            playbackState: "PLAYBACK_STATE_PLAYING",
            volume: 24,
            nowPlaying: "Example Track",
            nowPlayingSubtitle: "Example Artist",
            nowPlayingService: "Example Service",
            artworkURL: nil
        )

        XCTAssertEqual(value.playerIDs.count, 2)
        XCTAssertEqual(value.volume, 24)
        XCTAssertEqual(value.nowPlaying, "Example Track")
    }

    private func group(state: String) -> CloudGroup {
        CloudGroup(
            id: "group-id",
            name: "Room",
            coordinatorID: "player-id",
            playerIDs: ["player-id"],
            playbackState: state,
            volume: nil,
            nowPlaying: nil,
            nowPlayingSubtitle: nil,
            nowPlayingService: nil,
            artworkURL: nil
        )
    }
}
