import Foundation

enum NetworkDomainAvailability: Equatable {
    case pending
    case enabled
    case unsupported(String)
}

enum DevtoolsConnectionError: LocalizedError {
    case invalidInput
    case noTargetsFound
    case multipleTargetsFound(Int)
    case timedOut
    case unableToConnect(String)

    func localizedDescription(language: AppLanguage = AppLanguage.current()) -> String {
        switch self {
        case .invalidInput:
            return AppStrings.text(.invalidInput, language: language)
        case .noTargetsFound:
            return AppStrings.text(.noTargetsFound, language: language)
        case .multipleTargetsFound(let count):
            return AppStrings.multipleTargetsFound(count, language: language)
        case .timedOut:
            return AppStrings.text(.timedOut, language: language)
        case .unableToConnect(let detail):
            return detail
        }
    }

    var errorDescription: String? {
        localizedDescription()
    }
}

final class DevtoolsConsoleSession: ObservableObject, Identifiable {
    let id = UUID()
    let candidate: DevtoolsConnectionCandidate
    let connectedAt = Date()

    @Published private(set) var logs: [ConsoleLogEntry] = []
    @Published private(set) var networkRequests: [NetworkRequestEntry] = []
    @Published private(set) var networkDomainAvailability: NetworkDomainAvailability = .pending
    @Published private(set) var sdkIngestStatus: RNVNetworkSDKIngestStatus = .idle
    @Published private(set) var sdkSession: RNVNetworkSDKSession?

    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextCommandIdentifier = 1
    private var seenLogIdentifiers = Set<String>()
    private var networkRequestsByID: [String: NetworkRequestEntry] = [:]
    private var pendingCommandMethods: [Int: String] = [:]

    init(
        candidate: DevtoolsConnectionCandidate,
        initialLogs: [ConsoleLogEntry] = [],
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.candidate = candidate
        self.logs = initialLogs
        self.session = session
        self.seenLogIdentifiers = Set(initialLogs.map(Self.logIdentifier(for:)))
    }

