import Foundation

enum ResolvedAppLanguage: Equatable {
    case english
    case vietnamese

    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en")
        case .vietnamese:
            return Locale(identifier: "vi_VN")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case vietnamese

    static let storageKey = "app.language"

    var id: String {
        rawValue
    }

    static func current(userDefaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: userDefaults.string(forKey: storageKey) ?? AppLanguage.system.rawValue) ?? .system
    }

    func resolvedLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages,
        locale: Locale = .autoupdatingCurrent
    ) -> ResolvedAppLanguage {
        switch self {
        case .english:
            return .english
        case .vietnamese:
            return .vietnamese
        case .system:
            if let preferredLanguage = preferredLanguages.first?.lowercased(), preferredLanguage.hasPrefix("vi") {
                return .vietnamese
            }

            if locale.identifier.lowercased().hasPrefix("vi") {
                return .vietnamese
            }

            return .english
        }
    }

    var resolvedLocale: Locale {
        resolvedLanguage().locale
    }

    var quickSelection: AppLanguageQuickOption {
        switch resolvedLanguage() {
        case .english:
            return .english
        case .vietnamese:
            return .vietnamese
        }
    }
}

enum AppLanguageQuickOption: String, CaseIterable, Identifiable {
    case english
    case vietnamese

    var id: String {
        rawValue
    }

    var appLanguage: AppLanguage {
        switch self {
        case .english:
            return .english
        case .vietnamese:
            return .vietnamese
        }
    }

    var shortTitle: String {
        switch self {
        case .english:
            return "EN"
        case .vietnamese:
            return "VN"
        }
    }
}

enum AppTextKey {
    case connections
    case connectionsSubtitle
    case connectManually
    case connectManuallySubtitle
    case manualConnectPlaceholder
    case connect
    case availableConnections
    case availableConnectionsSubtitle
    case noConnectionsFoundYet
    case detectAgain
    case unknownTarget
    case invalidInput
    case noTargetsFound
    case timedOut
    case unableToEncodeWebSocketCommand
    case consoleMessage
    case consoleSource
    case consoleEntry
    case javaScriptException
    case exceptionSource
    case loading
    case detectLinks
    case allLevels
    case noLogsMatchCurrentFilters
    case waitingForConsoleLogs
    case adjustSearchOrLevelFilter
    case consoleOutputWillAppear
    case back
    case consoleTitle
    case connected
    case disconnected
    case disconnect
    case consoleLogTabTitle
    case networkLogTabTitle
    case searchConsoleMessages
    case searchNetworkLogs
    case add
    case pinSearchTerm
    case showAllLevels
    case clear
    case collapse
    case expand
    case removeSearchTerm
    case waitingForNetworkLogs
    case networkOutputWillAppear
    case networkDomainUnsupportedTitle
    case languageSettingsTitle
    case languageSettingsDescription
    case displayLanguage
    case systemDefault
    case english
    case vietnamese
}

