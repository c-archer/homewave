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

    func testFavoriteResourceTypesMapToLibraryFilters() {
        XCTAssertEqual(CloudContentKind(resourceType: "ALBUM"), .album)
        XCTAssertEqual(CloudContentKind(resourceType: "TRACKLIST"), .playlist)
        XCTAssertEqual(CloudContentKind(resourceType: "STREAM"), .station)
        XCTAssertEqual(CloudContentKind(resourceType: "TRACK"), .other)
        XCTAssertEqual(CloudContentKind(resourceType: nil), .other)
    }

    func testMusicFiltersAndSearchUseSavedContentMetadata() {
        let favorite = CloudFavorite(
            id: "favorite-id",
            title: "Example Album",
            subtitle: "Example Artist",
            imageURL: nil,
            serviceName: "Example Music",
            kind: .album
        )
        let playlist = CloudPlaylist(id: "playlist-id", name: "Evening Mix", trackCount: 12)

        XCTAssertTrue(MusicLibraryFilter.all.includes(favorite))
        XCTAssertTrue(MusicLibraryFilter.favorites.includes(favorite))
        XCTAssertTrue(MusicLibraryFilter.albums.includes(favorite))
        XCTAssertFalse(MusicLibraryFilter.stations.includes(favorite))
        XCTAssertTrue(MusicLibraryFilter.playlists.includesSonosPlaylists)
        XCTAssertTrue(favorite.matchesLibraryQuery("artist"))
        XCTAssertTrue(favorite.matchesLibraryQuery("music"))
        XCTAssertTrue(playlist.matchesLibraryQuery("evening"))
        XCTAssertFalse(playlist.matchesLibraryQuery("morning"))
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