    func connect() async throws {
        networkDomainAvailability = .pending
        let task = session.webSocketTask(with: candidate.webSocketURL)
        webSocketTask = task
        task.resume()

        do {
            try await waitUntilSocketResponds(task)
            startReceiving(on: task)
            try await enableConsoleDomains(on: task)
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            throw error
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session.invalidateAndCancel()
    }

    @MainActor
    func clearLogs() {
        logs.removeAll()
        seenLogIdentifiers.removeAll()
    }

    @MainActor
    func clearNetworkRequests() {
        networkRequests.removeAll()
        networkRequestsByID.removeAll()
    }

    @MainActor
    func applySDKEnvelope(_ envelope: RNVNetworkSDKEnvelope) {
        bindSDKSession(envelope.session)
        networkDomainAvailability = .enabled

        for event in envelope.events {
            applySDKEvent(event)
        }

        networkRequests = networkRequestsByID.values.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    @MainActor
    func bindSDKSession(_ sdkSession: RNVNetworkSDKSession) {
        self.sdkSession = sdkSession
        sdkIngestStatus = .clientConnected(
            appName: sdkSession.appName,
            deviceName: sdkSession.deviceName
        )
    }

    @MainActor
    func updateSDKClientState(_ state: RNVNetworkSDKClientState?) {
        guard let state else {
            sdkIngestStatus = .idle
            return
        }

        sdkSession = state.session

        switch state.connectionStatus {
        case .connected:
            sdkIngestStatus = .clientConnected(
                appName: state.session.appName,
                deviceName: state.session.deviceName
            )
        case .disconnected:
            sdkIngestStatus = .idle
        case .failed(let detail):
            sdkIngestStatus = .failed(detail)
        }
    }

    var sdkSessionID: String? {
        sdkSession?.id
    }

    func sdkMatchScore(for sdkSession: RNVNetworkSDKSession) -> Int {
        if let boundSessionID = self.sdkSessionID, boundSessionID != sdkSession.id {
            return .min
        }

        let haystacks = [
            Self.normalizedMatchValue(candidate.displayName),
            Self.normalizedMatchValue(candidate.detailText),
            Self.normalizedMatchValue(candidate.webSocketURL.absoluteString),
        ]

        let bundleIdentifier = Self.normalizedMatchValue(sdkSession.bundleIdentifier)
        let appName = Self.normalizedMatchValue(sdkSession.appName)
        let deviceName = Self.normalizedMatchValue(sdkSession.deviceName)
        let detailText = Self.normalizedMatchValue(candidate.detailText)

        var score = 0

        if !bundleIdentifier.isEmpty, haystacks.contains(where: { $0.contains(bundleIdentifier) }) {
            score += 100
        }

        if !appName.isEmpty, haystacks.contains(where: { $0.contains(appName) }) {
            score += 60
        }

        if !deviceName.isEmpty, haystacks.contains(where: { $0.contains(deviceName) }) {
            score += 40
        }

        if detailText.contains("reactnative") ||
            detailText.contains("bridgeless") ||
            detailText.contains("hermes") {
            score += 15
        }

        if detailText.contains("reanimated") {
            score -= 20
        }

        return score > 0 ? score : .min
    }

    private static func normalizedMatchValue(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }

    private func startReceiving(on task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveMessages(from: task)
        }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    await handleIncomingData(data)
                case .string(let text):
                    await handleIncomingData(Data(text.utf8))
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
    }

    private func handleIncomingData(_ data: Data) async {
        await MainActor.run {
            if let response = DevtoolsConsoleEventParser.parseCommandResponse(data) {
                handleCommandResponse(response)
                return
            }

            if let entry = DevtoolsConsoleEventParser.parseNotification(data) {
                let identifier = Self.logIdentifier(for: entry)
                guard seenLogIdentifiers.insert(identifier).inserted else {
                    return
                }

                logs.append(entry)
            }

            if let event = DevtoolsConsoleEventParser.parseNetworkNotification(data) {
                applyNetworkEvent(event)
            }
        }
    }

    private static func logIdentifier(for entry: ConsoleLogEntry) -> String {
        let timestampInMilliseconds = Int(entry.timestamp.timeIntervalSince1970 * 1_000)
        return "\(timestampInMilliseconds)|\(entry.level.rawValue)|\(entry.source)|\(entry.message)"
    }

    private func enableConsoleDomains(on task: URLSessionWebSocketTask) async throws {
        try await sendCommand("Runtime.enable", using: task)
        try await sendCommand("Log.enable", using: task)
        try await sendCommand("Console.enable", using: task)
        try await sendCommand("Network.enable", using: task)
    }

    private func sendCommand(_ method: String, using task: URLSessionWebSocketTask) async throws {
        let commandIdentifier = nextCommandIdentifier
        let payload: [String: Any] = [
            "id": commandIdentifier,
            "method": method
        ]
        nextCommandIdentifier += 1
        pendingCommandMethods[commandIdentifier] = method

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DevtoolsConnectionError.unableToConnect(
                AppStrings.text(.unableToEncodeWebSocketCommand)
            )
        }

        try await task.send(.string(text))
    }

