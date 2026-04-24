import Combine
import SwiftUI

@MainActor
final class WorkspaceSessionStore: ObservableObject {
    @Published private(set) var sessions: [DevtoolsConsoleSession] = []
    @Published private(set) var activeSessionID: DevtoolsConsoleSession.ID?

    private var sdkEnvelopeCancellable: AnyCancellable?
    private var sdkClientStatesCancellable: AnyCancellable?
    private var sdkClientStates: [String: RNVNetworkSDKClientState] = [:]
    private var sdkAssignments: [String: DevtoolsConsoleSession.ID] = [:]

    init(
        sdkEnvelopePublisher: AnyPublisher<RNVNetworkSDKEnvelope, Never> = RNVNetworkSDKIngestServer.shared.envelopePublisher.eraseToAnyPublisher(),
        sdkClientStatesPublisher: AnyPublisher<[String: RNVNetworkSDKClientState], Never> = RNVNetworkSDKIngestServer.shared.$clientStates.eraseToAnyPublisher()
    ) {
        bindSDKStreams(
            sdkEnvelopePublisher: sdkEnvelopePublisher,
            sdkClientStatesPublisher: sdkClientStatesPublisher
        )
    }

    var activeSession: DevtoolsConsoleSession? {
        guard let activeSessionID else {
            return nil
        }

        return sessions.first { $0.id == activeSessionID }
    }

    func connect(_ session: DevtoolsConsoleSession) {
        if let existingSession = sessions.first(where: {
            $0.candidate.webSocketURL.absoluteString == session.candidate.webSocketURL.absoluteString
        }) {
            if existingSession.id != session.id {
                session.disconnect()
            }

            activeSessionID = existingSession.id
            return
        }

        sessions.append(session)
        activeSessionID = session.id
        rebindKnownSDKSessions()
    }

    func showHome() {
        activeSessionID = nil
    }

    func select(_ session: DevtoolsConsoleSession) {
        guard sessions.contains(where: { $0.id == session.id }) else {
            return
        }

        activeSessionID = session.id
    }

    func disconnect(_ session: DevtoolsConsoleSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].disconnect()
            sessions.remove(at: index)
        } else {
            session.disconnect()
        }

        sdkAssignments = sdkAssignments.filter { $0.value != session.id }

        if activeSessionID == session.id {
            activeSessionID = nil
        }

        rebindKnownSDKSessions()
    }

    private func bindSDKStreams(
        sdkEnvelopePublisher: AnyPublisher<RNVNetworkSDKEnvelope, Never>,
        sdkClientStatesPublisher: AnyPublisher<[String: RNVNetworkSDKClientState], Never>
    ) {
        sdkEnvelopeCancellable = sdkEnvelopePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope in
                self?.routeSDKEnvelope(envelope)
            }

        sdkClientStatesCancellable = sdkClientStatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                self?.handleSDKClientStates(states)
            }
    }

    private func handleSDKClientStates(_ states: [String: RNVNetworkSDKClientState]) {
        sdkClientStates = states
        rebindKnownSDKSessions()
        applySDKClientStatesToSessions()
    }

    private func routeSDKEnvelope(_ envelope: RNVNetworkSDKEnvelope) {
        guard let session = targetSession(for: envelope.session) else {
            return
        }

        session.bindSDKSession(envelope.session)
        sdkAssignments[envelope.session.id] = session.id
        session.applySDKEnvelope(envelope)

        if let state = sdkClientStates[envelope.session.id] {
            session.updateSDKClientState(state)
        }
    }

    private func rebindKnownSDKSessions() {
        for state in sdkClientStates.values {
            guard let session = targetSession(for: state.session) else {
                continue
            }

            session.bindSDKSession(state.session)
            sdkAssignments[state.session.id] = session.id
        }
    }

    private func applySDKClientStatesToSessions() {
        for session in sessions {
            guard let sdkSessionID = session.sdkSessionID else {
                session.updateSDKClientState(nil)
                continue
            }

            session.updateSDKClientState(sdkClientStates[sdkSessionID])
        }
    }

    private func targetSession(for sdkSession: RNVNetworkSDKSession) -> DevtoolsConsoleSession? {
        if let assignedSessionID = sdkAssignments[sdkSession.id],
           let assignedSession = sessions.first(where: { $0.id == assignedSessionID }) {
            return assignedSession
        }

        let candidates = sessions
            .filter { session in
                guard let boundSDKSessionID = session.sdkSessionID else {
                    return true
                }

                return boundSDKSessionID == sdkSession.id
            }
            .map { session in
                (session: session, score: session.sdkMatchScore(for: sdkSession))
            }
            .filter { $0.score != .min }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.session.connectedAt < rhs.session.connectedAt
                }

                return lhs.score > rhs.score
            }

        return candidates.first?.session
    }
}

