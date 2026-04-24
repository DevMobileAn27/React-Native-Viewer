import Foundation

enum NetworkRequestEvent {
    case requestWillBeSent(
        requestId: String,
        timestamp: Date,
        method: String,
        url: String,
        headers: [String: String],
        postData: String?,
        resourceType: String?
    )
    case responseReceived(
        requestId: String,
        timestamp: Date,
        statusCode: Int?,
        statusText: String?,
        mimeType: String?,
        headers: [String: String],
        resourceType: String?
    )
    case loadingFinished(
        requestId: String,
        timestamp: Date,
        encodedDataLength: Int64?
    )
    case loadingFailed(
        requestId: String,
        timestamp: Date,
        errorText: String?
    )
}

struct DebuggerCommandResponse {
    let id: Int
    let errorMessage: String?
}

enum DevtoolsConsoleEventParser {
    static func parseNotification(_ data: Data) -> ConsoleLogEntry? {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = rootObject["method"] as? String,
            let params = rootObject["params"] as? [String: Any]
        else {
            return nil
        }

        switch method {
        case "Runtime.consoleAPICalled":
            return parseConsoleAPICalled(params)
        case "Log.entryAdded":
            return parseLogEntryAdded(params)
        case "Console.messageAdded":
            return parseConsoleMessageAdded(params)
        case "Runtime.exceptionThrown":
            return parseExceptionThrown(params)
        default:
            return nil
        }
    }

    static func parseNetworkNotification(_ data: Data) -> NetworkRequestEvent? {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = rootObject["method"] as? String,
            let params = rootObject["params"] as? [String: Any]
        else {
            return nil
        }

        switch method {
        case "Network.requestWillBeSent":
            return parseRequestWillBeSent(params)
        case "Network.responseReceived":
            return parseResponseReceived(params)
        case "Network.loadingFinished":
            return parseLoadingFinished(params)
        case "Network.loadingFailed":
            return parseLoadingFailed(params)
        default:
            return nil
        }
    }

    static func parseCommandResponse(_ data: Data) -> DebuggerCommandResponse? {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let identifier = integerValue(from: rootObject["id"])
        else {
            return nil
        }

        if let error = rootObject["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.nonEmpty ?? "Unknown error"
            if let details = (error["data"] as? String)?.nonEmpty {
                return DebuggerCommandResponse(id: identifier, errorMessage: "\(message): \(details)")
            }

            return DebuggerCommandResponse(id: identifier, errorMessage: message)
        }

        if rootObject["result"] != nil {
            return DebuggerCommandResponse(id: identifier, errorMessage: nil)
        }

        return nil
    }

    private static func parseConsoleAPICalled(_ params: [String: Any]) -> ConsoleLogEntry? {
        let level = ConsoleLogLevel(runtimeType: params["type"] as? String)
        let timestamp = date(fromTimestampValue: params["timestamp"])
        let args = params["args"] as? [[String: Any]] ?? []
        let message = args
            .map(renderRemoteObject)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nonEmpty ?? AppStrings.text(.consoleMessage)

        return ConsoleLogEntry(
            timestamp: timestamp,
            level: level,
            message: message,
            source: parseSource(from: params) ?? AppStrings.text(.consoleSource)
        )
    }

    private static func parseLogEntryAdded(_ params: [String: Any]) -> ConsoleLogEntry? {
        guard let entry = params["entry"] as? [String: Any] else {
            return nil
        }

        let level = ConsoleLogLevel(logEntryLevel: entry["level"] as? String)
        let message = (entry["text"] as? String)?.nonEmpty
            ?? (entry["args"] as? [[String: Any]])?
                .map(renderRemoteObject)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .nonEmpty
            ?? AppStrings.text(.consoleEntry)

        let source = (entry["url"] as? String)?.nonEmpty
            ?? parseSource(from: entry)
            ?? (entry["source"] as? String)?.nonEmpty
            ?? AppStrings.text(.consoleSource)

        return ConsoleLogEntry(
            timestamp: date(fromTimestampValue: entry["timestamp"]),
            level: level,
            message: message,
            source: source
        )
    }

    private static func parseConsoleMessageAdded(_ params: [String: Any]) -> ConsoleLogEntry? {
        guard let message = params["message"] as? [String: Any] else {
            return nil
        }

        let source = (message["url"] as? String)?.nonEmpty
            ?? (message["source"] as? String)?.nonEmpty
            ?? AppStrings.text(.consoleSource)

        return ConsoleLogEntry(
            timestamp: date(fromTimestampValue: message["timestamp"]),
            level: ConsoleLogLevel(logEntryLevel: message["level"] as? String),
            message: (message["text"] as? String)?.nonEmpty ?? AppStrings.text(.consoleMessage),
            source: source
        )
    }

    private static func parseExceptionThrown(_ params: [String: Any]) -> ConsoleLogEntry? {
        guard let details = params["exceptionDetails"] as? [String: Any] else {
            return nil
        }

        let message = (details["text"] as? String)?.nonEmpty
            ?? ((details["exception"] as? [String: Any]).flatMap { renderRemoteObject($0).nonEmpty })
            ?? AppStrings.text(.javaScriptException)

        let source = (details["url"] as? String)?.nonEmpty
            ?? parseSource(from: details)
            ?? AppStrings.text(.exceptionSource)

        return ConsoleLogEntry(
            timestamp: date(fromTimestampValue: params["timestamp"] ?? details["timestamp"]),
            level: .error,
            message: message,
            source: source
        )
    }

