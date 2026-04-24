import SwiftUI

@main
struct ReactNativeViewerApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }

    init() {
        RNVNetworkSDKIngestServer.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color(hex: 0x722ED1))
                .preferredColorScheme(.light)
                .environment(\.locale, appLanguage.resolvedLocale)
        }
        .defaultSize(width: 1440, height: 810)
        .windowResizability(.contentMinSize)

        Settings {
            AppSettingsView()
                .tint(Color(hex: 0x722ED1))
                .preferredColorScheme(.light)
                .environment(\.locale, appLanguage.resolvedLocale)
        }
    }
}
