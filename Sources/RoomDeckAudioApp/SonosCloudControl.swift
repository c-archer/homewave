import Foundation

struct CloudGroup: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let coordinatorID: String
    let playerIDs: [String]
    var playbackState: String
    var volume: Int?
    var nowPlaying: String?
    var nowPlayingSubtitle: String?
    var nowPlayingService: String?
    var artworkURL: URL?

    var isPlaying: Bool {
        !["PLAYBACK_STATE_IDLE", "PLAYBACK_STATE_PAUSED", ""].contains(playbackState)
    }
}

struct CloudPlayer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var volume: Int?
    var isMuted: Bool
    var isVolumeFixed: Bool
}

struct CloudFavorite: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    let serviceName: String
    let kind: CloudContentKind
}

enum CloudContentKind: String, Sendable {
    case album
    case playlist
    case station
    case other

    init(resourceType: String?) {
        switch resourceType?.uppercased() {
        case "ALBUM": self = .album
        case "PLAYLIST", "TRACKLIST": self = .playlist
        case "PROGRAM", "STATION", "STREAM": self = .station
        default: self = .other
        }
    }
}

struct CloudPlaylist: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let trackCount: Int
}

struct CloudSnapshot: Sendable {
    let groups: [CloudGroup]
    let favorites: [CloudFavorite]
    let playlists: [CloudPlaylist]
    let players: [CloudPlayer]
}

enum SonosCloudControlError: LocalizedError {
    case unavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Your Sonos account session is unavailable"
        case .requestFailed(let message):
            return message
        }
    }
}

