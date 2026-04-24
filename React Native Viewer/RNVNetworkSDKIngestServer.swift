import Combine
import CryptoKit
import Foundation
import Network

enum RNVNetworkSDKIngestStatus: Equatable {
    case idle
    case listening(port: UInt16)
    case clientConnected(appName: String, deviceName: String)
    case failed(String)

    var hasConnectedClient: Bool {
        if case .clientConnected = self {
            return true
        }

        return false
    }
}

enum RNVNetworkSDKClientConnectionStatus: Equatable {
    case connected
    case disconnected
    case failed(String)
}

struct RNVNetworkSDKClientState: Equatable {
    let session: RNVNetworkSDKSession
    let connectionStatus: RNVNetworkSDKClientConnectionStatus
}

final class RNVNetworkSDKIngestServer: ObservableObject {
    static let shared = RNVNetworkSDKIngestServer()
    static let defaultPort: UInt16 = 38_940
    static let defaultPath = "/rnv/network"

    @Published private(set) var status: RNVNetworkSDKIngestStatus = .idle
    @Published private(set) var clientStates: [String: RNVNetworkSDKClientState] = [:]

    let envelopePublisher = PassthroughSubject<RNVNetworkSDKEnvelope, Never>()

    private let queue = DispatchQueue(label: "com.reactnativeviewer.rnv-network-ingest")
    private var listener: NWListener?
    private var activeClients: [UUID: RNVNetworkSDKWebSocketClientConnection] = [:]
    private var sessionIDsByConnectionID: [UUID: String] = [:]
    private var connectionIDsBySessionID: [String: UUID] = [:]
    private var latestClientStates: [String: RNVNetworkSDKClientState] = [:]
    private var isStarted = false

    private init() {}

    func startIfNeeded() {
        guard !isStarted else {
            return
        }

        isStarted = true

        do {
            let port = try NWEndpoint.Port(rawValue: Self.defaultPort).unwrap(
                or: "Invalid ingest port \(Self.defaultPort)."
            )
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else {
                    return
                }

                switch state {
                case .ready:
                    self.publishStatus(.listening(port: Self.defaultPort))
                case .failed(let error):
                    self.publishStatus(.failed(error.localizedDescription))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.start(queue: queue)
        } catch {
            publishStatus(.failed(error.localizedDescription))
        }
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = UUID()
        let client = RNVNetworkSDKWebSocketClientConnection(
            connection: connection,
            expectedPath: Self.defaultPath
        )
        activeClients[connectionID] = client

        client.onOpen = { [weak self] in
            self?.publishAggregateStatus()
        }

        client.onTextMessage = { [weak self] message in
            self?.handleTextMessage(message, connectionID: connectionID)
        }

        client.onClose = { [weak self] in
            self?.handleClientTermination(connectionID: connectionID, failureDetail: nil)
        }

        client.onFailure = { [weak self] detail in
            self?.handleClientTermination(connectionID: connectionID, failureDetail: detail)
        }

        client.start(on: queue)
    }

    private func handleTextMessage(_ message: String, connectionID: UUID) {
        guard let envelope = RNVNetworkSDKEnvelopeParser.parseEnvelope(Data(message.utf8)) else {
            return
        }

        sessionIDsByConnectionID[connectionID] = envelope.session.id
        connectionIDsBySessionID[envelope.session.id] = connectionID
        publishClientState(
            RNVNetworkSDKClientState(
                session: envelope.session,
                connectionStatus: .connected
            )
        )
        publishAggregateStatus(preferredSessionID: envelope.session.id)
        envelopePublisher.send(envelope)
    }

    private func handleClientTermination(connectionID: UUID, failureDetail: String?) {
        activeClients.removeValue(forKey: connectionID)

        guard let sessionID = sessionIDsByConnectionID.removeValue(forKey: connectionID) else {
            if let failureDetail, connectedClientState(preferredSessionID: nil) == nil {
                publishStatus(.failed(failureDetail))
            } else {
                publishAggregateStatus()
            }
            return
        }

        if connectionIDsBySessionID[sessionID] == connectionID {
            connectionIDsBySessionID.removeValue(forKey: sessionID)
        }

        if let existingState = latestClientStates[sessionID] {
            let nextStatus: RNVNetworkSDKClientConnectionStatus
            if let failureDetail, !failureDetail.isEmpty {
                nextStatus = .failed(failureDetail)
            } else {
                nextStatus = .disconnected
            }

            publishClientState(
                RNVNetworkSDKClientState(
                    session: existingState.session,
                    connectionStatus: nextStatus
                )
            )
        }

        if let failureDetail, connectedClientState(preferredSessionID: nil) == nil {
            publishStatus(.failed(failureDetail))
        } else {
            publishAggregateStatus()
        }
    }

    private func publishClientState(_ nextState: RNVNetworkSDKClientState) {
        latestClientStates[nextState.session.id] = nextState
        DispatchQueue.main.async { [weak self] in
            self?.clientStates[nextState.session.id] = nextState
        }
    }

    private func publishAggregateStatus(preferredSessionID: String? = nil) {
        if let connectedState = connectedClientState(preferredSessionID: preferredSessionID) {
            publishStatus(
                .clientConnected(
                    appName: connectedState.session.appName,
                    deviceName: connectedState.session.deviceName
                )
            )
            return
        }

        if listener != nil, isStarted {
            publishStatus(.listening(port: Self.defaultPort))
        } else {
            publishStatus(.idle)
        }
    }

    private func connectedClientState(preferredSessionID: String?) -> RNVNetworkSDKClientState? {
        if let preferredSessionID,
           let preferredState = latestClientStates[preferredSessionID],
           preferredState.connectionStatus == .connected {
            return preferredState
        }

        return latestClientStates.values.first { $0.connectionStatus == .connected }
    }

    private func publishStatus(_ nextStatus: RNVNetworkSDKIngestStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.status = nextStatus
        }
    }
}

