import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct PackageSearchResult: Equatable {
    let package: String
    let description: String?
    let stars: Int
    let url: URL
    let manifestURL: URL
    let pushedAt: String?
}

struct PackageSearcher {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.github.com/search/repositories")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func search(query: String, limit: Int) throws -> [PackageSearchResult] {
        let request = try makeRequest(query: query, limit: max(limit, 25))
        let (data, response) = try run(request)

        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = GitHubSearchErrorMessage.decode(from: data)
                throw PackageSearchError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: message
                )
            }
        }

        let candidates = try Self.decodeResults(from: data)
        var verified: [PackageSearchResult] = []

        for candidate in candidates {
            if try hasManifest(at: candidate.manifestURL) {
                verified.append(candidate)
            }

            if verified.count >= limit {
                break
            }
        }

        return verified
    }

    func makeRequest(query: String, limit: Int) throws -> URLRequest {
        var request = URLRequest(url: try Self.makeSearchURL(endpoint: endpoint, query: query, limit: limit))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("neat-cli", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func makeSearchURL(endpoint: URL, query: String, limit: Int) throws -> URL {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw PackageSearchError.emptyQuery
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(
                name: "q",
                value: "\(trimmedQuery) neat package in:name,description,readme"
            ),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 50)))"),
        ]

        guard let url = components?.url else {
            throw PackageSearchError.invalidSearchURL
        }

        return url
    }

    static func decodeResults(from data: Data) throws -> [PackageSearchResult] {
        let response = try JSONDecoder().decode(GitHubRepositorySearchResponse.self, from: data)
        return response.items.map { repository in
            PackageSearchResult(
                package: repository.fullName,
                description: repository.description,
                stars: repository.stargazersCount,
                url: repository.htmlURL,
                manifestURL: repository.manifestURL,
                pushedAt: repository.pushedAt
            )
        }
    }

    private func hasManifest(at url: URL) throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("neat-cli", forHTTPHeaderField: "User-Agent")

        let (_, response) = try run(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200..<300).contains(httpResponse.statusCode)
    }

    private func run(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = PackageSearchResponseBox()

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result.store(.failure(error))
                return
            }

            guard let data, let response else {
                result.store(.failure(PackageSearchError.emptyResponse))
                return
            }

            result.store(.success((data, response)))
        }

        task.resume()
        semaphore.wait()

        switch result.load() {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw PackageSearchError.emptyResponse
        }
    }
}

private final class PackageSearchResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<(Data, URLResponse), Error>?

    func store(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<(Data, URLResponse), Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

enum PackageSearchError: Error, CustomStringConvertible {
    case emptyQuery
    case invalidSearchURL
    case emptyResponse
    case requestFailed(statusCode: Int, message: String?)

    var description: String {
        switch self {
        case .emptyQuery:
            return "Search query cannot be empty."
        case .invalidSearchURL:
            return "Could not build package search URL."
        case .emptyResponse:
            return "Package search returned an empty response."
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Package search failed with HTTP \(statusCode): \(message)"
            }
            return "Package search failed with HTTP \(statusCode)."
        }
    }
}

private struct GitHubRepositorySearchResponse: Decodable {
    let items: [GitHubRepository]
}

private struct GitHubRepository: Decodable {
    let fullName: String
    let description: String?
    let stargazersCount: Int
    let htmlURL: URL
    let defaultBranch: String
    let pushedAt: String?

    var manifestURL: URL {
        URL(string: "https://raw.githubusercontent.com/\(fullName)/\(defaultBranch)/Package.neat")!
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case stargazersCount = "stargazers_count"
        case htmlURL = "html_url"
        case defaultBranch = "default_branch"
        case pushedAt = "pushed_at"
    }
}

private struct GitHubSearchErrorMessage: Decodable {
    let message: String?

    static func decode(from data: Data) -> String? {
        try? JSONDecoder().decode(Self.self, from: data).message
    }
}
