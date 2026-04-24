import Foundation

struct RNVNetworkSDKEnvelope: Equatable {
    let session: RNVNetworkSDKSession
    let events: [RNVNetworkSDKEvent]
}

struct RNVNetworkSDKSession: Equatable {
    let id: String
    let platform: String
    let bundleIdentifier: String
    let appName: String
    let deviceName: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool
}

enum RNVNetworkSDKEventPhase: String, Codable, Equatable {
    case request
    case response
    case error
}

struct RNVNetworkSDKEvent: Equatable {
    let requestId: String
    let phase: RNVNetworkSDKEventPhase
    let source: String
    let timestamp: Date
    let method: String
    let url: String
    let requestHeaders: [String: String]
    let requestBody: String?
    let requestBodyPreview: String?
    let requestKind: String?
    let statusCode: Int?
    let statusText: String?
    let responseHeaders: [String: String]
    let responseBody: String?
    let responseBodyPreview: String?
    let durationMs: Int?
    let errorMessage: String?
}

enum RNVNetworkSDKEnvelopeParser {
    static func parseEnvelope(_ data: Data) -> RNVNetworkSDKEnvelope? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = ISO8601DateFormatter.rnvFractional.date(from: value)
                ?? ISO8601DateFormatter.rnvBasic.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 timestamp: \(value)"
            )
        }

        guard let envelope = try? decoder.decode(EnvelopeDTO.self, from: data) else {
            return nil
        }

        return envelope.toModel()
    }
}

private struct EnvelopeDTO: Decodable {
    let session: SessionDTO
    let events: [EventDTO]

    func toModel() -> RNVNetworkSDKEnvelope {
        RNVNetworkSDKEnvelope(
            session: session.toModel(),
            events: events.map { $0.toModel() }
        )
    }
}

private struct SessionDTO: Decodable {
    let id: String
    let platform: String
    let bundleIdentifier: String
    let appName: String
    let deviceName: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool

    func toModel() -> RNVNetworkSDKSession {
        RNVNetworkSDKSession(
            id: id,
            platform: platform,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            deviceName: deviceName,
            systemName: systemName,
            systemVersion: systemVersion,
            isSimulator: isSimulator
        )
    }
}

private struct EventDTO: Decodable {
    let requestId: String
    let phase: RNVNetworkSDKEventPhase
    let source: String?
    let timestamp: Date
    let durationMs: Int?
    let request: RequestDTO?
    let response: ResponseDTO?
    let error: ErrorDTO?

    func toModel() -> RNVNetworkSDKEvent {
        RNVNetworkSDKEvent(
            requestId: requestId,
            phase: phase,
            source: source ?? "",
            timestamp: timestamp,
            method: request?.method ?? "",
            url: request?.url ?? "",
            requestHeaders: request?.headers ?? [:],
            requestBody: request?.body ?? request?.bodyPreview,
            requestBodyPreview: request?.bodyPreview,
            requestKind: request?.requestKind,
            statusCode: response?.statusCode,
            statusText: response?.statusText,
            responseHeaders: response?.headers ?? [:],
            responseBody: response?.body ?? response?.bodyPreview,
            responseBodyPreview: response?.bodyPreview,
            durationMs: durationMs,
            errorMessage: error?.message
        )
    }
}

private struct RequestDTO: Decodable {
    let method: String
    let url: String
    let headers: [String: String]?
    let body: String?
    let bodyPreview: String?
    let requestKind: String?
}

private struct ResponseDTO: Decodable {
    let statusCode: Int?
    let statusText: String?
    let headers: [String: String]?
    let body: String?
    let bodyPreview: String?
}

private struct ErrorDTO: Decodable {
    let message: String?
}

private extension ISO8601DateFormatter {
    static let rnvFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let rnvBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