private final class RNVNetworkSDKWebSocketClientConnection {
    private let connection: NWConnection
    private let expectedPath: String

    private var didCompleteHandshake = false
    private var didClose = false
    private var buffer = Data()

    var onOpen: (() -> Void)?
    var onTextMessage: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onFailure: ((String) -> Void)?

    init(connection: NWConnection, expectedPath: String) {
        self.connection = connection
        self.expectedPath = expectedPath
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }

            switch state {
            case .failed(let error):
                self.finish(withFailure: error.localizedDescription)
            case .cancelled:
                self.finish()
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveNextChunk()
    }

    func stop() {
        guard !didClose else {
            return
        }

        didClose = true
        sendFrame(opcode: 0x8, payload: Data())
        connection.cancel()
        onClose?()
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let error {
                self.finish(withFailure: error.localizedDescription)
                return
            }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                self.finish()
                return
            }

            if !self.didClose {
                self.receiveNextChunk()
            }
        }
    }

    private func processBuffer() {
        if !didCompleteHandshake {
            processHandshake()
        }

        if didCompleteHandshake {
            processWebSocketFrames()
        }
    }

    private func processHandshake() {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            return
        }

        let requestData = buffer.subdata(in: 0..<headerRange.lowerBound)
        buffer.removeSubrange(0..<headerRange.upperBound)

        guard let requestString = String(data: requestData, encoding: .utf8) else {
            finish(withFailure: "Invalid websocket handshake encoding.")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard
            let requestLine = lines.first,
            let handshake = parseHandshake(from: requestLine, headers: Array(lines.dropFirst()))
        else {
            finish(withFailure: "Invalid websocket handshake request.")
            return
        }

        guard handshake.path == expectedPath else {
            finish(withFailure: "Unsupported websocket path \(handshake.path).")
            return
        }

        let response = handshakeResponse(for: handshake.key)
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else {
                return
            }

            if let error {
                self.finish(withFailure: error.localizedDescription)
                return
            }

            self.didCompleteHandshake = true
            self.onOpen?()
            self.processBuffer()
        })
    }

    private func processWebSocketFrames() {
        while let frame = nextFrame() {
            switch frame.opcode {
            case 0x1:
                guard let text = String(data: frame.payload, encoding: .utf8) else {
                    finish(withFailure: "Received non-UTF8 websocket text frame.")
                    return
                }

                onTextMessage?(text)
            case 0x8:
                stop()
                return
            case 0x9:
                sendFrame(opcode: 0xA, payload: frame.payload)
            case 0xA:
                break
            default:
                break
            }
        }
    }

    private func nextFrame() -> WebSocketFrame? {
        let bytes = Array(buffer)
        guard bytes.count >= 2 else {
            return nil
        }

        let firstByte = bytes[0]
        let secondByte = bytes[1]
        let isFinalFrame = (firstByte & 0x80) != 0
        let opcode = firstByte & 0x0F
        let isMasked = (secondByte & 0x80) != 0

        guard isFinalFrame else {
            finish(withFailure: "Fragmented websocket frames are not supported.")
            return nil
        }

        guard isMasked else {
            finish(withFailure: "Client websocket frames must be masked.")
            return nil
        }

        var offset = 2
        var payloadLength = Int(secondByte & 0x7F)

        if payloadLength == 126 {
            guard bytes.count >= offset + 2 else {
                return nil
            }

            payloadLength = Int(UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]))
            offset += 2
        } else if payloadLength == 127 {
            guard bytes.count >= offset + 8 else {
                return nil
            }

            payloadLength = bytes[offset..<(offset + 8)].reduce(0) { partialResult, byte in
                (partialResult << 8) | Int(byte)
            }
            offset += 8
        }

        guard bytes.count >= offset + 4 else {
            return nil
        }

        let maskingKey = Array(bytes[offset..<(offset + 4)])
        offset += 4

        guard bytes.count >= offset + payloadLength else {
            return nil
        }

        let maskedPayload = Array(bytes[offset..<(offset + payloadLength)])
        let payload = Data(maskedPayload.enumerated().map { index, byte in
            byte ^ maskingKey[index % maskingKey.count]
        })

        buffer.removeSubrange(0..<(offset + payloadLength))
        return WebSocketFrame(opcode: opcode, payload: payload)
    }

    private func sendFrame(opcode: UInt8, payload: Data) {
        var frame = Data()
        frame.append(0x80 | opcode)

        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= 65_535 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }

        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func parseHandshake(from requestLine: String, headers: [String]) -> HandshakeRequest? {
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }

        var headerMap: [String: String] = [:]
        for header in headers {
            let pieces = header.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else {
                continue
            }

            headerMap[pieces[0].lowercased()] = pieces[1].trimmed
        }

        guard let key = headerMap["sec-websocket-key"]?.nonEmpty else {
            return nil
        }

        return HandshakeRequest(path: parts[1], key: key)
    }

    private func handshakeResponse(for key: String) -> String {
        let acceptSource = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data(acceptSource.utf8))
        let accept = Data(digest).base64EncodedString()

        return [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "",
            ""
        ].joined(separator: "\r\n")
    }

    private func finish(withFailure detail: String) {
        guard !didClose else {
            return
        }

        didClose = true
        connection.cancel()
        onFailure?(detail)
    }

    private func finish() {
        guard !didClose else {
            return
        }

        didClose = true
        connection.cancel()
        onClose?()
    }
}

private struct HandshakeRequest {
    let path: String
    let key: String
}

private struct WebSocketFrame {
    let opcode: UInt8
    let payload: Data
}

private extension Optional {
    func unwrap(or message: @autoclosure () -> String) throws -> Wrapped {
        guard let wrapped = self else {
            throw NSError(domain: "RNVNetworkSDKIngestServer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message()
            ])
        }

        return wrapped
    }
}
