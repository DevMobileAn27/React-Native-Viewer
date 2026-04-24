import Foundation

struct DevtoolsConnectionCandidate: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
    let detailText: String
    let webSocketURL: URL
    let discoveryURL: URL?

    init(
        id: String? = nil,
        displayName: String,
        detailText: String,
        webSocketURL: URL,
        discoveryURL: URL? = nil
    ) {
        self.id = id ?? webSocketURL.absoluteString
        self.displayName = displayName
        self.detailText = detailText
        self.webSocketURL = webSocketURL
        self.discoveryURL = discoveryURL
    }
}

enum DevtoolsInputResolution: Equatable {
    case direct(DevtoolsConnectionCandidate)
    case jsonList(URL)
}
