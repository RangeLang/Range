import Foundation
@testable import NeatCLI
import Testing

@Suite("Package search")
struct PackageSearcherTests {
    @Test("Search URL includes GitHub repository query")
    func searchURLIncludesRepositoryQuery() throws {
        let endpoint = try #require(URL(string: "https://api.github.com/search/repositories"))

        let url = try PackageSearcher.makeSearchURL(
            endpoint: endpoint,
            query: "ui components",
            limit: 100
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(items["q"] == "ui components neat package in:name,description,readme")
        #expect(items["sort"] == "stars")
        #expect(items["order"] == "desc")
        #expect(items["per_page"] == "50")
    }

    @Test("Repository search response decodes into package results")
    func responseDecodesIntoPackageResults() throws {
        let data = """
        {
          "items": [
            {
              "full_name": "neat/example-package",
              "description": "Example Neat package",
              "stargazers_count": 42,
              "html_url": "https://github.com/neat/example-package",
              "default_branch": "main",
              "pushed_at": "2026-05-01T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let results = try PackageSearcher.decodeResults(from: data)

        #expect(results == [
            PackageSearchResult(
                package: "neat/example-package",
                description: "Example Neat package",
                stars: 42,
                url: URL(string: "https://github.com/neat/example-package")!,
                manifestURL: URL(string: "https://raw.githubusercontent.com/neat/example-package/main/Package.neat")!,
                pushedAt: "2026-05-01T00:00:00Z"
            )
        ])
    }
}