enum WorkspaceRailSelection: Equatable {
    case home
    case settings
    case mobile(DevtoolsConsoleSession.ID)
}

struct WorkspaceRailMobileItem: Identifiable, Equatable {
    let id: DevtoolsConsoleSession.ID
    let title: String
    let badge: String?

    static func items(from sessions: [DevtoolsConsoleSession], language: AppLanguage) -> [WorkspaceRailMobileItem] {
        let showsIndexedLabels = sessions.count > 1
        let baseTitle: String
        switch language.resolvedLanguage() {
        case .english:
            baseTitle = "Mobile"
        case .vietnamese:
            baseTitle = "Thiết bị"
        }

        return sessions.enumerated().map { index, session in
            WorkspaceRailMobileItem(
                id: session.id,
                title: showsIndexedLabels ? "\(baseTitle) \(index + 1)" : baseTitle,
                badge: showsIndexedLabels ? "\(index + 1)" : nil
            )
        }
    }
}

struct WorkspaceLeftRail: View {
    let palette: FlipperPalette
    let language: AppLanguage
    @Binding var isExpanded: Bool
    let selection: WorkspaceRailSelection
    let mobileItems: [WorkspaceRailMobileItem]
    let onHome: () -> Void
    let onSelectMobile: (DevtoolsConsoleSession.ID) -> Void
    let onSettings: () -> Void

    static func width(isExpanded: Bool) -> CGFloat {
        isExpanded ? 156 : 52
    }

    private var toggleTitle: String {
        switch language.resolvedLanguage() {
        case .english:
            return isExpanded ? "Collapse" : "Expand"
        case .vietnamese:
            return isExpanded ? "Thu gọn" : "Mở rộng"
        }
    }

    var body: some View {
        VStack(alignment: isExpanded ? .leading : .center, spacing: 8) {
            toggleButton
                .padding(.top, 12)

            navigationButton(
                icon: "house",
                title: language.resolvedLanguage() == .english ? "Home" : "Trang chủ",
                isSelected: selection == .home,
                badge: nil,
                action: onHome
            )

            ForEach(mobileItems) { item in
                navigationButton(
                    icon: "iphone",
                    title: item.title,
                    isSelected: selection == .mobile(item.id),
                    badge: item.badge
                ) {
                    onSelectMobile(item.id)
                }
            }

            navigationButton(
                icon: "gearshape",
                title: language.resolvedLanguage() == .english ? "Settings" : "Cài đặt",
                isSelected: selection == .settings,
                badge: nil,
                action: onSettings
            )

            Spacer()
        }
        .padding(.horizontal, isExpanded ? 10 : 8)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 18, height: 18)

                if isExpanded {
                    Text(toggleTitle)
                        .font(FlipperTypography.bodyStrong)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isExpanded ? 10 : 0)
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.panelMutedBackground)
            )
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private func navigationButton(
        icon: String,
        title: String,
        isSelected: Bool,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                    .frame(width: 18, height: 18)

                if isExpanded {
                    Text(title)
                        .font(FlipperTypography.bodyStrong)
                        .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isExpanded ? 10 : 0)
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.accentMuted : Color.clear)
            )
            .overlay(alignment: .topTrailing) {
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(FlipperTypography.micro)
                        .foregroundStyle(palette.invertedText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(palette.accent)
                        )
                        .offset(x: isExpanded ? 6 : 2, y: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    @StateObject private var workspaceStore = WorkspaceSessionStore()

    var body: some View {
        Group {
            if let activeConsoleSession = workspaceStore.activeSession {
                ConsoleDebuggerView(
                    session: activeConsoleSession,
                    connectedSessions: workspaceStore.sessions,
                    onShowHome: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspaceStore.showHome()
                        }
                    },
                    onSelectSession: { session in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspaceStore.select(session)
                        }
                    },
                    onDisconnect: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspaceStore.disconnect(activeConsoleSession)
                        }
                    }
                )
            } else {
                DevtoolsWebFinderView(
                    connectedSessions: workspaceStore.sessions,
                    onConnected: { session in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspaceStore.connect(session)
                        }
                    },
                    onSelectSession: { session in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspaceStore.select(session)
                        }
                    }
                )
            }
        }
        .frame(minWidth: 1280, minHeight: 720)
    }
}

#Preview {
    ContentView()
}
