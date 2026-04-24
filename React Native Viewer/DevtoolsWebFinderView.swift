import SwiftUI

private enum FinderWorkspaceDestination {
    case home
    case settings
}

struct DevtoolsWebFinderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    @StateObject private var viewModel: DevtoolsWebFinderViewModel
    @State private var isRailExpanded = false
    @State private var selectedDestination: FinderWorkspaceDestination = .home

    let connectedSessions: [DevtoolsConsoleSession]
    let onSelectSession: (DevtoolsConsoleSession) -> Void

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }

    init(
        connectedSessions: [DevtoolsConsoleSession] = [],
        onConnected: @escaping (DevtoolsConsoleSession) -> Void,
        onSelectSession: @escaping (DevtoolsConsoleSession) -> Void = { _ in }
    ) {
        self.connectedSessions = connectedSessions
        self.onSelectSession = onSelectSession
        _viewModel = StateObject(
            wrappedValue: DevtoolsWebFinderViewModel(onConnected: onConnected)
        )
    }

    var body: some View {
        let palette = FlipperPalette(for: colorScheme)
        let mobileItems = WorkspaceRailMobileItem.items(from: connectedSessions, language: language)

        HStack(spacing: 0) {
            WorkspaceLeftRail(
                palette: palette,
                language: language,
                isExpanded: $isRailExpanded,
                selection: selectedDestination == .settings ? .settings : .home,
                mobileItems: mobileItems,
                onHome: {
                    selectedDestination = .home
                },
                onSelectMobile: { sessionID in
                    guard let session = connectedSessions.first(where: { $0.id == sessionID }) else {
                        return
                    }

                    onSelectSession(session)
                },
                onSettings: {
                    selectedDestination = .settings
                }
            )
            .frame(width: WorkspaceLeftRail.width(isExpanded: isRailExpanded))

            Rectangle()
                .fill(palette.divider)
                .frame(width: 1)

            Group {
                if selectedDestination == .settings {
                    AppSettingsView(embeddedInWorkspace: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    HStack(spacing: 0) {
                        sidebar(palette: palette)
                            .frame(width: 260)

                        Rectangle()
                            .fill(palette.divider)
                            .frame(width: 1)

                        VStack(spacing: 0) {
                            topToolbar(palette: palette)

                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 16) {
                                    manualConnectSection(palette: palette)
                                    availableConnectionsSection(palette: palette)
                                }
                                .frame(maxWidth: 980, alignment: .leading)
                                .padding(20)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.shellBackground)
        }
        .background(palette.shellBackground)
        .task {
            viewModel.startDetection()
        }
        .onDisappear {
            viewModel.stopDetection()
        }
    }

    private func sidebar(palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("React Native Viewer")
                    .font(FlipperTypography.title3)
                    .foregroundStyle(palette.primaryText)

                Text(AppStrings.text(.connectionsSubtitle, language: language))
                    .font(FlipperTypography.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlipperPanel(palette: palette, padding: 14, fill: palette.panelBackground) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppStrings.text(.connections, language: language).uppercased())
                        .font(FlipperTypography.micro)
                        .foregroundStyle(palette.secondaryText)
                        .tracking(0.6)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.isDetecting ? palette.warning : palette.success)
                            .frame(width: 8, height: 8)

                        Text(viewModel.isDetecting ? AppStrings.text(.loading, language: language) : viewModel.statusMessage)
                            .font(FlipperTypography.caption)
                            .foregroundStyle(palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                        .overlay(palette.divider)

                    sidebarMetricRow(
                        title: AppStrings.text(.availableConnections, language: language),
                        value: "\(viewModel.detectedCandidates.count)",
                        palette: palette
                    )

                    sidebarMetricRow(
                        title: AppStrings.text(.connected, language: language),
                        value: "\(connectedSessions.count)",
                        palette: palette
                    )
                }
            }

            FlipperPanel(palette: palette, padding: 14, fill: palette.panelBackground) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.text(.connectManually, language: language))
                        .font(FlipperTypography.title4)
                        .foregroundStyle(palette.primaryText)

                    Text(AppStrings.text(.connectManuallySubtitle, language: language))
                        .font(FlipperTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppStrings.text(.availableConnectionsSubtitle, language: language))
                        .font(FlipperTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(palette.sidebarBackground)
    }

    private func sidebarMetricRow(
        title: String,
        value: String,
        palette: FlipperPalette
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(FlipperTypography.caption)
                .foregroundStyle(palette.secondaryText)

            Spacer(minLength: 8)

            Text(value)
                .font(FlipperTypography.bodyStrong)
                .foregroundStyle(palette.primaryText)
        }
    }

    private func topToolbar(palette: FlipperPalette) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.text(.connections, language: language))
                    .font(FlipperTypography.title2)
                    .foregroundStyle(palette.primaryText)

                Text(AppStrings.text(.connectionsSubtitle, language: language))
                    .font(FlipperTypography.body)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            if viewModel.isDetecting {
                ProgressView()
                    .controlSize(.small)
            }

            Button(AppStrings.text(.detectAgain, language: language)) {
                viewModel.startDetection()
            }
            .buttonStyle(FlipperSecondaryButtonStyle(palette: palette))
            .disabled(viewModel.isDetecting)

            AppLanguageQuickSwitcher()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(palette.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
        }
    }

    private func manualConnectSection(palette: FlipperPalette) -> some View {
        FlipperPanel(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: AppStrings.text(.connectManually, language: language),
                    subtitle: AppStrings.text(.connectManuallySubtitle, language: language),
                    palette: palette
                )

                HStack(alignment: .center, spacing: 10) {
                    TextField(
                        AppStrings.text(.manualConnectPlaceholder, language: language),
                        text: $viewModel.manualInput
                    )
                    .textFieldStyle(.plain)
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
                    .onSubmit {
                        viewModel.connectUsingManualInput()
                    }

                    Button {
                        viewModel.connectUsingManualInput()
                    } label: {
                        Group {
                            if viewModel.isConnectingManualInput {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 88)
                            } else {
                                Text(AppStrings.text(.connect, language: language))
                                    .frame(minWidth: 88)
                            }
                        }
                    }
                    .buttonStyle(FlipperPrimaryButtonStyle(palette: palette))
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.manualInput.trimmed.isEmpty || viewModel.isConnectingManualInput)
                }

                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.warning)

                        Text(errorMessage)
                            .font(FlipperTypography.caption)
                            .foregroundStyle(palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func availableConnectionsSection(palette: FlipperPalette) -> some View {
        FlipperPanel(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: AppStrings.text(.availableConnections, language: language),
                    subtitle: AppStrings.text(.availableConnectionsSubtitle, language: language),
                    palette: palette
                )

                if viewModel.detectedCandidates.isEmpty {
                    emptyConnectionsState(palette: palette)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.detectedCandidates) { candidate in
                            connectionRow(candidate: candidate, palette: palette)
                        }
                    }
                }

                detectorFooter(palette: palette)
            }
        }
    }

    private func emptyConnectionsState(palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.text(.noConnectionsFoundYet, language: language))
                .font(FlipperTypography.title4)
                .foregroundStyle(palette.primaryText)

            Text(viewModel.statusMessage)
                .font(FlipperTypography.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.panelMutedBackground)
        )
    }

    private func connectionRow(candidate: DevtoolsConnectionCandidate, palette: FlipperPalette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName(for: candidate))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accentMuted)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(FlipperTypography.bodyStrong)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Text(candidate.detailText)
                    .font(FlipperTypography.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.connect(candidate: candidate)
            } label: {
                Group {
                    if viewModel.connectingIdentifier == candidate.id {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 76)
                    } else {
                        Text(AppStrings.text(.connect, language: language))
                            .frame(minWidth: 76)
                    }
                }
            }
            .buttonStyle(FlipperPrimaryButtonStyle(palette: palette))
            .disabled(viewModel.connectingIdentifier != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.panelMutedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private func detectorFooter(palette: FlipperPalette) -> some View {
        HStack(spacing: 10) {
            if viewModel.isDetecting {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.statusMessage)
                .font(FlipperTypography.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(title: String, subtitle: String, palette: FlipperPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FlipperTypography.title3)
                .foregroundStyle(palette.primaryText)

            Text(subtitle)
                .font(FlipperTypography.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func symbolName(for candidate: DevtoolsConnectionCandidate) -> String {
        let lowercasedTitle = candidate.displayName.lowercased()
        let lowercasedDetail = candidate.detailText.lowercased()

        if lowercasedTitle.contains("iphone") || lowercasedTitle.contains("ios") || lowercasedDetail.contains("ios") {
            return "iphone.gen3"
        }

        if lowercasedTitle.contains("android") || lowercasedDetail.contains("android") {
            return "app.connected.to.app.below.fill"
        }

        return "bolt.horizontal.circle"
    }
}
