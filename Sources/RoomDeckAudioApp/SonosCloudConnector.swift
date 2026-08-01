import AppKit
import Foundation
import Security

struct SonosCloudSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum SonosCloudError: LocalizedError {
    case invalidConfiguration
    case invalidCallback
    case stateMismatch
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Sonos sign-in is not configured in this build"
        case .invalidCallback:
            return "Sonos returned an invalid sign-in callback"
        case .stateMismatch:
            return "Sonos sign-in could not be verified"
        case .requestFailed(let message):
            return message
        }
    }
}

struct SonosAuthCallback: Equatable, Sendable {
    let ticket: String
    let state: String

    init?(url: URL) {
        guard url.scheme?.lowercased() == ProductIdentity.callbackScheme,
            url.host?.lowercased() == ProductIdentity.callbackHost,
            url.path.isEmpty || url.path == "/",
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else {
            return nil
        }

        let tickets = queryItems.filter { $0.name == "ticket" }.compactMap(\.value)
        let states = queryItems.filter { $0.name == "state" }.compactMap(\.value)
        guard tickets.count == 1,
            states.count == 1,
            UUID(uuidString: tickets[0]) != nil,
            UUID(uuidString: states[0]) != nil
        else {
            return nil
        }

        ticket = tickets[0]
        state = states[0]
    }
}

actor SonosCloudConnector {
    private let sessionStore = SonosCloudSessionStore()

    func loginURL(state: String) -> URL? {
        guard let baseURL = authBaseURL else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("sonos/login"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "state", value: state)]
        return components?.url
    }

    func openLogin(state: String) throws {
        guard let url = loginURL(state: state) else { throw SonosCloudError.invalidConfiguration }
        guard NSWorkspace.shared.open(url) else {
            throw SonosCloudError.requestFailed("RoomDeck Audio could not open the Sonos sign-in page")
        }
    }

    func completeLogin(ticket: String, expectedState: String) async throws -> SonosCloudSession {
        guard let baseURL = authBaseURL else { throw SonosCloudError.invalidConfiguration }
        guard UUID(uuidString: ticket) != nil, UUID(uuidString: expectedState) != nil else {
            throw SonosCloudError.invalidCallback
        }
        let url = baseURL.appendingPathComponent("sonos/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(SessionTicketRequest(ticket: ticket))

        let (data, httpResponse) = try await HardenedHTTPClient.data(for: request, maximumBytes: 128 * 1_024)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SonosCloudError.requestFailed(Self.errorMessage(from: data, fallback: "Sonos sign-in ticket expired"))
        }
        let result = try JSONDecoder().decode(SessionTicketResponse.self, from: data)
        guard result.clientState == expectedState else { throw SonosCloudError.stateMismatch }
        try Self.validate(result.tokens)
        let session = SonosCloudSession(
            accessToken: result.tokens.accessToken,
            refreshToken: result.tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.tokens.expiresIn))
        )
        try sessionStore.save(session)
        return session
    }

    func hasSession() -> Bool {
        sessionStore.load() != nil
    }

    func accessToken() async throws -> String {
        guard var current = sessionStore.load() else { throw SonosCloudError.requestFailed("Sign in with Sonos to continue") }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }

        guard let baseURL = authBaseURL else { throw SonosCloudError.invalidConfiguration }
        let refreshURL = baseURL.appendingPathComponent("sonos/refresh")
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["refresh_token": current.refreshToken])

        let (data, httpResponse) = try await HardenedHTTPClient.data(for: request, maximumBytes: 128 * 1_024)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SonosCloudError.requestFailed(Self.errorMessage(from: data, fallback: "Could not refresh your Sonos session"))
        }
        let token = try JSONDecoder().decode(SonosTokenResponse.self, from: data)
        try Self.validate(token)
        current = SonosCloudSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        )
        try sessionStore.save(current)
        return current.accessToken
    }

    func disconnect() throws {
        try sessionStore.clear()
    }

    private var authBaseURL: URL? {
        let configured =
            (Bundle.main.object(forInfoDictionaryKey: "SonosAuthBaseURL") as? String)
            ?? ProcessInfo.processInfo.environment["ROOMDECK_SONOS_AUTH_BASE_URL"]
        guard let configured, !configured.isEmpty else { return nil }
        return NetworkSecurityPolicy.validatedHTTPSBaseURL(configured)
    }

    private static func errorMessage(from data: Data, fallback: String) -> String {
        let message = try? JSONDecoder().decode(APIError.self, from: data).error
        return NetworkSecurityPolicy.sanitizedServerMessage(message) ?? fallback
    }

    private static func validate(_ token: SonosTokenResponse) throws {
        guard !token.accessToken.isEmpty,
            token.accessToken.count <= 16_384,
            !token.refreshToken.isEmpty,
            token.refreshToken.count <= 16_384,
            token.expiresIn > 0
        else {
            throw SonosCloudError.requestFailed("Sonos returned an invalid session")
        }
    }
}

private struct SessionTicketRequest: Encodable {
    let ticket: String
}

private struct SessionTicketResponse: Decodable {
    let tokens: SonosTokenResponse
    let clientState: String
}

struct SonosTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct APIError: Decodable {
    let error: String
}

private final class SonosCloudSessionStore: @unchecked Sendable {
    private let service = "uk.co.roomdeck.audio.sonos-cloud"
    private let account = "sonos-session"

    func load() -> SonosCloudSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(SonosCloudSession.self, from: data)
    }

    func save(_ session: SonosCloudSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            insert[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw SonosCloudError.requestFailed("Could not save the Sonos session to Keychain")
            }
        } else if status != errSecSuccess {
            throw SonosCloudError.requestFailed("Could not update the Sonos session in Keychain")
        }
    }

    func clear() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SonosCloudError.requestFailed("Could not remove the Sonos session from Keychain")
        }
    }
}