actor SonosCloudControl {
    private let session: SonosCloudConnector
    private let baseURL = URL(string: "https://api.ws.sonos.com/control/api/v1")!

    init(session: SonosCloudConnector) {
        self.session = session
    }

    func snapshot() async throws -> CloudSnapshot {
        let households: HouseholdsResponse = try await request(pathComponents: ["households"])
        guard let householdID = households.households.first?.id else {
            return CloudSnapshot(groups: [], favorites: [], playlists: [], players: [])
        }

        async let groupsResponse: GroupsResponse = request(
            pathComponents: ["households", householdID, "groups"]
        )
        async let favoritesResponse: FavoritesResponse = request(
            pathComponents: ["households", householdID, "favorites"]
        )
        async let playlistsResponse: PlaylistsResponse = request(
            pathComponents: ["households", householdID, "playlists"]
        )
        let (groups, favorites, playlists) = try await (
            groupsResponse,
            favoritesResponse,
            playlistsResponse
        )

        let enrichedGroups = try await withThrowingTaskGroup(of: CloudGroup.self) { group in
            for item in groups.groups {
                group.addTask { [self] in
                    async let playback: PlaybackResponse = request(
                        pathComponents: ["groups", item.id, "playback"]
                    )
                    async let volume: VolumeResponse = request(
                        pathComponents: ["groups", item.id, "groupVolume"]
                    )
                    async let metadata = playbackMetadata(groupID: item.id)
                    let (playbackValue, volumeValue, metadataValue) = try await (playback, volume, metadata)
                    return CloudGroup(
                        id: item.id,
                        name: item.name,
                        coordinatorID: item.coordinatorId,
                        playerIDs: item.playerIds,
                        playbackState: playbackValue.playbackState ?? item.playbackState ?? "PLAYBACK_STATE_IDLE",
                        volume: volumeValue.volume,
                        nowPlaying: metadataValue.title,
                        nowPlayingSubtitle: metadataValue.subtitle,
                        nowPlayingService: metadataValue.serviceName,
                        artworkURL: metadataValue.artworkURL
                    )
                }
            }

            var results: [CloudGroup] = []
            for try await item in group { results.append(item) }
            return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let cloudPlayers = await withTaskGroup(of: CloudPlayer.self) { taskGroup in
            for item in groups.players {
                taskGroup.addTask { [self] in
                    let playerVolume: PlayerVolumeResponse? = try? await request(
                        pathComponents: ["players", item.id, "playerVolume"]
                    )
                    return CloudPlayer(
                        id: item.id,
                        name: item.name,
                        volume: playerVolume?.volume,
                        isMuted: playerVolume?.muted ?? false,
                        isVolumeFixed: playerVolume?.fixed ?? false
                    )
                }
            }

            var results: [CloudPlayer] = []
            for await item in taskGroup { results.append(item) }
            return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let cloudFavorites = favorites.items.map(CloudFavorite.init)
        let groupsWithFavoriteArtwork = enrichedGroups.map { group in
            guard group.artworkURL == nil, let title = group.nowPlaying else { return group }
            guard let favorite = cloudFavorites.first(where: { Self.titlesMatch(title, $0.title) }) else { return group }
            var updated = group
            updated.artworkURL = favorite.imageURL
            return updated
        }

        return CloudSnapshot(
            groups: groupsWithFavoriteArtwork,
            favorites: cloudFavorites,
            playlists: playlists.playlists.map(CloudPlaylist.init),
            players: cloudPlayers
        )
    }

    func togglePlayback(group: CloudGroup) async throws {
        let action = group.isPlaying ? "pause" : "play"
        try await command(pathComponents: ["groups", group.id, "playback", action])
    }

    func skip(groupID: String, forward: Bool) async throws {
        let action = forward ? "skipToNextTrack" : "skipToPreviousTrack"
        try await command(pathComponents: ["groups", groupID, "playback", action])
    }

    func setVolume(_ volume: Int, groupID: String) async throws {
        try await command(
            pathComponents: ["groups", groupID, "groupVolume"],
            body: ["volume": min(100, max(0, volume))]
        )
    }

    func setPlayerVolume(_ volume: Int, playerID: String) async throws {
        try await command(
            pathComponents: ["players", playerID, "playerVolume"],
            body: ["volume": min(100, max(0, volume))]
        )
    }

    func setPlayerMuted(_ muted: Bool, playerID: String) async throws {
        try await command(
            pathComponents: ["players", playerID, "playerVolume", "mute"],
            body: ["muted": muted]
        )
    }

    func loadFavorite(_ favorite: CloudFavorite, groupID: String) async throws {
        try await command(
            pathComponents: ["groups", groupID, "favorites"],
            body: ["favoriteId": favorite.id, "action": "PLAY_NOW"]
        )
    }

    func loadPlaylist(_ playlist: CloudPlaylist, groupID: String) async throws {
        try await command(
            pathComponents: ["groups", groupID, "playlists"],
            body: [
                "playlistId": playlist.id,
                "action": "PLAY_NOW",
                "playOnCompletion": true,
            ]
        )
    }

    func createGroup(playerIDs: [String], musicContextGroupID: String?) async throws {
        let households: HouseholdsResponse = try await request(pathComponents: ["households"])
        guard let householdID = households.households.first?.id else { throw SonosCloudControlError.unavailable }
        var body: [String: Any] = ["playerIds": playerIDs]
        if let musicContextGroupID { body["musicContextGroupId"] = musicContextGroupID }
        try await command(
            pathComponents: ["households", householdID, "groups", "createGroup"],
            body: body
        )
    }

    func ungroup(_ group: CloudGroup) async throws {
        let memberIDs = group.playerIDs.filter { $0 != group.coordinatorID }
        guard !memberIDs.isEmpty else { return }

        do {
            try await command(
                pathComponents: ["groups", group.id, "groups", "modifyGroupMembers"],
                body: ["playerIdsToRemove": memberIDs]
            )
        } catch {
            for playerID in memberIDs {
                try await createGroup(playerIDs: [playerID], musicContextGroupID: nil)
            }
        }
    }

    private func command(pathComponents: [String], body: [String: Any] = [:]) async throws {
        _ = try await requestData(pathComponents: pathComponents, method: "POST", body: body)
    }

    private func request<Response: Decodable>(pathComponents: [String]) async throws -> Response {
        let data = try await requestData(pathComponents: pathComponents, method: "GET")
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func requestData(
        pathComponents: [String],
        method: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        let token = try await session.accessToken()
        let url = try NetworkSecurityPolicy.validatedAPIURL(
            baseURL: baseURL,
            pathComponents: pathComponents
        )
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("RoomDeckAudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, http) = try await HardenedHTTPClient.data(for: request, maximumBytes: 2 * 1_024 * 1_024)
        guard (200..<300).contains(http.statusCode) else {
            throw SonosCloudControlError.requestFailed(Self.errorMessage(data) ?? "Sonos cloud returned HTTP \(http.statusCode)")
        }
        return data
    }

    private func playbackMetadata(groupID: String) async throws -> CloudPlaybackMetadata {
        let data = try await requestData(
            pathComponents: ["groups", groupID, "playbackMetadata"],
            method: "GET"
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CloudPlaybackMetadata()
        }

        let container = object["container"] as? [String: Any]
        let currentItem = object["currentItem"] as? [String: Any]
        let track = currentItem?["track"] as? [String: Any]
        let album = track?["album"] as? [String: Any]
        let artist = track?["artist"] as? [String: Any]
        let service =
            (track?["service"] as? [String: Any])
            ?? (container?["service"] as? [String: Any])

        let title =
            Self.nonEmptyString(track?["name"])
            ?? Self.nonEmptyString(currentItem?["name"])
            ?? Self.nonEmptyString(container?["name"])
            ?? Self.nonEmptyString(object["streamInfo"])
        let subtitle =
            Self.nonEmptyString(artist?["name"])
            ?? Self.nonEmptyString(album?["name"])
        let imageText =
            Self.nonEmptyString(track?["imageUrl"])
            ?? Self.nonEmptyString(album?["imageUrl"])
            ?? Self.nonEmptyString(currentItem?["imageUrl"])
            ?? Self.nonEmptyString(container?["imageUrl"])
            ?? Self.nonEmptyString(service?["imageUrl"])

        return CloudPlaybackMetadata(
            title: title,
            subtitle: subtitle,
            serviceName: Self.nonEmptyString(service?["name"]),
            artworkURL: NetworkSecurityPolicy.validatedRemoteAssetURL(imageText)
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedTitle(lhs)
        let right = normalizedTitle(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func errorMessage(_ data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let value = object?["message"] as? String ?? object?["error"] as? String
        return NetworkSecurityPolicy.sanitizedServerMessage(value)
    }
}

private struct CloudPlaybackMetadata: Sendable {
    var title: String?
    var subtitle: String?
    var serviceName: String?
    var artworkURL: URL?
}

private struct HouseholdsResponse: Decodable { let households: [Household] }
private struct Household: Decodable { let id: String }
private struct GroupsResponse: Decodable {
    let groups: [Group]
    let players: [Player]
}
private struct Group: Decodable {
    let id: String
    let name: String
    let coordinatorId: String
    let playerIds: [String]
    let playbackState: String?
}
private struct Player: Decodable {
    let id: String
    let name: String
}
private struct PlaybackResponse: Decodable { let playbackState: String? }
private struct VolumeResponse: Decodable { let volume: Int? }
struct PlayerVolumeResponse: Decodable {
    let volume: Int?
    let muted: Bool?
    let fixed: Bool?
}
private struct FavoritesResponse: Decodable {
    let items: [Favorite]

    enum CodingKeys: String, CodingKey { case items, favorites }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items =
            try container.decodeIfPresent([Favorite].self, forKey: .items)
            ?? container.decodeIfPresent([Favorite].self, forKey: .favorites)
            ?? []
    }
}
private struct Favorite: Decodable {
    let id: String
    let name: String?
    let title: String?
    let description: String?
    let imageUrl: String?
    let resource: FavoriteResource?
    let service: FavoriteService?

    enum CodingKeys: String, CodingKey {
        case id, name, title, description, imageUrl, resource, service
    }
}
private struct FavoriteResource: Decodable {
    let type: String?
}
private struct FavoriteService: Decodable {
    let name: String?
}
private struct PlaylistsResponse: Decodable {
    let playlists: [Playlist]
}
private struct Playlist: Decodable {
    let id: String
    let name: String
    let trackCount: Int?
}

private extension CloudFavorite {
    init(_ favorite: Favorite) {
        id = favorite.id
        title = favorite.name ?? favorite.title ?? "Sonos Favorite"
        serviceName = favorite.service?.name ?? "Sonos"
        subtitle = favorite.description ?? serviceName
        imageURL = NetworkSecurityPolicy.validatedRemoteAssetURL(favorite.imageUrl)
        kind = CloudContentKind(resourceType: favorite.resource?.type)
    }
}

private extension CloudPlaylist {
    init(_ playlist: Playlist) {
        id = playlist.id
        name = playlist.name
        trackCount = max(0, playlist.trackCount ?? 0)
    }
}
