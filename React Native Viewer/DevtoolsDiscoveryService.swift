import Foundation

struct DevtoolsDiscoveryService {
    private let session: URLSession
    private let ports: [Int]

    init(
        session: URLSession = URLSession(configuration: .ephemeral),
        ports: [Int] = Array(8081...8090) + [19000, 19001, 19006]
    ) {
        self.session = session
        self.ports = ports
    }

    func scanAvailableConnections() async -> [DevtoolsConnectionCandidate] {
        await withTaskGroup(of: [DevtoolsConnectionCandidate].self) { group in
            for endpoint in discoveryEndpoints {
                group.addTask {
                    await fetchCandidates(from: endpoint)
                }
            }

            var merged: [DevtoolsConnectionCandidate] = []
            for await candidates in group {
                merged.append(contentsOf: candidates)
            }

            return deduplicate(merged)
        }
    }

    func fetchCandidates(from endpoint: URL) async -> [DevtoolsConnectionCandidate] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return []
            }

            return try DevtoolsEndpointParser.decodeJSONList(data: data, sourceURL: endpoint)
        } catch {
            return []
        }
    }

    private var discoveryEndpoints: [URL] {
        ports.compactMap { URL(string: "http://localhost:\($0)/json/list") }
    }

    private func deduplicate(_ candidates: [DevtoolsConnectionCandidate]) -> [DevtoolsConnectionCandidate] {
        var seen = Set<String>()
        var uniqueCandidates: [DevtoolsConnectionCandidate] = []

        for candidate in candidates {
            if seen.insert(candidate.webSocketURL.absoluteString).inserted {
                uniqueCandidates.append(candidate)
            }
        }

        return uniqueCandidates.sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName {
                return lhs.detailText < rhs.detailText
            }

            return lhs.displayName < rhs.displayName
        }
    }
}
