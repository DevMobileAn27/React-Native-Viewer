import SwiftUI

struct AppSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    private let embeddedInWorkspace: Bool

    init(embeddedInWorkspace: Bool = false) {
        self.embeddedInWorkspace = embeddedInWorkspace
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }

    var body: some View {
        let palette = FlipperPalette(for: colorScheme)

        ZStack {
            palette.shellBackground
                .modifier(IgnoreSafeAreaModifier(isEnabled: !embeddedInWorkspace))

            VStack(alignment: .leading, spacing: 16) {
                Text(AppStrings.text(.languageSettingsTitle, language: selectedLanguage))
                    .font(FlipperTypography.title2)
                    .foregroundStyle(palette.primaryText)

                Text(AppStrings.text(.languageSettingsDescription, language: selectedLanguage))
                    .font(FlipperTypography.body)
                    .foregroundStyle(palette.secondaryText)

                FlipperPanel(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppStrings.text(.displayLanguage, language: selectedLanguage))
                            .font(FlipperTypography.title4)
                            .foregroundStyle(palette.secondaryText)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(AppLanguage.allCases) { language in
                                Button {
                                    languageRawValue = language.rawValue
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: language == selectedLanguage ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(language == selectedLanguage ? palette.accent : palette.secondaryText)

                                        Text(AppStrings.languageOptionTitle(language, currentLanguage: selectedLanguage))
                                            .font(FlipperTypography.body)
                                            .foregroundStyle(palette.primaryText)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(language == selectedLanguage ? palette.selectedSidebarBackground : palette.panelMutedBackground)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: embeddedInWorkspace ? 520 : .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: embeddedInWorkspace ? nil : 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct IgnoreSafeAreaModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

#Preview {
    AppSettingsView()
}
