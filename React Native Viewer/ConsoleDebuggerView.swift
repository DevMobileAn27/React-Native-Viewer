import AppKit
import SwiftUI

enum ConsoleLogLevel: String, CaseIterable, Hashable {
    case log
    case info
    case warn
    case error

    var title: String {
        rawValue.uppercased()
    }

    var badgeColor: Color {
        switch self {
        case .log:
            return Color(red: 0.35, green: 0.63, blue: 0.96)
        case .info:
            return Color(red: 0.22, green: 0.71, blue: 0.56)
        case .warn:
            return Color(red: 0.89, green: 0.63, blue: 0.20)
        case .error:
            return Color(red: 0.86, green: 0.32, blue: 0.33)
        }
    }

    init(runtimeType: String?) {
        switch runtimeType?.lowercased() {
        case "info":
            self = .info
        case "warning":
            self = .warn
        case "error", "assert":
            self = .error
        default:
            self = .log
        }
    }

    init(logEntryLevel: String?) {
        switch logEntryLevel?.lowercased() {
        case "info":
            self = .info
        case "warning":
            self = .warn
        case "error":
            self = .error
        default:
            self = .log
        }
    }
}

enum DebuggerLogTab: String, CaseIterable, Identifiable {
    case console
    case network
    case compareText
    case jsonGraph

    var id: String {
        rawValue
    }

    func title(language: AppLanguage = AppLanguage.current()) -> String {
        switch self {
        case .console:
            return AppStrings.text(.consoleLogTabTitle, language: language)
        case .network:
            return AppStrings.text(.networkLogTabTitle, language: language)
        case .compareText:
            switch language.resolvedLanguage() {
            case .english:
                return "Compare Text"
            case .vietnamese:
                return "So sánh văn bản"
            }
        case .jsonGraph:
            switch language.resolvedLanguage() {
            case .english:
                return "Json Graph"
            case .vietnamese:
                return "Đồ thị JSON"
            }
        }
    }

    var showsWorkspaceHeader: Bool {
        self != .jsonGraph
    }
}

enum CompareTextResult: Equatable {
    case idle
    case same
    case different

    func title(language: AppLanguage) -> String? {
        switch self {
        case .idle:
            return nil
        case .same:
            switch language.resolvedLanguage() {
            case .english:
                return "Same"
            case .vietnamese:
                return "Giống nhau"
            }
        case .different:
            switch language.resolvedLanguage() {
            case .english:
                return "Different"
            case .vietnamese:
                return "Khác nhau"
            }
        }
    }
}

enum CompareTextMode: Equatable {
    case editing
    case results
}

struct CompareTextSegment: Equatable {
    let text: String
    let isDifferent: Bool
}

enum ConsoleLogSortOrder: String {
    case oldestFirst
    case newestFirst

    mutating func toggle() {
        self = self == .oldestFirst ? .newestFirst : .oldestFirst
    }
}

enum DebuggerSidebarDisplayMode: String {
    case expanded
    case iconOnly

    var toggleIcon: String {
        switch self {
        case .expanded:
            return "sidebar.left"
        case .iconOnly:
            return "sidebar.right"
        }
    }
}

enum ConsoleScrollMetrics {
    enum ChangeSource {
        case scrollPosition
        case contentSize
    }

    static let bottomAnchorID = "console-bottom-anchor"
    static let followTailThreshold: CGFloat = 0.98

    static func scrollProgress(contentHeight: CGFloat, visibleHeight: CGFloat, visibleMaxY: CGFloat) -> CGFloat {
        let maxScrollableDistance = max(contentHeight - visibleHeight, 0)
        guard maxScrollableDistance > 0 else {
            return 1
        }

        let currentOffset = max(visibleMaxY - visibleHeight, 0)
        return min(max(currentOffset / maxScrollableDistance, 0), 1)
    }

    static func isPinnedToBottom(contentHeight: CGFloat, visibleHeight: CGFloat, visibleMaxY: CGFloat) -> Bool {
        scrollProgress(
            contentHeight: contentHeight,
            visibleHeight: visibleHeight,
            visibleMaxY: visibleMaxY
        ) >= followTailThreshold
    }

    static func pinnedState(
        currentlyPinned: Bool,
        contentHeight: CGFloat,
        visibleHeight: CGFloat,
        visibleMaxY: CGFloat,
        changeSource: ChangeSource
    ) -> Bool {
        guard contentHeight > 0, visibleHeight > 0, visibleMaxY > 0 else {
            return currentlyPinned
        }

        let pinnedToBottom = isPinnedToBottom(
            contentHeight: contentHeight,
            visibleHeight: visibleHeight,
            visibleMaxY: visibleMaxY
        )

        switch changeSource {
        case .scrollPosition:
            return pinnedToBottom
        case .contentSize:
            return currentlyPinned || pinnedToBottom
        }
    }
}

private struct ConsoleScrollPositionObserver: NSViewRepresentable {
    let onMetricsChange: (CGFloat, CGFloat, CGFloat, ConsoleScrollMetrics.ChangeSource) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMetricsChange: onMetricsChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.enclosingScrollView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMetricsChange = onMetricsChange
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.enclosingScrollView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onMetricsChange: (CGFloat, CGFloat, CGFloat, ConsoleScrollMetrics.ChangeSource) -> Void

        private weak var observedScrollView: NSScrollView?
        private weak var observedDocumentView: NSView?
        private var observers: [NSObjectProtocol] = []

        init(onMetricsChange: @escaping (CGFloat, CGFloat, CGFloat, ConsoleScrollMetrics.ChangeSource) -> Void) {
            self.onMetricsChange = onMetricsChange
        }

        func attach(to scrollView: NSScrollView?) {
            let documentView = scrollView?.documentView

            guard observedScrollView !== scrollView || observedDocumentView !== documentView else {
                notify(changeSource: .scrollPosition)
                return
            }

            detach()
            observedScrollView = scrollView
            observedDocumentView = documentView

            guard let scrollView else {
                return
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            documentView?.postsFrameChangedNotifications = true

            let notificationCenter = NotificationCenter.default
            observers.append(
                notificationCenter.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.notify(changeSource: .scrollPosition)
                }
            )

            if let documentView {
                observers.append(
                    notificationCenter.addObserver(
                        forName: NSView.frameDidChangeNotification,
                        object: documentView,
                        queue: .main
                    ) { [weak self] _ in
                        self?.notify(changeSource: .contentSize)
                    }
                )
            }

            notify(changeSource: .scrollPosition)
        }

        func detach() {
            let notificationCenter = NotificationCenter.default
            observers.forEach(notificationCenter.removeObserver)
            observers.removeAll()
            observedScrollView = nil
            observedDocumentView = nil
        }

        private func notify(changeSource: ConsoleScrollMetrics.ChangeSource) {
            guard
                let scrollView = observedScrollView,
                let documentView = scrollView.documentView
            else {
                return
            }

            let visibleRect = scrollView.contentView.documentVisibleRect
            onMetricsChange(
                documentView.frame.height,
                visibleRect.height,
                visibleRect.maxY,
                changeSource
            )
        }

        deinit {
            detach()
        }
    }
}

private enum DebuggerWorkspaceDestination: String, CaseIterable, Identifiable {
    case device
    case settings

    var id: String {
        rawValue
    }
}

enum NetworkRequestState: Equatable {
    case pending
    case succeeded
    case failed
}

struct NetworkRequestEntry: Identifiable, Equatable {
    let id: String
    var timestamp: Date
    var method: String
    var url: String
    var resourceType: String?
    var statusCode: Int?
    var statusText: String?
    var mimeType: String?
    var encodedDataLength: Int64?
    var requestHeaders: [String: String]
    var responseHeaders: [String: String]
    var requestBody: String?
    var responseBody: String?
    var durationMs: Int?
    var failureText: String?
    var finishedAt: Date?

    init(
        id: String,
        timestamp: Date,
        method: String,
        url: String,
        resourceType: String? = nil,
        statusCode: Int? = nil,
        statusText: String? = nil,
        mimeType: String? = nil,
        encodedDataLength: Int64? = nil,
        requestHeaders: [String: String] = [:],
        responseHeaders: [String: String] = [:],
        requestBody: String? = nil,
        responseBody: String? = nil,
        durationMs: Int? = nil,
        failureText: String? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.resourceType = resourceType
        self.statusCode = statusCode
        self.statusText = statusText
        self.mimeType = mimeType
        self.encodedDataLength = encodedDataLength
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.durationMs = durationMs
        self.failureText = failureText
        self.finishedAt = finishedAt
    }

    var state: NetworkRequestState {
        if failureText != nil {
            return .failed
        }

        if statusCode != nil || finishedAt != nil {
            return .succeeded
        }

        return .pending
    }