    private func waitUntilSocketResponds(_ task: URLSessionWebSocketTask) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.sendPing(on: task)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw DevtoolsConnectionError.timedOut
            }

            guard let _ = try await group.next() else {
                throw DevtoolsConnectionError.timedOut
            }
            group.cancelAll()
        }
    }

    private func sendPing(on task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: DevtoolsConnectionError.unableToConnect(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func applyNetworkEvent(_ event: NetworkRequestEvent) {
        if case .pending = networkDomainAvailability {
            networkDomainAvailability = .enabled
        }

        switch event {
        case .requestWillBeSent(let requestId, let timestamp, let method, let url, let headers, let postData, let resourceType):
            var entry = networkRequestsByID[requestId] ?? NetworkRequestEntry(
                id: requestId,
                timestamp: timestamp,
                method: method,
                url: url
            )
            entry.timestamp = timestamp
            entry.method = method
            entry.url = url
            entry.requestHeaders = headers
            entry.requestBody = postData
            entry.resourceType = resourceType ?? entry.resourceType
            networkRequestsByID[requestId] = entry

        case .responseReceived(let requestId, let timestamp, let statusCode, let statusText, let mimeType, let headers, let resourceType):
            var entry = networkRequestsByID[requestId] ?? NetworkRequestEntry(
                id: requestId,
                timestamp: timestamp,
                method: "GET",
                url: requestId
            )
            entry.statusCode = statusCode
            entry.statusText = statusText
            entry.mimeType = mimeType
            entry.responseHeaders = headers
            entry.resourceType = resourceType ?? entry.resourceType
            networkRequestsByID[requestId] = entry

        case .loadingFinished(let requestId, let timestamp, let encodedDataLength):
            var entry = networkRequestsByID[requestId] ?? NetworkRequestEntry(
                id: requestId,
                timestamp: timestamp,
                method: "GET",
                url: requestId
            )
            entry.encodedDataLength = encodedDataLength
            entry.finishedAt = timestamp
            networkRequestsByID[requestId] = entry

        case .loadingFailed(let requestId, let timestamp, let errorText):
            var entry = networkRequestsByID[requestId] ?? NetworkRequestEntry(
                id: requestId,
                timestamp: timestamp,
                method: "GET",
                url: requestId
            )
            entry.failureText = errorText
            entry.finishedAt = timestamp
            networkRequestsByID[requestId] = entry
        }

        networkRequests = networkRequestsByID.values.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    @MainActor
    private func applySDKEvent(_ event: RNVNetworkSDKEvent) {
        var entry = networkRequestsByID[event.requestId] ?? NetworkRequestEntry(
            id: event.requestId,
            timestamp: event.timestamp,
            method: event.method.nonEmpty ?? "REQUEST",
            url: event.url.nonEmpty ?? event.requestId
        )

        entry.timestamp = event.timestamp

        if let method = event.method.nonEmpty {
            entry.method = method
        }

        if let url = event.url.nonEmpty {
            entry.url = url
        }

        if !event.requestHeaders.isEmpty {
            entry.requestHeaders = event.requestHeaders
        }

        if !event.responseHeaders.isEmpty {
            entry.responseHeaders = event.responseHeaders
        }

        if let requestBody = event.requestBody?.nonEmpty ?? event.requestBodyPreview?.nonEmpty {
            entry.requestBody = requestBody
        }

        if let responseBody = event.responseBody?.nonEmpty ?? event.responseBodyPreview?.nonEmpty {
            entry.responseBody = responseBody
        }

        if let requestKind = event.requestKind?.nonEmpty {
            entry.resourceType = requestKind.uppercased()
        }

        if let statusCode = event.statusCode {
            entry.statusCode = statusCode
        }

        if let statusText = event.statusText?.nonEmpty {
            entry.statusText = statusText
        }

        if let durationMs = event.durationMs {
            entry.durationMs = durationMs
        }

        switch event.phase {
        case .request:
            break
        case .response:
            entry.finishedAt = event.timestamp
        case .error:
            entry.failureText = event.errorMessage?.nonEmpty ?? "Request failed"
            entry.finishedAt = event.timestamp
        }

        networkRequestsByID[event.requestId] = entry
    }

    @MainActor
    private func handleCommandResponse(_ response: DebuggerCommandResponse) {
        guard let method = pendingCommandMethods.removeValue(forKey: response.id) else {
            return
        }

        guard method == "Network.enable" else {
            return
        }

        if let errorMessage = response.errorMessage {
            networkDomainAvailability = .unsupported(errorMessage)
        } else {
            networkDomainAvailability = .enabled
        }
    }
}

struct DevtoolsConnectionService {
    func connect(to candidate: DevtoolsConnectionCandidate) async throws -> DevtoolsConsoleSession {
        let session = DevtoolsConsoleSession(candidate: candidate)
        try await session.connect()
        return session
    }
}
