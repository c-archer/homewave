import Foundation

enum NetworkSecurityError: LocalizedError {
    case invalidURL
    case responseTooLarge
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The network address is not allowed"
        case .responseTooLarge:
            return "The server response was larger than expected"
        case .unexpectedResponse:
            return "The server returned an invalid response"
        }
    }
}

enum NetworkSecurityPolicy {
    static func validatedHTTPSBaseURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            var components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    static func validatedRemoteAssetURL(_ value: String?) -> URL? {
        guard let value,
            value.count <= 4_096,
            let components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.fragment == nil
        else {
            return nil
        }
        return components.url
    }

    static func validatedAPIURL(baseURL: URL, pathComponents: [String]) throws -> URL {
        guard !pathComponents.isEmpty,
            pathComponents.allSatisfy({ isValidPathComponent($0) })
        else {
            throw NetworkSecurityError.invalidURL
        }

        let url = pathComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard url.scheme == baseURL.scheme, url.host == baseURL.host else {
            throw NetworkSecurityError.invalidURL
        }
        return url
    }

    static func sanitizedServerMessage(_ value: String?, maximumLength: Int = 300) -> String? {
        guard let value else { return nil }
        let printable = value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let trimmed = String(String.UnicodeScalarView(printable))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }

    static func isValidPathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 512
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum HardenedHTTPClient {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(
            configuration: configuration,
            delegate: RedirectRejectingDelegate(),
            delegateQueue: nil
        )
    }()

    static func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard data.count <= maximumBytes else { throw NetworkSecurityError.responseTooLarge }
        guard let http = response as? HTTPURLResponse else { throw NetworkSecurityError.unexpectedResponse }
        return (data, http)
    }
}