    var statusSummary: String {
        switch state {
        case .pending:
            return "Pending"
        case .succeeded:
            if let statusCode {
                if let statusText, !statusText.isEmpty {
                    return "\(statusCode) \(statusText)"
                }

                return "\(statusCode)"
            }

            return "Finished"
        case .failed:
            return failureText ?? "Failed"
        }
    }

    var metadataSummary: String {
        var parts: [String] = [statusSummary]

        if let resourceType, !resourceType.isEmpty {
            parts.append(resourceType.uppercased())
        }

        if let mimeType, !mimeType.isEmpty {
            parts.append(mimeType)
        }

        if let encodedDataLength, encodedDataLength > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: encodedDataLength, countStyle: .file))
        }

        if let durationMs, durationMs >= 0 {
            parts.append("\(durationMs) ms")
        }

        return parts.joined(separator: " • ")
    }
}

struct ConsoleLogEntry: Identifiable {
    static let collapseThreshold = 150

    let id: UUID
    let timestamp: Date
    let level: ConsoleLogLevel
    let message: String
    let source: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: ConsoleLogLevel,
        message: String,
        source: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.source = source
    }

    var isCollapsible: Bool {
        switch level {
        case .warn, .error:
            return message.count > Self.collapseThreshold
        case .log, .info:
            return false
        }
    }

    func displayMessage(isExpanded: Bool) -> String {
        guard isCollapsible, !isExpanded else {
            return message
        }

        let prefix = String(message.prefix(Self.collapseThreshold)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

}

enum ConsoleTimestampFormatter {
    static func string(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = AppLanguage.current().resolvedLocale,
        timeZone: TimeZone = .current
    ) -> String {
        var normalizedCalendar = calendar
        normalizedCalendar.timeZone = timeZone

        let timeOnlyFormatter = DateFormatter()
        timeOnlyFormatter.locale = locale
        timeOnlyFormatter.timeZone = timeZone
        timeOnlyFormatter.dateFormat = "HH:mm:ss"

        guard normalizedCalendar.isDate(date, inSameDayAs: now) == false else {
            return timeOnlyFormatter.string(from: date)
        }

        let datedFormatter = DateFormatter()
        datedFormatter.locale = locale
        datedFormatter.timeZone = timeZone
        datedFormatter.dateFormat = "dd MMM HH:mm:ss"
        return datedFormatter.string(from: date)
    }
}

@MainActor
final class ConsoleDebuggerViewModel: ObservableObject {
    struct Persistence {
        let userDefaults: UserDefaults

        static let shared = Persistence(userDefaults: .standard)

        private func key(for tab: DebuggerLogTab, suffix: String) -> String {
            "ConsoleDebuggerViewModel.\(tab.rawValue).\(suffix)"
        }

        private var sortOrderKey: String {
            "ConsoleDebuggerViewModel.consoleLogSortOrder"
        }

        private var sidebarDisplayModeKey: String {
            "ConsoleDebuggerViewModel.sidebarDisplayMode"
        }

        func loadSortOrder() -> ConsoleLogSortOrder {
            guard
                let rawValue = userDefaults.string(forKey: sortOrderKey),
                let sortOrder = ConsoleLogSortOrder(rawValue: rawValue)
            else {
                return .newestFirst
            }

            return sortOrder
        }

        func saveSortOrder(_ sortOrder: ConsoleLogSortOrder) {
            userDefaults.set(sortOrder.rawValue, forKey: sortOrderKey)
        }

        func loadSidebarDisplayMode() -> DebuggerSidebarDisplayMode {
            guard
                let rawValue = userDefaults.string(forKey: sidebarDisplayModeKey),
                let mode = DebuggerSidebarDisplayMode(rawValue: rawValue)
            else {
                return .expanded
            }

            return mode
        }

        func saveSidebarDisplayMode(_ mode: DebuggerSidebarDisplayMode) {
            userDefaults.set(mode.rawValue, forKey: sidebarDisplayModeKey)
        }

        func loadDraftSearchText(for tab: DebuggerLogTab) -> String {
            userDefaults.string(forKey: key(for: tab, suffix: "draftSearchText")) ?? ""
        }

        func saveDraftSearchText(_ text: String, for tab: DebuggerLogTab) {
            userDefaults.set(text, forKey: key(for: tab, suffix: "draftSearchText"))
        }

        func loadPinnedSearchTerms(for tab: DebuggerLogTab) -> [String] {
            userDefaults.stringArray(forKey: key(for: tab, suffix: "pinnedSearchTerms")) ?? []
        }

        func savePinnedSearchTerms(_ terms: [String], for tab: DebuggerLogTab) {
            userDefaults.set(terms, forKey: key(for: tab, suffix: "pinnedSearchTerms"))
        }
    }

    private let persistence: Persistence

    @Published var searchText = ""
    @Published private(set) var searchTerms: [String] = []
    @Published var networkSearchText = ""
    @Published private(set) var networkSearchTerms: [String] = []
    @Published private(set) var consoleLogSortOrder: ConsoleLogSortOrder = .newestFirst
    @Published var selectedLevels: Set<ConsoleLogLevel>
    @Published var compareFirstText = ""
    @Published var compareSecondText = ""
    @Published private(set) var compareMode: CompareTextMode = .editing
    @Published private(set) var compareResult: CompareTextResult = .idle
    @Published private(set) var compareFirstSegments: [CompareTextSegment] = []
    @Published private(set) var compareSecondSegments: [CompareTextSegment] = []
    @Published private(set) var logs: [ConsoleLogEntry]
    @Published private(set) var networkRequests: [NetworkRequestEntry]

    init(
        logs: [ConsoleLogEntry] = [],
        networkRequests: [NetworkRequestEntry] = [],
        persistence: Persistence? = nil
    ) {
        let resolvedPersistence = persistence ?? .shared
        self.persistence = resolvedPersistence
        self.logs = logs
        self.networkRequests = networkRequests
        self.searchText = resolvedPersistence.loadDraftSearchText(for: .console)
        self.searchTerms = resolvedPersistence.loadPinnedSearchTerms(for: .console)
        self.networkSearchText = resolvedPersistence.loadDraftSearchText(for: .network)
        self.networkSearchTerms = resolvedPersistence.loadPinnedSearchTerms(for: .network)
        self.consoleLogSortOrder = resolvedPersistence.loadSortOrder()
        self.selectedLevels = Set(ConsoleLogLevel.allCases)
    }

    var filteredLogs: [ConsoleLogEntry] {
        filteredLogs(for: .console)
    }

    func filteredLogs(for tab: DebuggerLogTab) -> [ConsoleLogEntry] {
        guard tab == .console else {
            return []
        }

        let normalizedTokens = activeSearchTokens(for: .console)

        return logs.filter { entry in
            guard selectedLevels.contains(entry.level) else {
                return false
            }

            guard !normalizedTokens.isEmpty else {
                return true
            }

            let message = entry.message.lowercased()
            let source = entry.source.lowercased()

            return normalizedTokens.contains { token in
                message.contains(token) || source.contains(token)
            }
        }
        .sorted { lhs, rhs in
            switch consoleLogSortOrder {
            case .oldestFirst:
                lhs.timestamp < rhs.timestamp
            case .newestFirst:
                lhs.timestamp > rhs.timestamp
            }
        }
    }

    var filteredNetworkRequests: [NetworkRequestEntry] {
        let normalizedTokens = activeSearchTokens(for: .network)

        return networkRequests.filter { entry in
            guard !normalizedTokens.isEmpty else {
                return true
            }

            let statusCodeText = entry.statusCode.map(String.init) ?? ""
            let haystacks = [
                entry.method.lowercased(),
                entry.url.lowercased(),
                entry.metadataSummary.lowercased(),
                statusCodeText.lowercased(),
                (entry.failureText ?? "").lowercased(),
                (entry.requestBody ?? "").lowercased()
            ]

            return normalizedTokens.contains { token in
                haystacks.contains { $0.contains(token) }
            }
        }
        .sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    var levelFilterTitle: String {
        let orderedLevels = ConsoleLogLevel.allCases.filter { selectedLevels.contains($0) }

        if orderedLevels.count == ConsoleLogLevel.allCases.count {
            return AppStrings.text(.allLevels)
        }

        return orderedLevels.map(\.title).joined(separator: " + ")
    }

    var emptyStateTitle: String {
        emptyStateTitle(for: .console)
    }

    func emptyStateTitle(for tab: DebuggerLogTab) -> String {
        hasActiveFilters(for: tab)
            ? AppStrings.text(.noLogsMatchCurrentFilters)
            : AppStrings.text(tab == .console ? .waitingForConsoleLogs : .waitingForNetworkLogs)
    }

    var emptyStateMessage: String {
        emptyStateMessage(for: .console)
    }

    func emptyStateMessage(for tab: DebuggerLogTab) -> String {
        if hasActiveFilters(for: tab) {
            return AppStrings.text(.adjustSearchOrLevelFilter)
        }

        return AppStrings.text(tab == .console ? .consoleOutputWillAppear : .networkOutputWillAppear)
    }

    var hasLogs: Bool {
        !logs.isEmpty
    }

    var hasNetworkRequests: Bool {
        !networkRequests.isEmpty
    }

    func addSearchTermFromDraft() {
        addSearchTermFromDraft(for: .console)
    }

    func addSearchTermFromDraft(for tab: DebuggerLogTab) {
        let term = draftSearchText(for: tab).trimmed
        guard !term.isEmpty else {
            return
        }

        switch tab {
        case .console:
            if !searchTerms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
                searchTerms.append(term)
            }

            searchText = ""
            persistence.savePinnedSearchTerms(searchTerms, for: .console)
            persistence.saveDraftSearchText(searchText, for: .console)
        case .network:
            if !networkSearchTerms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
                networkSearchTerms.append(term)
            }

            networkSearchText = ""
            persistence.savePinnedSearchTerms(networkSearchTerms, for: .network)
            persistence.saveDraftSearchText(networkSearchText, for: .network)
        case .compareText:
            break
        case .jsonGraph:
            break
        }
    }

    func removeSearchTerm(_ term: String) {
        removeSearchTerm(term, for: .console)
    }

    func removeSearchTerm(_ term: String, for tab: DebuggerLogTab) {
        switch tab {
        case .console:
            searchTerms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
            persistence.savePinnedSearchTerms(searchTerms, for: .console)
        case .network:
            networkSearchTerms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
            persistence.savePinnedSearchTerms(networkSearchTerms, for: .network)
        case .compareText:
            break
        case .jsonGraph:
            break
        }
    }

    func draftSearchText(for tab: DebuggerLogTab) -> String {
        switch tab {
        case .console:
            return searchText
        case .network:
            return networkSearchText
        case .compareText:
            return ""
        case .jsonGraph:
            return ""
        }
    }

    func setDraftSearchText(_ text: String, for tab: DebuggerLogTab) {
        switch tab {
        case .console:
            searchText = text
            persistence.saveDraftSearchText(text, for: .console)
        case .network:
            networkSearchText = text
            persistence.saveDraftSearchText(text, for: .network)
        case .compareText:
            break
        case .jsonGraph:
            break
        }
    }

    func clearSearchText(for tab: DebuggerLogTab) {
        setDraftSearchText("", for: tab)
    }

    func pinnedSearchTerms(for tab: DebuggerLogTab) -> [String] {
        switch tab {
        case .console:
            return searchTerms
        case .network:
            return networkSearchTerms
        case .compareText:
            return []
        case .jsonGraph:
            return []
        }
    }

    private func hasActiveFilters(for tab: DebuggerLogTab) -> Bool {
        if tab == .compareText || tab == .jsonGraph {
            return false
        }

        let hasSearchFilters = !activeSearchTokens(for: tab).isEmpty

        if tab == .console {
            return hasSearchFilters || selectedLevels.count < ConsoleLogLevel.allCases.count
        }

        return hasSearchFilters
    }

    private func activeSearchTokens(for tab: DebuggerLogTab) -> [String] {
        let sourceTerms: [String]
        let draftText: String

        switch tab {
        case .console:
            sourceTerms = searchTerms
            draftText = searchText
        case .network:
            sourceTerms = networkSearchTerms
            draftText = networkSearchText
        case .compareText:
            sourceTerms = []
            draftText = ""
        case .jsonGraph:
            sourceTerms = []
            draftText = ""
        }

        return (sourceTerms + [draftText]).flatMap(Self.tokenizeSearchTokens)
    }

    private static func tokenizeSearchTokens(from input: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))

        return input
            .lowercased()
            .components(separatedBy: separators)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }

    func toggleLevel(_ level: ConsoleLogLevel) {
        if selectedLevels.contains(level) {
            guard selectedLevels.count > 1 else {
                return
            }

            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }

    func resetLevelFilter() {
        selectedLevels = Set(ConsoleLogLevel.allCases)
    }

    func replaceLogs(_ logs: [ConsoleLogEntry]) {
        self.logs = logs
    }

    func toggleConsoleLogSortOrder() {
        consoleLogSortOrder.toggle()
        persistence.saveSortOrder(consoleLogSortOrder)
    }

    func replaceNetworkRequests(_ requests: [NetworkRequestEntry]) {
        networkRequests = requests
    }

    func compareTexts() {
        let diffSegments = Self.buildCompareDiffSegments(
            first: compareFirstText,
            second: compareSecondText
        )

        compareFirstSegments = diffSegments.first
        compareSecondSegments = diffSegments.second
        compareResult = compareFirstText == compareSecondText ? .same : .different
        compareMode = .results
    }

    func resetCompare() {
        compareMode = .editing
        compareResult = .idle
        compareFirstSegments.removeAll()
        compareSecondSegments.removeAll()
    }

    func clearLogs() {
        logs.removeAll()
    }

    func clearNetworkRequests() {
        networkRequests.removeAll()
    }

    private static func buildCompareDiffSegments(
        first: String,
        second: String
    ) -> (first: [CompareTextSegment], second: [CompareTextSegment]) {
        let firstTokens = tokenizeCompareText(first)
        let secondTokens = tokenizeCompareText(second)

        guard !(firstTokens.isEmpty && secondTokens.isEmpty) else {
            return ([], [])
        }

        let rowLength = secondTokens.count + 1
        var lcs = Array(repeating: 0, count: (firstTokens.count + 1) * rowLength)

        func index(_ firstIndex: Int, _ secondIndex: Int) -> Int {
            firstIndex * rowLength + secondIndex
        }

        if !firstTokens.isEmpty, !secondTokens.isEmpty {
            for firstIndex in stride(from: firstTokens.count - 1, through: 0, by: -1) {
                for secondIndex in stride(from: secondTokens.count - 1, through: 0, by: -1) {
                    if firstTokens[firstIndex] == secondTokens[secondIndex] {
                        lcs[index(firstIndex, secondIndex)] = lcs[index(firstIndex + 1, secondIndex + 1)] + 1
                    } else {
                        lcs[index(firstIndex, secondIndex)] = max(
                            lcs[index(firstIndex + 1, secondIndex)],
                            lcs[index(firstIndex, secondIndex + 1)]
                        )
                    }
                }
            }
        }

        var firstSegments: [CompareTextSegment] = []
        var secondSegments: [CompareTextSegment] = []
        var firstIndex = 0
        var secondIndex = 0

        while firstIndex < firstTokens.count && secondIndex < secondTokens.count {
            if firstTokens[firstIndex] == secondTokens[secondIndex] {
                appendCompareSegment(firstTokens[firstIndex], differs: false, into: &firstSegments)
                appendCompareSegment(secondTokens[secondIndex], differs: false, into: &secondSegments)
                firstIndex += 1
                secondIndex += 1
            } else if lcs[index(firstIndex + 1, secondIndex)] >= lcs[index(firstIndex, secondIndex + 1)] {
                appendCompareSegment(firstTokens[firstIndex], differs: true, into: &firstSegments)
                firstIndex += 1
            } else {
                appendCompareSegment(secondTokens[secondIndex], differs: true, into: &secondSegments)
                secondIndex += 1
            }
        }

        while firstIndex < firstTokens.count {
            appendCompareSegment(firstTokens[firstIndex], differs: true, into: &firstSegments)
            firstIndex += 1
        }

        while secondIndex < secondTokens.count {
            appendCompareSegment(secondTokens[secondIndex], differs: true, into: &secondSegments)
            secondIndex += 1
        }

        return (firstSegments, secondSegments)
    }

    private static func appendCompareSegment(
        _ text: String,
        differs: Bool,
        into segments: inout [CompareTextSegment]
    ) {
        guard !text.isEmpty else {
            return
        }

        if let lastIndex = segments.indices.last, segments[lastIndex].isDifferent == differs {
            segments[lastIndex] = CompareTextSegment(
                text: segments[lastIndex].text + text,
                isDifferent: differs
            )
        } else {
            segments.append(CompareTextSegment(text: text, isDifferent: differs))
        }
    }

    private static func tokenizeCompareText(_ input: String) -> [String] {
        guard !input.isEmpty else {
            return []
        }

        let pattern = #"\s+|\w+|[^\w\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [input]
        }

        let fullRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: fullRange)

        guard !matches.isEmpty else {
            return [input]
        }

        return matches.compactMap { match in
            guard let range = Range(match.range, in: input) else {
                return nil
            }

            return String(input[range])
        }
    }

}