    private static func parseRequestWillBeSent(_ params: [String: Any]) -> NetworkRequestEvent? {
        guard
            let requestId = params["requestId"] as? String,
            let request = params["request"] as? [String: Any],
            let method = (request["method"] as? String)?.nonEmpty,
            let url = (request["url"] as? String)?.nonEmpty
        else {
            return nil
        }

        return .requestWillBeSent(
            requestId: requestId,
            timestamp: date(fromTimestampValue: params["timestamp"]),
            method: method,
            url: url,
            headers: stringifyHeaders(request["headers"]),
            postData: (request["postData"] as? String)?.nonEmpty,
            resourceType: (params["type"] as? String)?.nonEmpty
        )
    }

    private static func parseResponseReceived(_ params: [String: Any]) -> NetworkRequestEvent? {
        guard
            let requestId = params["requestId"] as? String,
            let response = params["response"] as? [String: Any]
        else {
            return nil
        }

        return .responseReceived(
            requestId: requestId,
            timestamp: date(fromTimestampValue: params["timestamp"]),
            statusCode: integerValue(from: response["status"]),
            statusText: (response["statusText"] as? String)?.nonEmpty,
            mimeType: (response["mimeType"] as? String)?.nonEmpty,
            headers: stringifyHeaders(response["headers"]),
            resourceType: (params["type"] as? String)?.nonEmpty
        )
    }

    private static func parseLoadingFinished(_ params: [String: Any]) -> NetworkRequestEvent? {
        guard let requestId = params["requestId"] as? String else {
            return nil
        }

        return .loadingFinished(
            requestId: requestId,
            timestamp: date(fromTimestampValue: params["timestamp"]),
            encodedDataLength: integer64Value(from: params["encodedDataLength"])
        )
    }

    private static func parseLoadingFailed(_ params: [String: Any]) -> NetworkRequestEvent? {
        guard let requestId = params["requestId"] as? String else {
            return nil
        }

        return .loadingFailed(
            requestId: requestId,
            timestamp: date(fromTimestampValue: params["timestamp"]),
            errorText: (params["errorText"] as? String)?.nonEmpty
        )
    }

    private static func parseSource(from payload: [String: Any]) -> String? {
        guard
            let stackTrace = payload["stackTrace"] as? [String: Any],
            let callFrames = stackTrace["callFrames"] as? [[String: Any]],
            let firstFrame = callFrames.first
        else {
            return nil
        }

        return (firstFrame["url"] as? String)?.nonEmpty
            ?? (firstFrame["functionName"] as? String)?.nonEmpty
    }

    private static func date(fromTimestampValue value: Any?, now: Date = .now) -> Date {
        guard let rawTimestamp = rawTimestamp(from: value) else {
            return now
        }

        let epochSecondsCandidate = Date(timeIntervalSince1970: rawTimestamp)
        let epochMillisecondsCandidate = Date(timeIntervalSince1970: rawTimestamp / 1_000)
        let plausibleDates = [
            epochSecondsCandidate,
            epochMillisecondsCandidate
        ].filter { candidate in
            abs(candidate.timeIntervalSince(now)) <= 60 * 60 * 24 * 365 * 5
        }

        if let bestCandidate = plausibleDates.min(by: { lhs, rhs in
            abs(lhs.timeIntervalSince(now)) < abs(rhs.timeIntervalSince(now))
        }) {
            return bestCandidate
        }

        return now
    }

    private static func rawTimestamp(from value: Any?) -> Double? {
        if let timestamp = value as? NSNumber {
            return timestamp.doubleValue
        }

        if let timestamp = value as? Double {
            return timestamp
        }

        return nil
    }

    private static func integerValue(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }

        if let number = value as? Int {
            return number
        }

        if let number = value as? Double {
            return Int(number)
        }

        return nil
    }

    private static func integer64Value(from value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }

        if let number = value as? Int64 {
            return number
        }

        if let number = value as? Int {
            return Int64(number)
        }

        if let number = value as? Double {
            return Int64(number)
        }

        return nil
    }

    private static func stringifyHeaders(_ rawHeaders: Any?) -> [String: String] {
        guard let headers = rawHeaders as? [String: Any] else {
            return [:]
        }

        return headers.reduce(into: [:]) { partialResult, item in
            partialResult[item.key] = stringify(item.value)
        }
    }

    private static func renderRemoteObject(_ object: [String: Any]) -> String {
        if let value = object["value"] {
            return stringify(value)
        }

        if let unserializableValue = object["unserializableValue"] as? String, !unserializableValue.isEmpty {
            return unserializableValue
        }

        if let objectPlaceholder = renderObjectPlaceholder(object), !objectPlaceholder.isEmpty {
            return objectPlaceholder
        }

        if let description = object["description"] as? String, !description.isEmpty {
            return description
        }

        if let type = object["type"] as? String, !type.isEmpty {
            return type
        }

        return ""
    }

    private static func renderObjectPlaceholder(_ object: [String: Any]) -> String? {
        guard (object["type"] as? String) == "object" else {
            return nil
        }

        if let subtype = object["subtype"] as? String {
            switch subtype {
            case "null":
                return "null"
            case "array", "typedarray":
                return "[...]"
            case "map", "set", "weakmap", "weakset":
                return "\(subtype)(...)"
            default:
                break
            }
        }

        if let description = object["description"] as? String, !description.isEmpty, description != "Object" {
            return description
        }

        return "{...}"
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            if let data = try? JSONSerialization.data(withJSONObject: array),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        case let dictionary as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: dictionary),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        default:
            break
        }

        return String(describing: value)
    }
}