enum AppStrings {
    static func text(_ key: AppTextKey, language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return englishText(for: key)
        case .vietnamese:
            return vietnameseText(for: key)
        }
    }

    static func foundConnectableLinks(_ count: Int, language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "Found \(count) connectable link(s)."
        case .vietnamese:
            return "Đã tìm thấy \(count) liên kết có thể kết nối."
        }
    }

    static func noLinkDetectedAfterOneMinute(language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "No link was detected after 1 minute."
        case .vietnamese:
            return "Không tìm thấy liên kết nào sau 1 phút."
        }
    }

    static func detectionFinished(_ count: Int, language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "Detection finished with \(count) available link(s)."
        case .vietnamese:
            return "Đã quét xong với \(count) liên kết khả dụng."
        }
    }

    static func lookingForLocalLinks(language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "Looking for local React Native devtools links..."
        case .vietnamese:
            return "Đang tìm liên kết devtools React Native trên máy..."
        }
    }

    static func multipleTargetsFound(_ count: Int, language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "Found \(count) targets. Please choose one from the list below."
        case .vietnamese:
            return "Đã tìm thấy \(count) target. Vui lòng chọn một target trong danh sách bên dưới."
        }
    }

    static func chooseOneTarget(language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "Choose one target from the list below."
        case .vietnamese:
            return "Hãy chọn một target trong danh sách bên dưới."
        }
    }

    static func connectStatusTitle(isDisconnected: Bool, language: AppLanguage = AppLanguage.current()) -> String {
        isDisconnected ? text(.disconnected, language: language) : text(.connected, language: language)
    }

    static func disconnectButtonTitle(isDisconnected: Bool, language: AppLanguage = AppLanguage.current()) -> String {
        isDisconnected ? text(.disconnected, language: language) : text(.disconnect, language: language)
    }

    static func languageOptionTitle(_ languageOption: AppLanguage, currentLanguage: AppLanguage = AppLanguage.current()) -> String {
        switch languageOption {
        case .system:
            return text(.systemDefault, language: currentLanguage)
        case .english:
            return text(.english, language: currentLanguage)
        case .vietnamese:
            return text(.vietnamese, language: currentLanguage)
        }
    }

    static func networkDomainUnsupported(_ detail: String, language: AppLanguage = AppLanguage.current()) -> String {
        switch language.resolvedLanguage() {
        case .english:
            return "This React Native target does not expose Network domain events through the current inspector connection. Detail: \(detail)"
        case .vietnamese:
            return "Target React Native này không phát sự kiện Network domain qua kết nối inspector hiện tại. Chi tiết: \(detail)"
        }
    }

    private static func englishText(for key: AppTextKey) -> String {
        switch key {
        case .connections:
            return "Connections"
        case .connectionsSubtitle:
            return "Connect directly with a websocket URL or choose a detected React Native Hermes target."
        case .connectManually:
            return "Connect Manually"
        case .connectManuallySubtitle:
            return "Paste a websocket URL, a /json/list endpoint, or an inspector link."
        case .manualConnectPlaceholder:
            return "ws://localhost:8081/inspector/debug?... or http://localhost:8081/json/list"
        case .connect:
            return "Connect"
        case .availableConnections:
            return "Available Connections"
        case .availableConnectionsSubtitle:
            return "Local Hermes targets discovered on this Mac."
        case .noConnectionsFoundYet:
            return "No connections found yet"
        case .detectAgain:
            return "Detect Again"
        case .unknownTarget:
            return "Unknown Target"
        case .invalidInput:
            return "The input is not a supported websocket, /json/list, or inspector link."
        case .noTargetsFound:
            return "No connectable target was found for this link."
        case .timedOut:
            return "The connection timed out."
        case .unableToEncodeWebSocketCommand:
            return "Unable to encode websocket command."
        case .consoleMessage:
            return "Console message"
        case .consoleSource:
            return "Console"
        case .consoleEntry:
            return "Console entry"
        case .javaScriptException:
            return "JavaScript exception"
        case .exceptionSource:
            return "Exception"
        case .loading:
            return "Loading..."
        case .detectLinks:
            return "Detect Links"
        case .allLevels:
            return "All Levels"
        case .noLogsMatchCurrentFilters:
            return "No logs match the current filters."
        case .waitingForConsoleLogs:
            return "Waiting for console logs"
        case .adjustSearchOrLevelFilter:
            return "Adjust the search terms or level filter to see matching console messages."
        case .consoleOutputWillAppear:
            return "React Native console output appears here after the connected Hermes target starts sending events."
        case .back:
            return "Back"
        case .consoleTitle:
            return "Console"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .disconnect:
            return "Disconnect"
        case .consoleLogTabTitle:
            return "Console log"
        case .networkLogTabTitle:
            return "Network log"
        case .searchConsoleMessages:
            return "Search console messages"
        case .searchNetworkLogs:
            return "Search network logs"
        case .add:
            return "Add"
        case .pinSearchTerm:
            return "Pin search term"
        case .showAllLevels:
            return "Show All Levels"
        case .clear:
            return "Clear"
        case .collapse:
            return "Collapse"
        case .expand:
            return "Expand"
        case .removeSearchTerm:
            return "Remove search term"
        case .waitingForNetworkLogs:
            return "Waiting for network logs"
        case .networkOutputWillAppear:
            return "Actual network requests will appear here when the connected app streams events from rnv_network_sdk or a supported Network domain."
        case .networkDomainUnsupportedTitle:
            return "Network capture is unavailable"
        case .languageSettingsTitle:
            return "Language"
        case .languageSettingsDescription:
            return "Choose how React Native Viewer displays its interface."
        case .displayLanguage:
            return "Display Language"
        case .systemDefault:
            return "System Default"
        case .english:
            return "English"
        case .vietnamese:
            return "Tiếng Việt"
        }
    }

    private static func vietnameseText(for key: AppTextKey) -> String {
        switch key {
        case .connections:
            return "Kết nối"
        case .connectionsSubtitle:
            return "Kết nối trực tiếp bằng URL websocket hoặc chọn target React Native Hermes được phát hiện."
        case .connectManually:
            return "Kết nối thủ công"
        case .connectManuallySubtitle:
            return "Dán URL websocket, endpoint /json/list hoặc inspector link."
        case .manualConnectPlaceholder:
            return "ws://localhost:8081/inspector/debug?... hoặc http://localhost:8081/json/list"
        case .connect:
            return "Kết nối"
        case .availableConnections:
            return "Kết nối khả dụng"
        case .availableConnectionsSubtitle:
            return "Các target Hermes cục bộ được phát hiện trên máy Mac này."
        case .noConnectionsFoundYet:
            return "Chưa tìm thấy kết nối nào"
        case .detectAgain:
            return "Quét lại"
        case .unknownTarget:
            return "Target không xác định"
        case .invalidInput:
            return "Dữ liệu nhập không phải websocket, /json/list hoặc inspector link được hỗ trợ."
        case .noTargetsFound:
            return "Không tìm thấy target có thể kết nối từ liên kết này."
        case .timedOut:
            return "Kết nối đã hết thời gian chờ."
        case .unableToEncodeWebSocketCommand:
            return "Không thể mã hóa lệnh websocket."
        case .consoleMessage:
            return "Thông điệp console"
        case .consoleSource:
            return "Console"
        case .consoleEntry:
            return "Mục console"
        case .javaScriptException:
            return "Ngoại lệ JavaScript"
        case .exceptionSource:
            return "Ngoại lệ"
        case .loading:
            return "Đang tải..."
        case .detectLinks:
            return "Quét liên kết"
        case .allLevels:
            return "Tất cả mức"
        case .noLogsMatchCurrentFilters:
            return "Không có log nào khớp với bộ lọc hiện tại."
        case .waitingForConsoleLogs:
            return "Đang chờ log console"
        case .adjustSearchOrLevelFilter:
            return "Hãy điều chỉnh từ khóa tìm kiếm hoặc bộ lọc mức để xem log phù hợp."
        case .consoleOutputWillAppear:
            return "Log console của React Native sẽ xuất hiện ở đây sau khi target Hermes đã kết nối bắt đầu gửi sự kiện."
        case .back:
            return "Quay lại"
        case .consoleTitle:
            return "Console"
        case .connected:
            return "Đã kết nối"
        case .disconnected:
            return "Đã ngắt kết nối"
        case .disconnect:
            return "Ngắt kết nối"
        case .consoleLogTabTitle:
            return "Log console"
        case .networkLogTabTitle:
            return "Log network"
        case .searchConsoleMessages:
            return "Tìm log console"
        case .searchNetworkLogs:
            return "Tìm log network"
        case .add:
            return "Thêm"
        case .pinSearchTerm:
            return "Ghim từ khóa tìm kiếm"
        case .showAllLevels:
            return "Hiện tất cả mức"
        case .clear:
            return "Xóa"
        case .collapse:
            return "Thu gọn"
        case .expand:
            return "Mở rộng"
        case .removeSearchTerm:
            return "Xóa từ khóa tìm kiếm"
        case .waitingForNetworkLogs:
            return "Đang chờ log network"
        case .networkOutputWillAppear:
            return "Các request network thực tế sẽ xuất hiện ở đây khi app đang kết nối stream sự kiện từ rnv_network_sdk hoặc từ Network domain được hỗ trợ."
        case .networkDomainUnsupportedTitle:
            return "Không thể bắt network"
        case .languageSettingsTitle:
            return "Ngôn ngữ"
        case .languageSettingsDescription:
            return "Chọn ngôn ngữ hiển thị của React Native Viewer."
        case .displayLanguage:
            return "Ngôn ngữ hiển thị"
        case .systemDefault:
            return "Theo hệ thống"
        case .english:
            return "English"
        case .vietnamese:
            return "Tiếng Việt"
        }
    }
}
