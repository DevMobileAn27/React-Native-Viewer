import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct FlipperPalette {
    let accent: Color
    let accentMuted: Color
    let success: Color
    let warning: Color
    let error: Color
    let shellBackground: Color
    let sidebarBackground: Color
    let panelBackground: Color
    let panelMutedBackground: Color
    let controlBackground: Color
    let controlHoverBackground: Color
    let selectedSidebarBackground: Color
    let border: Color
    let divider: Color
    let primaryText: Color
    let secondaryText: Color
    let placeholderText: Color
    let disabledText: Color
    let invertedText: Color

    var backgroundDefault: Color {
        panelBackground
    }

    var backgroundWash: Color {
        shellBackground
    }

    init(for colorScheme: ColorScheme) {
        if colorScheme == .dark {
            accent = Color(hex: 0x9254DE)
            accentMuted = Color(hex: 0x9254DE, opacity: 0.20)
            success = Color(hex: 0x49AA19)
            warning = Color(hex: 0xD89614)
            error = Color(hex: 0xF5222D)
            shellBackground = Color(hex: 0x121212)
            sidebarBackground = Color(hex: 0x0F0F0F)
            panelBackground = Color(hex: 0x000000)
            panelMutedBackground = Color.white.opacity(0.06)
            controlBackground = Color.white.opacity(0.15)
            controlHoverBackground = Color.white.opacity(0.22)
            selectedSidebarBackground = accentMuted
            border = Color(hex: 0x1C1C1C)
            divider = Color(hex: 0x1C1C1C)
            primaryText = .white
            secondaryText = Color(hex: 0x999999)
            placeholderText = Color(hex: 0x737373)
            disabledText = Color(hex: 0x404040)
            invertedText = .white
        } else {
            accent = Color(hex: 0x722ED1)
            accentMuted = Color(hex: 0x722ED1, opacity: 0.14)
            success = Color(hex: 0x389E0D)
            warning = Color(hex: 0xFAAD14)
            error = Color(hex: 0xF5222D)
            shellBackground = Color(hex: 0xF2F2F2)
            sidebarBackground = Color(hex: 0xF7F7F7)
            panelBackground = .white
            panelMutedBackground = Color.black.opacity(0.03)
            controlBackground = Color.black.opacity(0.10)
            controlHoverBackground = Color.black.opacity(0.15)
            selectedSidebarBackground = accentMuted
            border = Color(hex: 0xECECEC)
            divider = Color(hex: 0xECECEC)
            primaryText = .black
            secondaryText = Color(hex: 0x666666)
            placeholderText = Color(hex: 0x8C8C8C)
            disabledText = Color(hex: 0xBFBFBF)
            invertedText = .white
        }
    }
}

enum FlipperTypography {
    static let title1 = Font.system(size: 24, weight: .semibold)
    static let title2 = Font.system(size: 20, weight: .semibold)
    static let title3 = Font.system(size: 16, weight: .semibold)
    static let title4 = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionStrong = Font.system(size: 12, weight: .semibold)
    static let micro = Font.system(size: 11, weight: .medium)
    static let code = Font.system(size: 12, weight: .regular, design: .monospaced)
}

struct FlipperPanel<Content: View>: View {
    let palette: FlipperPalette
    let padding: CGFloat
    let fill: Color
    @ViewBuilder let content: Content

    init(
        palette: FlipperPalette,
        padding: CGFloat = 16,
        fill: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.padding = padding
        self.fill = fill ?? palette.panelBackground
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

struct FlipperSidebarSection<Content: View>: View {
    let title: String
    let palette: FlipperPalette
    @ViewBuilder let content: Content

    init(
        title: String,
        palette: FlipperPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(FlipperTypography.micro)
                .foregroundStyle(palette.secondaryText)
                .tracking(0.6)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

struct FlipperSidebarItem: View {
    let icon: String
    let title: String
    let subtitle: String?
    let badge: String?
    let isSelected: Bool
    let palette: FlipperPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FlipperTypography.bodyStrong)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(FlipperTypography.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(FlipperTypography.micro)
                        .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? palette.accentMuted : palette.panelMutedBackground)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? palette.selectedSidebarBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FlipperTag: View {
    let title: String
    let tint: Color
    let palette: FlipperPalette

    var body: some View {
        Text(title)
            .font(FlipperTypography.micro)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}

struct FlipperPrimaryButtonStyle: ButtonStyle {
    let palette: FlipperPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlipperTypography.bodyStrong)
            .foregroundStyle(palette.invertedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? palette.accent.opacity(0.86) : palette.accent)
            )
    }
}

struct FlipperSecondaryButtonStyle: ButtonStyle {
    let palette: FlipperPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlipperTypography.bodyStrong)
            .foregroundStyle(palette.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? palette.controlHoverBackground : palette.controlBackground)
            )
    }
}

struct FlipperGhostButtonStyle: ButtonStyle {
    let palette: FlipperPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlipperTypography.bodyStrong)
            .foregroundStyle(palette.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? palette.panelMutedBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
    }
}

struct FlipperDangerGhostButtonStyle: ButtonStyle {
    let background: Color
    let border: Color
    let foreground: Color
    let pressedBackground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlipperTypography.bodyStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? pressedBackground : background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
}

struct FlipperInputFieldStyle: TextFieldStyle {
    let palette: FlipperPalette

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(FlipperTypography.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