struct ConsoleDebuggerView: View {
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    @ObservedObject var session: DevtoolsConsoleSession
    let connectedSessions: [DevtoolsConsoleSession]
    let onShowHome: () -> Void
    let onSelectSession: (DevtoolsConsoleSession) -> Void
    let onDisconnect: () -> Void

    @StateObject private var viewModel: ConsoleDebuggerViewModel
    @State private var isDisconnected = false
    @State private var expandedLogIdentifiers = Set<UUID>()
    @State private var isRailExpanded = false
    @State private var leftSidebarDisplayMode: DebuggerSidebarDisplayMode
    @State private var selectedDestination: DebuggerWorkspaceDestination = .device
    @State private var selectedTab: DebuggerLogTab = .network
    @State private var selectedNetworkRequestID: String?
    @State private var selectedConsoleLogID: UUID?
    @State private var isConsolePinnedToBottom = true
    @State private var pendingConsoleAutoScroll = false
    @State private var copyToastMessage: String?
    @State private var copyToastDismissWorkItem: DispatchWorkItem?
    @State private var expandedInspectorCodeSections = Set<String>()
    @StateObject private var jsonGraphViewModel = JsonGraphWorkspaceViewModel()
    @FocusState private var isSearchFieldFocused: Bool
    private let persistence: ConsoleDebuggerViewModel.Persistence

