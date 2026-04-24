import Foundation

enum DevtoolsEndpointParser {
    static func resolveInput(_ input: String) -> DevtoolsInputResolution? {
        let trimmedInput = input.trimmed
        guard !trimmedInput.isEmpty else {
            return nil
        }

        let normalizedInput = normalizeInput(trimmedInput)
        guard let url = URL(string: normalizedInput) else {
            return nil
        }

        return resolveURL(url)
    }

    static func decodeJSONList(data: Data, sourceURL: URL) throws -> [DevtoolsConnectionCandidate] {
        let pages = try JSONDecoder().decode([InspectablePage].self, from: data)

        return pages.compactMap { page in
            guard
                let rawWebSocketURL = page.rawWebSocketURL?.trimmed.nonEmpty,
                let webSocketURL = URL(string: rawWebSocketURL)
            else {
                return nil
            }

            let displayName = page.title?.trimmed.nonEmpty
                ?? page.id?.trimmed.nonEmpty
                ?? sourceURL.hostPortLabel
                ?? webSocketURL.hostPortLabel
                ?? AppStrings.text(.unknownTarget)

            let detailText = page.description?.trimmed.nonEmpty
                ?? page.pageURL?.trimmed.nonEmpty
                ?? page.vm?.trimmed.nonEmpty
                ?? webSocketURL.pathWithQuery

            return DevtoolsConnectionCandidate(
                id: page.id?.trimmed.nonEmpty ?? webSocketURL.absoluteString,
                displayName: displayName,
                detailText: detailText,
                webSocketURL: webSocketURL,
                discoveryURL: sourceURL
            )
        }
    }

    private static func resolveURL(_ url: URL) -> DevtoolsInputResolution? {
        switch url.scheme?.lowercased() {
        case "ws", "wss":
            return .direct(candidate(for: url, displayName: url.hostPortLabel ?? url.absoluteString))
        case "http", "https":
            if let embeddedWebSocketURL = embeddedWebSocketURL(in: url) {
                return .direct(candidate(for: embeddedWebSocketURL, displayName: embeddedWebSocketURL.hostPortLabel ?? embeddedWebSocketURL.absoluteString))
            }

            let normalizedPath = url.path.lowercased()
            if normalizedPath.isEmpty || normalizedPath == "/" {
                var jsonListURL = url
                jsonListURL.append(path: "json")
                jsonListURL.append(path: "list")
                return .jsonList(jsonListURL)
            }

            if normalizedPath == "/json/list" {
                return .jsonList(url)
            }

            if normalizedPath.contains("/inspector/debug") {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.scheme = url.scheme == "https" ? "wss" : "ws"
                if let webSocketURL = components?.url {
                    return .direct(candidate(for: webSocketURL, displayName: webSocketURL.hostPortLabel ?? webSocketURL.absoluteString))
                }
            }

            return nil
        default:
            return nil
        }
    }

    private static func candidate(for webSocketURL: URL, displayName: String) -> DevtoolsConnectionCandidate {
        DevtoolsConnectionCandidate(
            displayName: displayName,
            detailText: webSocketURL.pathWithQuery,
            webSocketURL: webSocketURL
        )
    }

    private static func normalizeInput(_ input: String) -> String {
        if input.hasPrefix("/json/list") {
            return "http://localhost:8081\(input)"
        }

        if input.hasPrefix("localhost:") || input.hasPrefix("127.0.0.1:") {
            return "http://\(input)"
        }

        return input
    }

    private static func embeddedWebSocketURL(in url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let keys = ["ws", "websocketDebuggerUrl", "webSocketDebuggerUrl"]
        for key in keys {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value?.removingPercentEncoding ?? components.queryItems?.first(where: { $0.name == key })?.value,
               let webSocketURL = URL(string: value) {
                return webSocketURL
            }
        }

        return nil
    }
}

private struct InspectablePage: Decodable {
    let id: String?
    let title: String?
    let description: String?
    let pageURL: String?
    let vm: String?
    let webSocketDebuggerUrl: String?
    let websocketDebuggerUrl: String?

    var rawWebSocketURL: String? {
        webSocketDebuggerUrl ?? websocketDebuggerUrl
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case pageURL = "url"
        case vm
        case webSocketDebuggerUrl
        case websocketDebuggerUrl
    }
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension URL {
    var hostPortLabel: String? {
        guard let host else {
            return nil
        }

        if let port {
            return "\(host):\(port)"
        }

        return host
    }

    var pathWithQuery: String {
        if let query, !query.isEmpty {
            return "\(path)?\(query)"
        }

        return path.isEmpty ? absoluteString : path
    }
}
