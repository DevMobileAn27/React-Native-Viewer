import Foundation

enum DevtoolsFinderStatus: Equatable {
    case lookingForLocalLinks
    case loading
    case foundConnectableLinks(Int)
    case noLinkDetectedAfterOneMinute
    case detectionFinished(Int)
    case chooseOneTarget

    func localizedDescription(language: AppLanguage = AppLanguage.current()) -> String {
        switch self {
        case .lookingForLocalLinks:
            return AppStrings.lookingForLocalLinks(language: language)
        case .loading:
            return AppStrings.text(.loading, language: language)
        case .foundConnectableLinks(let count):
            return AppStrings.foundConnectableLinks(count, language: language)
        case .noLinkDetectedAfterOneMinute:
            return AppStrings.noLinkDetectedAfterOneMinute(language: language)
        case .detectionFinished(let count):
            return AppStrings.detectionFinished(count, language: language)
        case .chooseOneTarget:
            return AppStrings.chooseOneTarget(language: language)
        }
    }
}

@MainActor
final class DevtoolsWebFinderViewModel: ObservableObject {
    @Published var manualInput = ""
    @Published private(set) var detectedCandidates: [DevtoolsConnectionCandidate] = []
    @Published private(set) var isDetecting = false
    @Published private(set) var status: DevtoolsFinderStatus = .lookingForLocalLinks
    @Published private(set) var connectionError: DevtoolsConnectionError?
    @Published private(set) var rawErrorMessage: String?
    @Published private(set) var connectingIdentifier: String?

    private let discoveryService: DevtoolsDiscoveryService
    private let connectionService: DevtoolsConnectionService
    private let onConnected: (DevtoolsConsoleSession) -> Void
    private let scanDuration: Duration
    private let scanInterval: Duration
    private var detectionTask: Task<Void, Never>?

    convenience init(
        onConnected: @escaping (DevtoolsConsoleSession) -> Void
    ) {
        self.init(
            discoveryService: DevtoolsDiscoveryService(),
            connectionService: DevtoolsConnectionService(),
            scanDuration: .seconds(60),
            scanInterval: .seconds(5),
            onConnected: onConnected
        )
    }

    init(
        discoveryService: DevtoolsDiscoveryService,
        connectionService: DevtoolsConnectionService,
        scanDuration: Duration = .seconds(60),
        scanInterval: Duration = .seconds(5),
        onConnected: @escaping (DevtoolsConsoleSession) -> Void
    ) {
        self.discoveryService = discoveryService
        self.connectionService = connectionService
        self.scanDuration = scanDuration
        self.scanInterval = scanInterval
        self.onConnected = onConnected
    }

    var isConnectingManualInput: Bool {
        connectingIdentifier == Self.manualConnectionIdentifier
    }

    var footerButtonLabel: String {
        let language = AppLanguage.current()
        return isDetecting
            ? AppStrings.text(.loading, language: language)
            : AppStrings.text(.detectLinks, language: language)
    }

    var statusMessage: String {
        status.localizedDescription(language: AppLanguage.current())
    }

    var errorMessage: String? {
        if let connectionError {
            return connectionError.localizedDescription(language: AppLanguage.current())
        }

        return rawErrorMessage
    }

    func startDetection() {
        detectionTask?.cancel()
        detectionTask = Task { [weak self] in
            await self?.runDetectionLoop()
        }
    }

    func stopDetection() {
        detectionTask?.cancel()
        detectionTask = nil
        isDetecting = false
    }

    func connectUsingManualInput() {
        Task {
            await resolveAndConnectManualInput()
        }
    }

    func connect(candidate: DevtoolsConnectionCandidate) {
        Task {
            await connect(candidate: candidate, identifier: candidate.id)
        }
    }

    private func runDetectionLoop() async {
        connectionError = nil
        rawErrorMessage = nil
        isDetecting = true
        status = .loading

        let clock = ContinuousClock()
        let deadline = clock.now + scanDuration

        repeat {
            let latestCandidates = await discoveryService.scanAvailableConnections()
            mergeDetectedCandidates(latestCandidates)

            if detectedCandidates.isEmpty {
                status = .lookingForLocalLinks
            } else {
                status = .foundConnectableLinks(detectedCandidates.count)
            }

            if clock.now >= deadline || Task.isCancelled {
                break
            }

            try? await Task.sleep(for: scanInterval)
        } while !Task.isCancelled

        isDetecting = false

        if detectedCandidates.isEmpty {
            status = .noLinkDetectedAfterOneMinute
        } else {
            status = .detectionFinished(detectedCandidates.count)
        }
    }

    private func resolveAndConnectManualInput() async {
        connectionError = nil
        rawErrorMessage = nil

        guard let resolution = DevtoolsEndpointParser.resolveInput(manualInput) else {
            connectionError = .invalidInput
            return
        }

        switch resolution {
        case .direct(let candidate):
            await connect(candidate: candidate, identifier: Self.manualConnectionIdentifier)
        case .jsonList(let url):
            connectingIdentifier = Self.manualConnectionIdentifier
            let candidates = await discoveryService.fetchCandidates(from: url)
            connectingIdentifier = nil

            guard !candidates.isEmpty else {
                connectionError = .noTargetsFound
                return
            }

            mergeDetectedCandidates(candidates)

            if candidates.count == 1, let candidate = candidates.first {
                await connect(candidate: candidate, identifier: Self.manualConnectionIdentifier)
                return
            }

            connectionError = .multipleTargetsFound(candidates.count)
            status = .chooseOneTarget
        }
    }

    private func connect(candidate: DevtoolsConnectionCandidate, identifier: String) async {
        connectingIdentifier = identifier
        connectionError = nil
        rawErrorMessage = nil

        do {
            let session = try await connectionService.connect(to: candidate)
            connectingIdentifier = nil
            onConnected(session)
        } catch {
            connectingIdentifier = nil
            if let connectionError = error as? DevtoolsConnectionError {
                self.connectionError = connectionError
            } else {
                rawErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func mergeDetectedCandidates(_ incomingCandidates: [DevtoolsConnectionCandidate]) {
        var mergedByIdentifier = Dictionary(uniqueKeysWithValues: detectedCandidates.map { ($0.id, $0) })

        for candidate in incomingCandidates {
            mergedByIdentifier[candidate.id] = candidate
        }

        detectedCandidates = mergedByIdentifier.values.sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName {
                return lhs.detailText < rhs.detailText
            }

            return lhs.displayName < rhs.displayName
        }
    }

    private static let manualConnectionIdentifier = "__manual__"
}