    init(
        session: DevtoolsConsoleSession,
        connectedSessions: [DevtoolsConsoleSession] = [],
        initialLogs: [ConsoleLogEntry] = [],
        persistence: ConsoleDebuggerViewModel.Persistence? = nil,
        onShowHome: @escaping () -> Void,
        onSelectSession: @escaping (DevtoolsConsoleSession) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        let resolvedPersistence = persistence ?? .shared
        self.session = session
        self.connectedSessions = connectedSessions
        self.persistence = resolvedPersistence
        self.onShowHome = onShowHome
        self.onSelectSession = onSelectSession
        self.onDisconnect = onDisconnect
        _viewModel = StateObject(
            wrappedValue: ConsoleDebuggerViewModel(
                logs: initialLogs,
                networkRequests: session.networkRequests,
                persistence: resolvedPersistence
            )
        )
        _leftSidebarDisplayMode = State(initialValue: resolvedPersistence.loadSidebarDisplayMode())
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }

    private func localized(_ english: String, _ vietnamese: String) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return english
        case .vietnamese:
            return vietnamese
        }
    }

    private var palette: FlipperPalette {
        FlipperPalette(for: .light)
    }

    private var filteredConsoleLogs: [ConsoleLogEntry] {
        viewModel.filteredLogs(for: .console)
    }

    private var filteredNetworkRequests: [NetworkRequestEntry] {
        viewModel.filteredNetworkRequests
    }

    private var draftSearchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.draftSearchText(for: selectedTab) },
            set: { viewModel.setDraftSearchText($0, for: selectedTab) }
        )
    }

    private var currentDraftSearchText: String {
        viewModel.draftSearchText(for: selectedTab)
    }

    private var currentPinnedSearchTerms: [String] {
        viewModel.pinnedSearchTerms(for: selectedTab)
    }

    private var compareResultTitle: String? {
        viewModel.compareResult.title(language: language)
    }

    private var compareButtonTitle: String {
        localized("Compare", "So sánh")
    }

    private var compareRefreshButtonTitle: String {
        localized("Refresh", "Làm mới")
    }

    private var showsSearchToolbar: Bool {
        selectedDestination == .device &&
            selectedTab != .compareText &&
            selectedTab != .jsonGraph
    }

    private var workspaceTitle: String {
        switch selectedDestination {
        case .device:
            switch selectedTab {
            case .console:
                return localized("Logs", "Nhật ký")
            case .network:
                return localized("Network", "Mạng")
            case .compareText:
                return localized("Compare Text", "So sánh văn bản")
            case .jsonGraph:
                return localized("Json Graph", "Đồ thị JSON")
            }
        case .settings:
            return localized("Settings", "Cài đặt")
        }
    }

    private var connectionStatusTitle: String {
        AppStrings.connectStatusTitle(isDisconnected: isDisconnected, language: language)
    }

    private var copyToastTitle: String {
        localized("Copied", "Đã copy")
    }

    private var inspectorExpandTitle: String {
        localized("View more", "Xem thêm")
    }

    private var inspectorCollapseTitle: String {
        localized("Collapse", "Thu gọn")
    }

    private var inspectorExpandLinkURL: URL {
        URL(string: "rnv-inspector://expand")!
    }

    private var mobileRailItems: [WorkspaceRailMobileItem] {
        WorkspaceRailMobileItem.items(from: connectedSessions, language: language)
    }

    private var railSelection: WorkspaceRailSelection {
        selectedDestination == .settings ? .settings : .mobile(session.id)
    }

    private var sdkConnectedAppName: String? {
        session.sdkSession?.appName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private var sdkConnectedDeviceName: String? {
        session.sdkSession?.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private var candidateAppName: String {
        if let sdkConnectedAppName {
            return sdkConnectedAppName
        }

        let raw = session.candidate.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openParen = raw.lastIndex(of: "("), raw.hasSuffix(")") else {
            return raw
        }

        let appName = raw[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
        return appName.isEmpty ? raw : appName
    }

    private var candidateDeviceName: String {
        if let sdkConnectedDeviceName {
            return sdkConnectedDeviceName
        }

        let raw = session.candidate.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let openParen = raw.lastIndex(of: "("),
            let closeParen = raw.lastIndex(of: ")"),
            openParen < closeParen
        else {
            return session.candidate.detailText
        }

        let start = raw.index(after: openParen)
        let deviceName = raw[start..<closeParen].trimmingCharacters(in: .whitespacesAndNewlines)
        return deviceName.isEmpty ? session.candidate.detailText : deviceName
    }

    private var candidatePlatformName: String {
        let haystack = "\(session.candidate.displayName) \(session.candidate.detailText)".lowercased()
        return haystack.contains("android") ? "Android" : "iOS"
    }

    private var candidatePlatformIcon: String {
        "iphone"
    }

    private var candidateTitleLine: String {
        let appName = candidateAppName
        let deviceName = candidateDeviceName

        guard !deviceName.isEmpty, deviceName != session.candidate.detailText else {
            return appName
        }

        return "\(appName) (\(deviceName))"
    }

    private var selectedNetworkRequest: NetworkRequestEntry? {
        guard let selectedNetworkRequestID else {
            return nil
        }

        return filteredNetworkRequests.first { $0.id == selectedNetworkRequestID }
    }

    private var selectedConsoleLog: ConsoleLogEntry? {
        guard let selectedConsoleLogID else {
            return nil
        }

        return filteredConsoleLogs.first { $0.id == selectedConsoleLogID }
    }

    private var showsInspectorPane: Bool {
        switch selectedTab {
        case .console:
            return selectedConsoleLog != nil
        case .network:
            return selectedNetworkRequest != nil
        case .compareText:
            return false
        case .jsonGraph:
            return jsonGraphViewModel.selectedNodeDetail != nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = DebuggerWorkspaceLayout(size: geometry.size)

            HStack(spacing: 0) {
                rail(palette: palette)
                    .frame(width: layout.railWidth(isExpanded: isRailExpanded))

                Rectangle()
                    .fill(palette.divider)
                    .frame(width: 1)

                if selectedDestination == .settings {
                    settingsWorkspace(palette: palette)
                } else {
                    leftSidebar(palette: palette)
                        .frame(width: layout.leftSidebarWidth(mode: leftSidebarDisplayMode))

                    Rectangle()
                        .fill(palette.divider)
                        .frame(width: 1)

                    VStack(spacing: 0) {
                        if selectedTab.showsWorkspaceHeader {
                            workspaceHeader(palette: palette)
                        }
                        if showsSearchToolbar {
                            searchToolbar(palette: palette, layout: layout)
                        }
                        workspaceBody(palette: palette, layout: layout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(palette.backgroundDefault)
                }
            }
        }
        .background(palette.backgroundWash)
        .overlay(alignment: .top) {
            if let copyToastMessage {
                Text(copyToastMessage)
                    .font(FlipperTypography.bodyStrong)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.82))
                    )
                    .padding(.top, 12)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isRailExpanded)
        .animation(.easeInOut(duration: 0.22), value: showsInspectorPane)
        .animation(.easeInOut(duration: 0.22), value: selectedDestination)
        .animation(.easeInOut(duration: 0.18), value: copyToastMessage)
        .task {
            viewModel.replaceLogs(session.logs)
            viewModel.replaceNetworkRequests(session.networkRequests)
            syncSelections()
        }
        .onReceive(session.$logs) { logs in
            let shouldStickToBottom = selectedTab == .console &&
                viewModel.consoleLogSortOrder == .oldestFirst &&
                isConsolePinnedToBottom
            viewModel.replaceLogs(logs)
            if shouldStickToBottom {
                pendingConsoleAutoScroll = true
            }
            syncSelections()
        }
        .onReceive(session.$networkRequests) { requests in
            viewModel.replaceNetworkRequests(requests)
            syncSelections()
        }
        .onChange(of: selectedTab) {
            syncSelections()
        }
        .onChange(of: selectedDestination) { _, newValue in
            if newValue == .settings {
                hideInspectorPane()
            }
        }
        .onDisappear {
            copyToastDismissWorkItem?.cancel()
            copyToastDismissWorkItem = nil
        }
    }

    private func rail(palette: FlipperPalette) -> some View {
        WorkspaceLeftRail(
            palette: palette,
            language: language,
            isExpanded: $isRailExpanded,
            selection: railSelection,
            mobileItems: mobileRailItems,
            onHome: {
                handleHome()
            },
            onSelectMobile: { sessionID in
                guard let targetSession = connectedSessions.first(where: { $0.id == sessionID }) else {
                    return
                }

                onSelectSession(targetSession)
            },
            onSettings: {
                selectedDestination = .settings
            }
        )
    }

    private func leftSidebar(palette: FlipperPalette) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            deviceSidebar(palette: palette)
                .padding(.horizontal, leftSidebarDisplayMode == .expanded ? 14 : 10)
        }
        .background(Color(hex: 0xFAFAFA))
    }

    private func deviceSidebar(palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if leftSidebarDisplayMode == .expanded {
                    Text(localized("APP INSPECT", "KIỂM TRA APP"))
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .tracking(0.5)
                }

                Spacer(minLength: 0)

                Button {
                    let nextMode: DebuggerSidebarDisplayMode = leftSidebarDisplayMode == .expanded ? .iconOnly : .expanded
                    leftSidebarDisplayMode = nextMode
                    persistence.saveSidebarDisplayMode(nextMode)
                } label: {
                    Image(systemName: leftSidebarDisplayMode.toggleIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(leftSidebarDisplayMode == .expanded ? localized("Collapse", "Thu nhỏ") : localized("Expand", "Mở rộng"))
            }
            .padding(.top, 12)

            appTargetCard(palette: palette)

            pluginSection(
                items: [
                    PluginSidebarEntry(
                        title: localized("Logs", "Nhật ký"),
                        subtitle: localized("\(filteredConsoleLogs.count) entries", "\(filteredConsoleLogs.count) mục"),
                        icon: "terminal",
                        tab: .console,
                        isSelected: selectedTab == .console
                    ),
                    PluginSidebarEntry(
                        title: localized("Network", "Mạng"),
                        subtitle: localized("\(filteredNetworkRequests.count) requests", "\(filteredNetworkRequests.count) yêu cầu"),
                        icon: "network",
                        tab: .network,
                        isSelected: selectedTab == .network
                    ),
                    PluginSidebarEntry(
                        title: localized("Compare Text", "So sánh văn bản"),
                        subtitle: localized("Compare two texts", "So sánh hai văn bản"),
                        icon: "doc.text.magnifyingglass",
                        tab: .compareText,
                        isSelected: selectedTab == .compareText
                    ),
                    PluginSidebarEntry(
                        title: localized("Json Graph", "Đồ thị JSON"),
                        subtitle: localized("Visualize JSON data", "Trực quan dữ liệu JSON"),
                        icon: "point.3.connected.trianglepath.dotted",
                        tab: .jsonGraph,
                        isSelected: selectedTab == .jsonGraph
                    )
                ],
                palette: palette
            )

            Spacer(minLength: 8)
        }
    }

    private func appTargetCard(palette: FlipperPalette) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0xF3E8FF))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: candidatePlatformIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }

                if leftSidebarDisplayMode == .expanded {
                    Text(candidatePlatformName)
                        .font(FlipperTypography.micro)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: leftSidebarDisplayMode == .expanded ? 52 : 42)

            if leftSidebarDisplayMode == .expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidateAppName)
                        .font(FlipperTypography.bodyStrong)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)

                    Text(candidateDeviceName)
                        .font(FlipperTypography.body)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: leftSidebarDisplayMode == .expanded ? .leading : .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private func pluginSection(items: [PluginSidebarEntry], palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    selectedTab = item.tab
                } label: {
                    HStack(spacing: leftSidebarDisplayMode == .expanded ? 10 : 0) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.isSelected ? palette.accent : palette.secondaryText)
                            .frame(width: 16)

                        if leftSidebarDisplayMode == .expanded {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(FlipperTypography.body)
                                    .foregroundStyle(palette.primaryText)

                                Text(item.subtitle)
                                    .font(FlipperTypography.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }

                            Spacer()
                        }
                    }
                    .padding(.horizontal, leftSidebarDisplayMode == .expanded ? 10 : 0)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: leftSidebarDisplayMode == .expanded ? .leading : .center)
                    .background(
                        Rectangle()
                            .fill(item.isSelected ? Color(hex: 0xF3E8FF) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.title)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(palette.divider)
                        .frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private func settingsWorkspace(palette: FlipperPalette) -> some View {
        AppSettingsView(embeddedInWorkspace: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.backgroundDefault)
    }

    private func workspaceHeader(palette: FlipperPalette) -> some View {
        let disconnectBackground = Color(hex: 0xFFF1F0)
        let disconnectBorder = Color(hex: 0xFFCCC7)
        let disconnectForeground = Color(hex: 0xCF1322)
        let disconnectPressedBackground = Color(hex: 0xFFE2E0)

        return HStack(spacing: 12) {
            Text(workspaceTitle)
                .font(FlipperTypography.title3)
                .foregroundStyle(palette.primaryText)

            Spacer()

            HStack(spacing: 8) {
                headerMetricPill(
                    icon: isDisconnected ? "bolt.slash" : "bolt.horizontal.circle",
                    title: connectionStatusTitle,
                    tint: isDisconnected ? palette.secondaryText : palette.success,
                    palette: palette
                )

                headerMetricPill(
                    icon: "terminal",
                    title: localized("\(filteredConsoleLogs.count) logs", "\(filteredConsoleLogs.count) log"),
                    tint: palette.primaryText,
                    palette: palette
                )

                headerMetricPill(
                    icon: "network",
                    title: localized("\(filteredNetworkRequests.count) requests", "\(filteredNetworkRequests.count) yêu cầu"),
                    tint: palette.primaryText,
                    palette: palette
                )
            }

            Button(AppStrings.disconnectButtonTitle(isDisconnected: isDisconnected, language: language)) {
                handleDisconnect()
            }
            .buttonStyle(
                FlipperDangerGhostButtonStyle(
                    background: disconnectBackground,
                    border: disconnectBorder,
                    foreground: disconnectForeground,
                    pressedBackground: disconnectPressedBackground
                )
            )
            .disabled(isDisconnected)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
        }
    }

    private func headerMetricPill(icon: String, title: String, tint: Color, palette: FlipperPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(FlipperTypography.caption)
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: 0xF7F7F7))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .fixedSize()
    }

    private func searchToolbar(palette: FlipperPalette, layout: DebuggerWorkspaceLayout) -> some View {
        let addBackground = Color(hex: 0xE6F4FF)
        let addBorder = Color(hex: 0xB8D9F5)
        let addForeground = Color(hex: 0x0958D9)
        let addPressedBackground = Color(hex: 0xD6EBFF)
        let clearBackground = Color(hex: 0xFFF1F0)
        let clearBorder = Color(hex: 0xFFCCC7)
        let clearForeground = Color(hex: 0xCF1322)
        let clearPressedBackground = Color(hex: 0xFFE2E0)

        return HStack(spacing: 10) {
            searchField(palette: palette)
                .frame(maxWidth: layout.searchFieldMaxWidth)

            Button {
                viewModel.addSearchTermFromDraft(for: selectedTab)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))

                    Text(AppStrings.text(.add, language: language))
                        .lineLimit(1)
                }
            }
            .buttonStyle(
                ToolbarTintedButtonStyle(
                    background: addBackground,
                    border: addBorder,
                    foreground: addForeground,
                    pressedBackground: addPressedBackground
                )
            )
            .disabled(currentDraftSearchText.trimmed.isEmpty)

            Button {
                handleClear()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .bold))

                    Text(AppStrings.text(.clear, language: language))
                        .lineLimit(1)
                }
            }
            .buttonStyle(
                ToolbarTintedButtonStyle(
                    background: clearBackground,
                    border: clearBorder,
                    foreground: clearForeground,
                    pressedBackground: clearPressedBackground
                )
            )
            .disabled(selectedTab == .console ? !viewModel.hasLogs : !viewModel.hasNetworkRequests)

            if !currentPinnedSearchTerms.isEmpty {
                searchTermsRow(palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0xFAFAFA))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
        }
    }

    private func searchField(palette: FlipperPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondaryText)

            TextField(
                "",
                text: draftSearchTextBinding,
                prompt: Text(
                    AppStrings.text(
                        selectedTab == .console ? .searchConsoleMessages : .searchNetworkLogs,
                        language: language
                    )
                )
                .foregroundStyle(palette.secondaryText)
            )
            .textFieldStyle(.plain)
            .font(FlipperTypography.body)
            .foregroundStyle(palette.primaryText)
            .focused($isSearchFieldFocused)

            if isSearchFieldFocused || !currentDraftSearchText.isEmpty {
                Button(action: clearSearchField) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("Clear search", "Xóa tìm kiếm"))
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private func searchTermsRow(palette: FlipperPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(currentPinnedSearchTerms, id: \.self) { term in
                    ConsoleSearchChip(term: term, palette: palette) {
                        viewModel.removeSearchTerm(term, for: selectedTab)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func workspaceBody(palette: FlipperPalette, layout: DebuggerWorkspaceLayout) -> some View {
        HStack(spacing: 0) {
            centerPane(palette: palette)

            if showsInspectorPane {
                Rectangle()
                    .fill(palette.divider)
                    .frame(width: 1)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                inspectorPane(palette: palette)
                    .frame(width: layout.inspectorWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centerPane(palette: FlipperPalette) -> some View {
        Group {
            if selectedTab == .compareText {
                compareTextWorkspace(palette: palette)
            } else if selectedTab == .jsonGraph {
                jsonGraphWorkspace(palette: palette)
            } else if selectedTab == .network {
                networkTable(palette: palette)
            } else {
                consoleTable(palette: palette)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private func compareTextWorkspace(palette: FlipperPalette) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 24) {
                compareTextColumn(
                    title: localized("Text 1", "Văn bản 1"),
                    text: $viewModel.compareFirstText,
                    segments: viewModel.compareFirstSegments,
                    highlightColor: nsColor(hex: 0xFFF1F0),
                    palette: palette
                )

                compareTextActions(palette: palette)
                    .frame(width: 120)
                    .padding(.top, 128)

                compareTextColumn(
                    title: localized("Text 2", "Văn bản 2"),
                    text: $viewModel.compareSecondText,
                    segments: viewModel.compareSecondSegments,
                    highlightColor: nsColor(hex: 0xF6FFED),
                    palette: palette
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func jsonGraphWorkspace(palette: FlipperPalette) -> some View {
        JsonGraphWorkspaceView(
            viewModel: jsonGraphViewModel,
            palette: palette,
            language: language
        )
    }

    private func compareTextColumn(
        title: String,
        text: Binding<String>,
        segments: [CompareTextSegment],
        highlightColor: NSColor,
        palette: FlipperPalette
    ) -> some View {
        Group {
            if viewModel.compareMode == .editing {
                compareTextInputCard(title: title, text: text, palette: palette)
            } else {
                compareTextDiffCard(
                    title: title,
                    segments: segments,
                    highlightColor: highlightColor,
                    palette: palette
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compareTextActions(palette: FlipperPalette) -> some View {
        VStack(spacing: 12) {
            Button(compareButtonTitle) {
                viewModel.compareTexts()
            }
            .buttonStyle(FlipperPrimaryButtonStyle(palette: palette))
            .frame(maxWidth: .infinity)

            Button(compareRefreshButtonTitle) {
                viewModel.resetCompare()
            }
            .buttonStyle(FlipperSecondaryButtonStyle(palette: palette))
            .frame(maxWidth: .infinity)
            .disabled(viewModel.compareMode == .editing)

            if let compareResultTitle {
                Text(compareResultTitle)
                    .font(FlipperTypography.bodyStrong)
                    .foregroundStyle(palette.primaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func compareTextInputCard(
        title: String,
        text: Binding<String>,
        palette: FlipperPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FlipperTypography.title4)
                .foregroundStyle(palette.primaryText)

            TextEditor(text: text)
                .font(FlipperTypography.body)
                .foregroundStyle(palette.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 360)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compareTextDiffCard(
        title: String,
        segments: [CompareTextSegment],
        highlightColor: NSColor,
        palette: FlipperPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FlipperTypography.title4)
                .foregroundStyle(palette.primaryText)

            CompareHighlightedTextView(
                segments: segments,
                highlightColor: highlightColor
            )
            .frame(minHeight: 360)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func networkTable(palette: FlipperPalette) -> some View {
        VStack(spacing: 0) {
            networkTableHeader(palette: palette)

            if filteredNetworkRequests.isEmpty {
                emptyState(
                    title: viewModel.emptyStateTitle(for: .network),
                    message: viewModel.emptyStateMessage(for: .network),
                    palette: palette
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredNetworkRequests) { entry in
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    selectedNetworkRequestID = entry.id
                                }
                            } label: {
                                networkRow(entry: entry, isSelected: selectedNetworkRequestID == entry.id, palette: palette)
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(palette.divider)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func networkTableHeader(palette: FlipperPalette) -> some View {
        HStack(spacing: 0) {
            tableColumnHeader(localized("Request Time", "Thời gian request"), width: 92, alignment: .leading, palette: palette)
            tableColumnHeader(localized("Domain", "Tên miền"), width: nil, alignment: .leading, palette: palette)
            tableColumnHeader(localized("Method", "Phương thức"), width: 64, alignment: .leading, palette: palette)
            tableColumnHeader(localized("Status", "Trạng thái"), width: 60, alignment: .leading, palette: palette)
            tableColumnHeader(localized("Request Size", "Kích thước request"), width: 86, alignment: .leading, palette: palette)
            tableColumnHeader(localized("Response Size", "Kích thước response"), width: 92, alignment: .leading, palette: palette)
            tableColumnHeader(localized("Time", "Thời gian"), width: 64, alignment: .leading, palette: palette)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(hex: 0xFAFAFA))
    }

    private func networkRow(entry: NetworkRequestEntry, isSelected: Bool, palette: FlipperPalette) -> some View {
        HStack(spacing: 0) {
            tableCell(entry.flipperTimestampText, width: 92, alignment: .leading, palette: palette)
            tableCell(entry.flipperDomainText, width: nil, alignment: .leading, palette: palette)
            tableCell(entry.method.uppercased(), width: 64, alignment: .leading, palette: palette)
            tableCell(entry.flipperStatusText(language: language), width: 60, alignment: .leading, palette: palette)
            tableCell(entry.flipperRequestSizeText, width: 86, alignment: .leading, palette: palette)
            tableCell(entry.flipperResponseSizeText, width: 92, alignment: .leading, palette: palette)
            tableCell(entry.flipperDurationText, width: 64, alignment: .leading, palette: palette)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color(hex: 0xF3E8FF) : Color.white)
    }

    private func consoleTable(palette: FlipperPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                consoleTimeHeader(palette: palette)
                tableColumnHeader(localized("Level", "Mức"), width: 72, alignment: .leading, palette: palette)
                tableColumnHeader(localized("Message", "Nội dung"), width: nil, alignment: .leading, palette: palette)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(hex: 0xFAFAFA))

            if filteredConsoleLogs.isEmpty {
                emptyState(
                    title: viewModel.emptyStateTitle(for: .console),
                    message: viewModel.emptyStateMessage(for: .console),
                    palette: palette
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredConsoleLogs) { entry in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        selectedConsoleLogID = entry.id
                                    }
                                } label: {
                                    HStack(spacing: 0) {
                                        tableCell(entry.flipperTimestampText, width: 92, alignment: .leading, palette: palette)
                                        tableCell(entry.level.title, width: 72, alignment: .leading, palette: palette, tint: entry.level.badgeColor)
                                        tableCell(entry.displayMessage(isExpanded: expandedLogIdentifiers.contains(entry.id)), width: nil, alignment: .leading, palette: palette)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedConsoleLogID == entry.id ? Color(hex: 0xF3E8FF) : Color.white)
                                }
                                .buttonStyle(.plain)

                                Rectangle()
                                    .fill(palette.divider)
                                    .frame(height: 1)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(ConsoleScrollMetrics.bottomAnchorID)
                        }
                        .background(
                            ConsoleScrollPositionObserver { contentHeight, visibleHeight, visibleMaxY, changeSource in
                                updateConsolePinnedToBottom(
                                    contentHeight: contentHeight,
                                    visibleHeight: visibleHeight,
                                    visibleMaxY: visibleMaxY,
                                    changeSource: changeSource
                                )
                            }
                            .frame(width: 0, height: 0)
                        )
                    }
                    .onChange(of: filteredConsoleLogs.map(\.id)) { _, _ in
                        guard pendingConsoleAutoScroll, viewModel.consoleLogSortOrder == .oldestFirst else {
                            return
                        }

                        pendingConsoleAutoScroll = false
                        isConsolePinnedToBottom = true
                        scrollConsoleToBottom(using: proxy)
                    }
                    .onChange(of: viewModel.consoleLogSortOrder) { _, newValue in
                        guard newValue == .oldestFirst else {
                            return
                        }

                        pendingConsoleAutoScroll = false
                        isConsolePinnedToBottom = true
                        scrollConsoleToBottom(using: proxy)
                    }
                    .onAppear {
                        if viewModel.consoleLogSortOrder == .oldestFirst {
                            isConsolePinnedToBottom = true
                            scrollConsoleToBottom(using: proxy)
                        }
                    }
                }
            }
        }
    }

    private func consoleTimeHeader(palette: FlipperPalette) -> some View {
        Button {
            viewModel.toggleConsoleLogSortOrder()
        } label: {
            HStack(spacing: 4) {
                Text(localized("Time", "Thời gian"))
                    .font(FlipperTypography.micro)
                    .foregroundStyle(palette.secondaryText)

                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        viewModel.consoleLogSortOrder == .newestFirst
                            ? palette.accent
                            : palette.secondaryText
                    )
            }
            .frame(width: 92, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(viewModel.consoleLogSortOrder == .oldestFirst ? localized("Oldest first", "Cũ nhất trước") : localized("Newest first", "Mới nhất trước"))
    }

    private func inspectorPane(palette: FlipperPalette) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(inspectorPaneTitle)
                        .font(FlipperTypography.title4)
                        .foregroundStyle(palette.primaryText)

                    if let copyValue = inspectorHeaderCopyValue {
                        inspectorCopyButton(value: copyValue, palette: palette)
                    }

                    Spacer()

                    Button {
                        hideInspectorPane()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(hex: 0xF3E8FF))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)

                if selectedTab == .network {
                    if let selectedNetworkRequest {
                        networkInspector(entry: selectedNetworkRequest, palette: palette)
                    } else {
                        emptyInspector(palette: palette)
                    }
                } else if selectedTab == .jsonGraph {
                    if let detail = jsonGraphViewModel.selectedNodeDetail {
                        jsonGraphInspector(detail: detail, palette: palette)
                    } else {
                        emptyInspector(palette: palette)
                    }
                } else {
                    if let selectedConsoleLog {
                        consoleInspector(entry: selectedConsoleLog, palette: palette)
                    } else {
                        emptyInspector(palette: palette)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Color(hex: 0xFCFCFC))
    }

    private var inspectorPaneTitle: String {
        switch selectedTab {
        case .network:
            return localized("Request", "Yêu cầu")
        case .console:
            return localized("Log Detail", "Chi tiết log")
        case .compareText:
            return ""
        case .jsonGraph:
            return localized("Detail", "Chi tiết")
        }
    }

    private var inspectorHeaderCopyValue: String? {
        guard selectedTab == .network, let selectedNetworkRequest else {
            return nil
        }

        return selectedNetworkRequest.url
    }

    private func networkInspector(entry: NetworkRequestEntry, palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorKeyValueSection(
                title: nil,
                rows: [
                    (localized("Full URL", "URL đầy đủ"), entry.url),
                    (localized("Host", "Host"), entry.flipperHostText),
                    (localized("Path", "Đường dẫn"), entry.flipperPathText),
                    (localized("Query String", "Chuỗi truy vấn"), entry.flipperQueryText),
                    (localized("Method", "Phương thức"), entry.method.uppercased()),
                    (localized("Status", "Trạng thái"), entry.flipperStatusText(language: language)),
                    (localized("Time", "Thời gian"), entry.flipperDurationText)
                ],
                palette: palette
            )

            if !entry.requestHeaders.isEmpty {
                inspectorDictionarySection(title: localized("Request Headers", "Header yêu cầu"), values: entry.requestHeaders, palette: palette)
            }

            if let requestBody = entry.requestBody, !requestBody.isEmpty {
                inspectorCodeSection(
                    title: localized("Request Body", "Body yêu cầu"),
                    body: requestBody,
                    copyValue: requestBody,
                    sectionID: "request-body-\(entry.id)",
                    palette: palette
                )
            }

            if !entry.responseHeaders.isEmpty {
                inspectorDictionarySection(title: localized("Response Headers", "Header phản hồi"), values: entry.responseHeaders, palette: palette)
            }

            if let responseBody = entry.responseBody, !responseBody.isEmpty {
                inspectorCodeSection(
                    title: localized("Response Body", "Body phản hồi"),
                    body: responseBody,
                    copyValue: responseBody,
                    sectionID: "response-body-\(entry.id)",
                    palette: palette
                )
            }
        }
    }

    private func consoleInspector(entry: ConsoleLogEntry, palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorKeyValueSection(
                title: nil,
                rows: [
                    (localized("Time", "Thời gian"), entry.flipperTimestampText),
                    (localized("Level", "Mức"), entry.level.title),
                    (localized("Source", "Nguồn"), entry.source)
                ],
                palette: palette
            )

            inspectorCodeSection(
                title: localized("Message", "Nội dung"),
                body: entry.message,
                copyValue: entry.message,
                sectionID: "console-message-\(entry.id.uuidString)",
                palette: palette
            )
        }
    }

    private func jsonGraphInspector(detail: JsonGraphSelectionDetail, palette: FlipperPalette) -> some View {
        JsonGraphSelectionDetailContent(
            detail: detail,
            palette: palette,
            language: language,
            onSelectNode: { nodeID in
                jsonGraphViewModel.selectNode(nodeID: nodeID)
            }
        )
    }

    private func inspectorKeyValueSection(title: String?, rows: [(String, String)], palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(FlipperTypography.title4)
                    .foregroundStyle(palette.primaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.0)
                            .font(FlipperTypography.captionStrong)
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 92, alignment: .leading)

                        Text(row.1.isEmpty ? " " : row.1)
                            .font(FlipperTypography.caption)
                            .foregroundStyle(palette.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(palette.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private func inspectorDictionarySection(title: String, values: [String: String], palette: FlipperPalette) -> some View {
        inspectorKeyValueSection(
            title: title,
            rows: values
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { ($0.key, $0.value) },
            palette: palette
        )
    }

    private func inspectorCodeSection(
        title: String,
        body: String,
        copyValue: String? = nil,
        sectionID: String,
        palette: FlipperPalette
    ) -> some View {
        let previewLimit = 1_200
        let canExpand = body.count > previewLimit
        let isExpanded = expandedInspectorCodeSections.contains(sectionID)
        let displayedBody: String
        if canExpand, !isExpanded {
            displayedBody = "\(body.prefix(previewLimit))..."
        } else {
            displayedBody = body
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(FlipperTypography.title4)
                    .foregroundStyle(palette.primaryText)

                if let copyValue {
                    inspectorCopyButton(value: copyValue, palette: palette)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                if canExpand, !isExpanded {
                    Text(inspectorCollapsedPreviewText(displayedBody))
                        .font(FlipperTypography.code)
                        .foregroundStyle(palette.primaryText)
                        .tint(palette.accent)
                        .environment(\.openURL, OpenURLAction { _ in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                _ = expandedInspectorCodeSections.insert(sectionID)
                            }
                            return .handled
                        })
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(displayedBody)
                        .font(FlipperTypography.code)
                        .foregroundStyle(palette.primaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if canExpand {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                _ = expandedInspectorCodeSections.remove(sectionID)
                            }
                        } label: {
                            Text(inspectorCollapseTitle)
                                .font(FlipperTypography.code)
                                .underline()
                                .foregroundStyle(palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color(nsColor: .white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
    }

    private func inspectorCollapsedPreviewText(_ displayedBody: String) -> AttributedString {
        var preview = AttributedString(displayedBody + " ")
        var expand = AttributedString(inspectorExpandTitle)
        expand.link = inspectorExpandLinkURL
        expand.underlineStyle = .single
        preview.append(expand)
        return preview
    }

    private func inspectorCopyButton(value: String, palette: FlipperPalette) -> some View {
        Button {
            copyInspectorValue(value)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: 0xF3E8FF))
                )
        }
        .buttonStyle(.plain)
        .help(localized("Copy", "Sao chép"))
    }

    private func tableColumnHeader(_ title: String, width: CGFloat?, alignment: Alignment, palette: FlipperPalette) -> some View {
        Text(title)
            .font(FlipperTypography.micro)
            .foregroundStyle(palette.secondaryText)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: alignment)
    }

    private func tableCell(_ value: String, width: CGFloat?, alignment: Alignment, palette: FlipperPalette, tint: Color? = nil) -> some View {
        Text(value)
            .font(FlipperTypography.caption)
            .foregroundStyle(tint ?? palette.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: alignment)
    }

    private func emptyState(title: String, message: String, palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FlipperTypography.title4)
                .foregroundStyle(palette.primaryText)

            Text(message)
                .font(FlipperTypography.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }

    private func emptyInspector(palette: FlipperPalette) -> some View {
        Text(localized("Select an item to inspect.", "Chọn một mục để xem chi tiết."))
            .font(FlipperTypography.body)
            .foregroundStyle(palette.secondaryText)
            .padding(.top, 8)
    }

    private func syncSelections() {
        if let selectedNetworkRequestID,
           filteredNetworkRequests.contains(where: { $0.id == selectedNetworkRequestID }) == false {
            withAnimation(.easeInOut(duration: 0.22)) {
                self.selectedNetworkRequestID = nil
            }
        }

        if let selectedConsoleLogID,
           filteredConsoleLogs.contains(where: { $0.id == selectedConsoleLogID }) == false {
            withAnimation(.easeInOut(duration: 0.22)) {
                self.selectedConsoleLogID = nil
            }
        }
    }

    private func handleHome() {
        onShowHome()
    }

    private func handleDisconnect() {
        guard !isDisconnected else {
            return
        }

        isDisconnected = true
        onDisconnect()
    }

    private func handleClear() {
        switch selectedTab {
        case .console:
            expandedLogIdentifiers.removeAll()
            selectedConsoleLogID = nil
            viewModel.clearLogs()
            session.clearLogs()
        case .network:
            selectedNetworkRequestID = nil
            viewModel.clearNetworkRequests()
            session.clearNetworkRequests()
        case .compareText:
            viewModel.compareFirstText = ""
            viewModel.compareSecondText = ""
        case .jsonGraph:
            jsonGraphViewModel.reset()
        }
        expandedInspectorCodeSections.removeAll()
    }

    private func clearSearchField() {
        viewModel.clearSearchText(for: selectedTab)
        isSearchFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func copyInspectorValue(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(value, forType: .string) {
            showCopyToast()
        }
    }

    private func showCopyToast() {
        copyToastDismissWorkItem?.cancel()

        withAnimation(.easeInOut(duration: 0.18)) {
            copyToastMessage = copyToastTitle
        }

        let dismissWorkItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                copyToastMessage = nil
            }
            copyToastDismissWorkItem = nil
        }

        copyToastDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: dismissWorkItem)
    }

    private func updateConsolePinnedToBottom(
        contentHeight: CGFloat,
        visibleHeight: CGFloat,
        visibleMaxY: CGFloat,
        changeSource: ConsoleScrollMetrics.ChangeSource
    ) {
        isConsolePinnedToBottom =
            ConsoleScrollMetrics.pinnedState(
                currentlyPinned: isConsolePinnedToBottom,
                contentHeight: contentHeight,
                visibleHeight: visibleHeight,
                visibleMaxY: visibleMaxY,
                changeSource: changeSource
            )
    }

    private func scrollConsoleToBottom(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(ConsoleScrollMetrics.bottomAnchorID, anchor: .bottom)
        }
    }

    private func hideInspectorPane() {
        withAnimation(.easeInOut(duration: 0.22)) {
            switch selectedTab {
            case .console:
                selectedConsoleLogID = nil
            case .network:
                selectedNetworkRequestID = nil
            case .compareText:
                break
            case .jsonGraph:
                jsonGraphViewModel.clearSelection()
            }
        }
        expandedInspectorCodeSections.removeAll()
    }

    private func nsColor(hex: UInt32, opacity: CGFloat = 1) -> NSColor {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255
        let blue = CGFloat(hex & 0x0000FF) / 255
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: opacity)
    }
}

private struct CompareHighlightedTextView: NSViewRepresentable {
    let segments: [CompareTextSegment]
    let highlightColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(makeAttributedString())
    }

    private func makeAttributedString() -> NSAttributedString {
        let fullText = NSMutableAttributedString()
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]

        for segment in segments {
            var attributes = baseAttributes
            if segment.isDifferent {
                attributes[.backgroundColor] = highlightColor
            }

            fullText.append(NSAttributedString(string: segment.text, attributes: attributes))
        }

        return fullText
    }
}

private struct PluginSidebarEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tab: DebuggerLogTab
    let isSelected: Bool
}

private struct DebuggerWorkspaceLayout {
    let size: CGSize

    private var isMinimumFootprint: Bool {
        size.width <= 1320 || size.height <= 760
    }

    func railWidth(isExpanded: Bool) -> CGFloat {
        isExpanded ? (isMinimumFootprint ? 144 : 156) : 52
    }

    func leftSidebarWidth(mode: DebuggerSidebarDisplayMode) -> CGFloat {
        switch mode {
        case .expanded:
            return isMinimumFootprint ? 212 : 228
        case .iconOnly:
            return 84
        }
    }

    var inspectorWidth: CGFloat {
        isMinimumFootprint ? 332 : 372
    }

    var searchFieldMaxWidth: CGFloat {
        isMinimumFootprint ? 420 : 540
    }
}

private extension NetworkRequestEntry {
    var flipperTimestampText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var flipperURLComponents: URLComponents? {
        URLComponents(string: url)
    }

    var flipperHostText: String {
        flipperURLComponents?.host ?? ""
    }

    var flipperPathText: String {
        let path = flipperURLComponents?.path ?? ""
        return path.isEmpty ? "/" : path
    }

    var flipperQueryText: String {
        flipperURLComponents?.percentEncodedQuery ?? ""
    }

    var flipperDomainText: String {
        if let host = flipperURLComponents?.host {
            let path = flipperPathText
            return path == "/" ? host : "\(host)\(path)"
        }

        return url
    }

    func flipperStatusText(language: AppLanguage) -> String {
        if let statusCode {
            return "\(statusCode)"
        }

        switch state {
        case .pending:
            return "..."
        case .succeeded:
            switch language.resolvedLanguage() {
            case .english:
                return "Done"
            case .vietnamese:
                return "Xong"
            }
        case .failed:
            switch language.resolvedLanguage() {
            case .english:
                return "Err"
            case .vietnamese:
                return "Lỗi"
            }
        }
    }

    var flipperRequestSizeText: String {
        if let requestBody {
            return ByteCountFormatter.string(fromByteCount: Int64(requestBody.utf8.count), countStyle: .file)
        }

        return "0 B"
    }

    var flipperResponseSizeText: String {
        if let encodedDataLength {
            return ByteCountFormatter.string(fromByteCount: encodedDataLength, countStyle: .file)
        }

        if let responseBody {
            return ByteCountFormatter.string(fromByteCount: Int64(responseBody.utf8.count), countStyle: .file)
        }

        return "0 B"
    }

    var flipperDurationText: String {
        if let durationMs {
            return "\(durationMs)ms"
        }

        if let finishedAt {
            let computed = Int((finishedAt.timeIntervalSince(timestamp) * 1000).rounded())
            return "\(max(computed, 0))ms"
        }

        return "-"
    }
}

private extension ConsoleLogEntry {
    var flipperTimestampText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

private struct ConsoleSearchChip: View {
    let term: String
    let palette: FlipperPalette
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(term)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText)
        }
        .font(FlipperTypography.caption)
        .foregroundStyle(palette.primaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct ToolbarTintedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let background: Color
    let border: Color
    let foreground: Color
    let pressedBackground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlipperTypography.captionStrong)
            .foregroundStyle(isEnabled ? foreground : foreground.opacity(0.45))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isEnabled
                            ? (configuration.isPressed ? pressedBackground : background)
                            : background.opacity(0.55)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isEnabled ? border : border.opacity(0.55), lineWidth: 1)
            )
    }
}

#Preview {
    let previewSession = DevtoolsConsoleSession(
        candidate: DevtoolsConnectionCandidate(
            displayName: "com.viettel.VOfficeLDAIPhone (iPhone 12 Pro Max)",
            detailText: "React Native Bridgeless [C++ connection]",
            webSocketURL: URL(string: "ws://localhost:8081/inspector/debug?device=device-42&page=9")!
        )
    )

    return ConsoleDebuggerView(
        session: previewSession,
        connectedSessions: [previewSession],
        initialLogs: [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .info,
                message: "[48;2;253;247;231mNOTE: You are using an unsupported debugging client. Use the Dev Menu in your app to open React Native DevTools.",
                source: "Console"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_121),
                level: .warn,
                message: "Require cycle: app/Utils.js -> src/languages/i18n.js -> redux/store/index.js -> redux/reducers/index.js -> redux/reduxToolKit/index.js -> redux/reduxToolKit/VanBanReducer.js -> app/Utils.js. Require cycles are allowed, but can result in uninitialized values. Consider refactoring to remove the need for a cycle.",
                source: "http://localhost:8081/index.bundle?platform=ios&dev=true"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_141),
                level: .error,
                message: "Unhandled promise rejection: Request timed out while fetching /api/documents after retry policy exhausted. Check network reachability and token refresh flow before reloading the screen.",
                source: "src/api/client.ts"
            )
        ],
        onShowHome: {},
        onSelectSession: { _ in },
        onDisconnect: {}
    )
}
