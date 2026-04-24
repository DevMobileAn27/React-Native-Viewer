import SwiftUI

struct AppLanguageQuickSwitcher: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }

    private var selection: Binding<AppLanguageQuickOption> {
        Binding(
            get: { currentLanguage.quickSelection },
            set: { languageRawValue = $0.appLanguage.rawValue }
        )
    }

    var body: some View {
        let palette = FlipperPalette(for: colorScheme)

        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondaryText)

            HStack(spacing: 4) {
                ForEach(AppLanguageQuickOption.allCases) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.shortTitle)
                            .font(FlipperTypography.micro)
                            .foregroundStyle(selection.wrappedValue == option ? palette.invertedText : palette.primaryText)
                            .frame(width: 34)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(selection.wrappedValue == option ? palette.accent : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.panelMutedBackground)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

#Preview {
    AppLanguageQuickSwitcher()
        .padding()
}
