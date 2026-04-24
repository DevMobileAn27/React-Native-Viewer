import AppKit
import SwiftUI

enum JsonGraphNodeKind: String, Equatable, Sendable {
    case object
    case array
    case string
    case number
    case boolean
    case null

    nonisolated var title: String {
        switch self {
        case .object:
            return "Object"
        case .array:
            return "Array"
        case .string:
            return "String"
        case .number:
            return "Number"
        case .boolean:
            return "Boolean"
        case .null:
            return "Null"
        }
    }
}

struct JsonGraphNode: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let edgeLabel: String?
    let kind: JsonGraphNodeKind
    let preview: String
    let children: [JsonGraphNode]

    nonisolated init(
        path: String,
        edgeLabel: String?,
        kind: JsonGraphNodeKind,
        preview: String,
        children: [JsonGraphNode] = []
    ) {
        self.id = path
        self.path = path
        self.edgeLabel = edgeLabel
        self.kind = kind
        self.preview = preview
        self.children = children
    }
}

struct JsonGraphDocument: Equatable, Sendable {
    let root: JsonGraphNode
    let nodeCount: Int
}

enum JsonGraphBuildError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case invalidJSON(String)
    case nodeLimitExceeded(limit: Int)
    case inputTooLarge(maxCharacters: Int)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Please paste a JSON value before rendering."
        case .invalidJSON(let message):
            return message
        case .nodeLimitExceeded(let limit):
            return "The graph is too large to render safely. Limit: \(limit) nodes."
        case .inputTooLarge(let maxCharacters):
            return "The JSON input is too large. Maximum supported size: \(maxCharacters) characters."
        }
    }
}

struct JsonGraphLayoutNode: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let edgeLabel: String?
    let kind: JsonGraphNodeKind
    let preview: String
    let depth: Int
    let frame: CGRect
}

struct JsonGraphLayoutEdge: Identifiable, Equatable, Sendable {
    let id: String
    let fromID: String
    let toID: String
    let fromPoint: CGPoint
    let toPoint: CGPoint
    let label: String
}

struct JsonGraphLayoutDocument: Equatable, Sendable {
    let nodes: [JsonGraphLayoutNode]
    let edges: [JsonGraphLayoutEdge]
    let contentSize: CGSize

    nonisolated func scaled(by scale: CGFloat) -> JsonGraphLayoutDocument {
        JsonGraphLayoutDocument(
            nodes: nodes.map { node in
                JsonGraphLayoutNode(
                    id: node.id,
                    path: node.path,
                    edgeLabel: node.edgeLabel,
                    kind: node.kind,
                    preview: node.preview,
                    depth: node.depth,
                    frame: node.frame.scaled(by: scale)
                )
            },
            edges: edges.map { edge in
                JsonGraphLayoutEdge(
                    id: edge.id,
                    fromID: edge.fromID,
                    toID: edge.toID,
                    fromPoint: edge.fromPoint.scaled(by: scale),
                    toPoint: edge.toPoint.scaled(by: scale),
                    label: edge.label
                )
            },
            contentSize: contentSize.scaled(by: scale)
        )
    }
}

struct JsonGraphRenderedGraph: Equatable, Sendable {
    let document: JsonGraphDocument
    let layout: JsonGraphLayoutDocument
}

private extension CGPoint {
    nonisolated func scaled(by scale: CGFloat) -> CGPoint {
        CGPoint(x: x * scale, y: y * scale)
    }
}

private extension CGSize {
    nonisolated func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}

private extension CGRect {
    nonisolated func scaled(by scale: CGFloat) -> CGRect {
        CGRect(
            x: origin.x * scale,
            y: origin.y * scale,
            width: size.width * scale,
            height: size.height * scale
        )
    }
}

struct JsonGraphSelectionValueEntry: Equatable, Sendable {
    let label: String
    let renderedValue: String
    let expandableNodeID: String?
}

enum JsonGraphSelectionValueContent: Equatable, Sendable {
    case scalar(String)
    case structured(
        openingToken: String,
        closingToken: String,
        entries: [JsonGraphSelectionValueEntry]
    )
}

private struct JsonGraphNodeTrail: Equatable, Sendable {
    let node: JsonGraphNode
    let ancestors: [JsonGraphNode]

    static func find(nodeID: String, in root: JsonGraphNode) -> JsonGraphNodeTrail? {
        find(nodeID: nodeID, current: root, ancestors: [])
    }

    private static func find(nodeID: String, current: JsonGraphNode, ancestors: [JsonGraphNode]) -> JsonGraphNodeTrail? {
        if current.id == nodeID {
            return JsonGraphNodeTrail(node: current, ancestors: ancestors)
        }

        for child in current.children {
            if let match = find(nodeID: nodeID, current: child, ancestors: ancestors + [current]) {
                return match
            }
        }

        return nil
    }
}

struct JsonGraphSelectionDetail: Equatable, Sendable {
    let id: String
    let propertyName: String
    let dataType: String
    let valueContent: JsonGraphSelectionValueContent
    let simpleGraph: String

    nonisolated init(node: JsonGraphNode, ancestors: [JsonGraphNode]) {
        self.id = node.id
        self.propertyName = Self.displayName(for: node)
        self.dataType = node.kind.title
        self.valueContent = Self.valueContent(for: node)
        self.simpleGraph = Self.simpleGraph(for: ancestors + [node])
    }

    private nonisolated static func displayName(for node: JsonGraphNode) -> String {
        if node.path == "$" {
            return "Root"
        }

        if let edgeLabel = node.edgeLabel, !edgeLabel.isEmpty {
            return edgeLabel
        }

        return node.path
    }

    private nonisolated static func simpleGraph(for nodes: [JsonGraphNode]) -> String {
        nodes.map(displayName(for:)).joined(separator: " -> ")
    }

    private nonisolated static func valueContent(for node: JsonGraphNode) -> JsonGraphSelectionValueContent {
        switch node.kind {
        case .object:
            return .structured(
                openingToken: "{",
                closingToken: "}",
                entries: node.children.map { child in
                    JsonGraphSelectionValueEntry(
                        label: displayName(for: child),
                        renderedValue: structuredPreviewValue(for: child),
                        expandableNodeID: child.kind == .object || child.kind == .array ? child.id : nil
                    )
                }
            )
        case .array:
            return .structured(
                openingToken: "[",
                closingToken: "]",
                entries: node.children.map { child in
                    JsonGraphSelectionValueEntry(
                        label: displayName(for: child),
                        renderedValue: structuredPreviewValue(for: child),
                        expandableNodeID: child.kind == .object || child.kind == .array ? child.id : nil
                    )
                }
            )
        default:
            return .scalar(node.preview)
        }
    }

    private nonisolated static func structuredPreviewValue(for node: JsonGraphNode) -> String {
        switch node.kind {
        case .object:
            return "{...}"
        case .array:
            return "[...]"
        default:
            return node.preview
        }
    }
}

enum JsonGraphRenderState: Equatable {
    case idle
    case loading
    case rendered(JsonGraphRenderedGraph)
    case failed(String)
}

enum JsonGraphPanMath {
    nonisolated static func nextOrigin(
        currentOrigin: CGPoint,
        translation: CGSize,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        let maxX = max(contentSize.width - viewportSize.width, 0)
        let maxY = max(contentSize.height - viewportSize.height, 0)

        let x = min(max(currentOrigin.x - translation.width, 0), maxX)
        let y = min(max(currentOrigin.y + translation.height, 0), maxY)
        return CGPoint(x: x, y: y)
    }
}

enum JsonGraphPanGestureMath {
    nonisolated static func translation(
        previousWindowLocation: CGPoint,
        currentWindowLocation: CGPoint
    ) -> CGSize {
        CGSize(
            width: currentWindowLocation.x - previousWindowLocation.x,
            height: currentWindowLocation.y - previousWindowLocation.y
        )
    }
}

enum JsonGraphZoomMath {
    nonisolated static let minimumScale: CGFloat = 0.35
    nonisolated static let maximumScale: CGFloat = 1.8
    nonisolated static let scrollStep: CGFloat = 0.04

    nonisolated static func nextScale(
        currentScale: CGFloat,
        scrollDeltaY: CGFloat,
        isControlPressed: Bool
    ) -> CGFloat? {
        guard isControlPressed, scrollDeltaY != 0 else {
            return nil
        }

        let proposedScale = currentScale + (scrollDeltaY * scrollStep)
        return min(max(proposedScale, minimumScale), maximumScale)
    }
}

enum JsonGraphZoomAnchorMath {
    nonisolated static func nextOrigin(
        currentOrigin: CGPoint,
        viewportPoint: CGPoint,
        currentScale: CGFloat,
        nextScale: CGFloat,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        guard currentScale > 0, nextScale > 0 else {
            return clamped(origin: currentOrigin, contentSize: contentSize, viewportSize: viewportSize)
        }

        let ratio = nextScale / currentScale
        let proposedOrigin = CGPoint(
            x: ((currentOrigin.x + viewportPoint.x) * ratio) - viewportPoint.x,
            y: ((currentOrigin.y + viewportPoint.y) * ratio) - viewportPoint.y
        )
        return clamped(origin: proposedOrigin, contentSize: contentSize, viewportSize: viewportSize)
    }

    private nonisolated static func clamped(
        origin: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        let maxX = max(contentSize.width - viewportSize.width, 0)
        let maxY = max(contentSize.height - viewportSize.height, 0)
        return CGPoint(
            x: min(max(origin.x, 0), maxX),
            y: min(max(origin.y, 0), maxY)
        )
    }
}

enum JsonGraphBuilder {
    nonisolated static let defaultNodeLimit = 250
    nonisolated static let defaultInputCharacterLimit = 120_000

    nonisolated static func build(
        from input: String,
        nodeLimit: Int = defaultNodeLimit,
        inputCharacterLimit: Int = defaultInputCharacterLimit
    ) throws -> JsonGraphDocument {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw JsonGraphBuildError.emptyInput
        }

        guard trimmedInput.count <= inputCharacterLimit else {
            throw JsonGraphBuildError.inputTooLarge(maxCharacters: inputCharacterLimit)
        }

        let data = Data(trimmedInput.utf8)
        let jsonValue: Any

        do {
            jsonValue = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw JsonGraphBuildError.invalidJSON("The data is not in the correct format.")
        }

        var nodeCount = 0
        let rootNode = try buildNode(
            value: jsonValue,
            path: "$",
            edgeLabel: nil,
            nodeCount: &nodeCount,
            nodeLimit: nodeLimit
        )

        return JsonGraphDocument(root: rootNode, nodeCount: nodeCount)
    }

    private nonisolated static func buildNode(
        value: Any,
        path: String,
        edgeLabel: String?,
        nodeCount: inout Int,
        nodeLimit: Int
    ) throws -> JsonGraphNode {
        nodeCount += 1
        guard nodeCount <= nodeLimit else {
            throw JsonGraphBuildError.nodeLimitExceeded(limit: nodeLimit)
        }

        if let dictionary = value as? [String: Any] {
            let keys = dictionary.keys.sorted()
            let children = try keys.map { key in
                try buildNode(
                    value: dictionary[key] as Any,
                    path: childPath(parentPath: path, edgeLabel: key),
                    edgeLabel: key,
                    nodeCount: &nodeCount,
                    nodeLimit: nodeLimit
                )
            }

            return JsonGraphNode(
                path: path,
                edgeLabel: edgeLabel,
                kind: .object,
                preview: "\(dictionary.count) key(s)",
                children: children
            )
        }

        if let array = value as? [Any] {
            let children = try array.enumerated().map { index, childValue in
                let edgeLabel = "[\(index)]"
                return try buildNode(
                    value: childValue,
                    path: childPath(parentPath: path, edgeLabel: edgeLabel),
                    edgeLabel: edgeLabel,
                    nodeCount: &nodeCount,
                    nodeLimit: nodeLimit
                )
            }

            return JsonGraphNode(
                path: path,
                edgeLabel: edgeLabel,
                kind: .array,
                preview: "\(array.count) item(s)",
                children: children
            )
        }

        if value is NSNull {
            return JsonGraphNode(
                path: path,
                edgeLabel: edgeLabel,
                kind: .null,
                preview: "null"
            )
        }

        if let stringValue = value as? String {
            return JsonGraphNode(
                path: path,
                edgeLabel: edgeLabel,
                kind: .string,
                preview: "\"\(truncatePreview(stringValue))\""
            )
        }

        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                return JsonGraphNode(
                    path: path,
                    edgeLabel: edgeLabel,
                    kind: .boolean,
                    preview: numberValue.boolValue ? "true" : "false"
                )
            }

            return JsonGraphNode(
                path: path,
                edgeLabel: edgeLabel,
                kind: .number,
                preview: numberValue.stringValue
            )
        }

        return JsonGraphNode(
            path: path,
            edgeLabel: edgeLabel,
            kind: .string,
            preview: "\"\(truncatePreview(String(describing: value)))\""
        )
    }

    private nonisolated static func childPath(parentPath: String, edgeLabel: String) -> String {
        if edgeLabel.hasPrefix("[") {
            return "\(parentPath)\(edgeLabel)"
        }

        return "\(parentPath).\(edgeLabel)"
    }

    private nonisolated static func truncatePreview(_ value: String, limit: Int = 64) -> String {
        guard value.count > limit else {
            return value
        }

        return value.prefix(limit - 1) + "…"
    }
}

enum JsonGraphLayoutBuilder {
    nonisolated static func build(from document: JsonGraphDocument) -> JsonGraphLayoutDocument {
        RNVJsonGraphLayoutEngine.build(from: document)
    }
}

@MainActor
final class JsonGraphWorkspaceViewModel: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var renderState: JsonGraphRenderState = .idle
    @Published private(set) var selectedNodeID: String?

    private var renderTask: Task<Void, Never>?

    var renderedDocument: JsonGraphDocument? {
        guard case .rendered(let graph) = renderState else {
            return nil
        }

        return graph.document
    }

    var renderedGraph: JsonGraphRenderedGraph? {
        guard case .rendered(let graph) = renderState else {
            return nil
        }

        return graph
    }

    var selectedNodeDetail: JsonGraphSelectionDetail? {
        guard
            let selectedNodeID,
            let root = renderedGraph?.document.root,
            let trail = JsonGraphNodeTrail.find(nodeID: selectedNodeID, in: root)
        else {
            return nil
        }

        return JsonGraphSelectionDetail(node: trail.node, ancestors: trail.ancestors)
    }

    func render(
        nodeLimit: Int = JsonGraphBuilder.defaultNodeLimit,
        inputCharacterLimit: Int = JsonGraphBuilder.defaultInputCharacterLimit
    ) {
        let snapshot = inputText
        renderTask?.cancel()
        selectedNodeID = nil
        renderState = .loading

        renderTask = Task(priority: .userInitiated) { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let document = try JsonGraphBuilder.build(
                    from: snapshot,
                    nodeLimit: nodeLimit,
                    inputCharacterLimit: inputCharacterLimit
                )
                let layout = JsonGraphLayoutBuilder.build(from: document)
                return JsonGraphRenderedGraph(document: document, layout: layout)
            }.result

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                switch result {
                case .success(let document):
                    self.renderState = .rendered(document)
                    self.pruneSelectionIfNeeded()
                case .failure(let error as JsonGraphBuildError):
                    self.renderState = .failed(error.errorDescription ?? "Unable to render the JSON graph.")
                    self.selectedNodeID = nil
                case .failure(let error):
                    self.renderState = .failed(error.localizedDescription)
                    self.selectedNodeID = nil
                }
            }
        }
    }

    func useRequestBody(_ body: String?) {
        guard let body = normalizedBody(body) else {
            return
        }

        renderTask?.cancel()
        selectedNodeID = nil
        inputText = body
        renderState = .idle
    }

    func useResponseBody(_ body: String?) {
        guard let body = normalizedBody(body) else {
            return
        }

        renderTask?.cancel()
        selectedNodeID = nil
        inputText = body
        renderState = .idle
    }

    func reset() {
        renderTask?.cancel()
        inputText = ""
        selectedNodeID = nil
        renderState = .idle
    }

    func toggleSelection(nodeID: String) {
        selectedNodeID = selectedNodeID == nodeID ? nil : nodeID
        pruneSelectionIfNeeded()
    }

    func selectNode(nodeID: String) {
        selectedNodeID = nodeID
        pruneSelectionIfNeeded()
    }

    func clearSelection() {
        selectedNodeID = nil
    }

    func pruneSelection(validNodeIDs: [String]) {
        guard let selectedNodeID, !validNodeIDs.contains(selectedNodeID) else {
            return
        }

        self.selectedNodeID = nil
    }

    deinit {
        renderTask?.cancel()
    }

    private func pruneSelectionIfNeeded() {
        guard let selectedNodeID else {
            return
        }
        guard
            let root = renderedGraph?.document.root,
            JsonGraphNodeTrail.find(nodeID: selectedNodeID, in: root) != nil
        else {
            self.selectedNodeID = nil
            return
        }
    }

    private func normalizedBody(_ body: String?) -> String? {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return nil
        }

        return body
    }
}

struct JsonGraphWorkspaceView: View {
    @ObservedObject var viewModel: JsonGraphWorkspaceViewModel
    let palette: FlipperPalette
    let language: AppLanguage

    @State private var zoomScale: CGFloat = 1

    private var resolvedLanguage: ResolvedAppLanguage {
        language.resolvedLanguage()
    }

    private func localized(_ english: String, _ vietnamese: String) -> String {
        switch resolvedLanguage {
        case .english:
            return english
        case .vietnamese:
            return vietnamese
        }
    }

    private var renderTitle: String {
        localized("Render", "Dựng")
    }

    private var resetTitle: String {
        localized("Reset", "Làm mới")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            inputPanel
                .frame(width: 360)

            graphPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(palette.backgroundDefault)
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $viewModel.inputText)
                .font(FlipperTypography.code)
                .foregroundStyle(palette.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 280)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button(renderTitle) {
                    viewModel.render()
                }
                .buttonStyle(FlipperPrimaryButtonStyle(palette: palette))

                Button(resetTitle) {
                    viewModel.reset()
                    zoomScale = 1
                }
                .buttonStyle(FlipperSecondaryButtonStyle(palette: palette))
            }

            Text(localized("Node limit: \(JsonGraphBuilder.defaultNodeLimit)", "Giới hạn node: \(JsonGraphBuilder.defaultNodeLimit)"))
                .font(FlipperTypography.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private var graphPanel: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.border, lineWidth: 1)

            graphPanelContent
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var graphPanelContent: some View {
        switch viewModel.renderState {
        case .idle:
            jsonGraphEmptyState(
                title: localized("No JSON graph yet", "Chưa có đồ thị JSON"),
                message: localized(
                    "Paste JSON on the left or import a network body, then press Render.",
                    "Dán JSON ở khung bên trái hoặc lấy từ network body, rồi nhấn Dựng."
                )
            )
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)

                Text(localized("Rendering graph...", "Đang dựng đồ thị..."))
                    .font(FlipperTypography.body)
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            jsonGraphErrorState(message: message)
        case .rendered(let graph):
            GeometryReader { geometry in
                RNVJsonGraphSceneScrollView(
                    layout: graph.layout,
                    zoomScale: zoomScale,
                    palette: palette,
                    selectedNodeID: viewModel.selectedNodeID,
                    onZoomRequested: { newScale in
                        zoomScale = newScale
                    },
                    onSelectNode: viewModel.toggleSelection(nodeID:)
                )
                .background(
                    Color.clear
                        .onAppear {
                            applyFitScale(for: graph.layout.contentSize, viewportSize: geometry.size)
                        }
                )
                .onChange(of: graph.layout.contentSize) { _, newSize in
                    applyFitScale(for: newSize, viewportSize: geometry.size)
                }
                .onChange(of: graph.layout.nodes.map(\.id)) { _, ids in
                    viewModel.pruneSelection(validNodeIDs: ids)
                }
            }
        }
    }

    private func applyFitScale(for contentSize: CGSize, viewportSize: CGSize) {
        let viewport = viewportSize
        guard contentSize.width > 0, contentSize.height > 0, viewport.width > 0, viewport.height > 0 else {
            zoomScale = 1
            return
        }

        let horizontalScale = max((viewport.width - 48) / contentSize.width, 0)
        let verticalScale = max((viewport.height - 48) / contentSize.height, 0)
        let fitScale = min(horizontalScale, verticalScale, 1)
        zoomScale = min(max(fitScale, JsonGraphZoomMath.minimumScale), 1)
    }

    private func jsonGraphEmptyState(title: String, message: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(palette.accent)

            Text(title)
                .font(FlipperTypography.title4)
                .foregroundStyle(palette.primaryText)

            Text(message)
                .font(FlipperTypography.body)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func jsonGraphErrorState(message: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color(hex: 0xCF1322))

            Text(localized("Unable to render JSON", "Không thể dựng JSON"))
                .font(FlipperTypography.title4)
                .foregroundStyle(palette.primaryText)

            Text(message)
                .font(FlipperTypography.body)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JsonGraphSelectionDetailContent: View {
    let detail: JsonGraphSelectionDetail
    let palette: FlipperPalette
    let language: AppLanguage
    let onSelectNode: (String) -> Void

    private var resolvedLanguage: ResolvedAppLanguage {
        language.resolvedLanguage()
    }

    private var detailPropertyNameTitle: String {
        resolvedLanguage == .english ? "Property Name" : "Tên thuộc tính"
    }

    private var detailDataTypeTitle: String {
        resolvedLanguage == .english ? "Data Type" : "Loại dữ liệu"
    }

    private var detailValueTitle: String {
        resolvedLanguage == .english ? "Value" : "Giá trị"
    }

    private var detailSimpleGraphTitle: String {
        resolvedLanguage == .english ? "Simple Graph" : "Đồ thị đơn giản"
    }

    private var detailViewMoreTitle: String {
        resolvedLanguage == .english ? "View detail" : "Xem chi tiết"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            jsonGraphSelectionField(title: detailPropertyNameTitle, value: detail.propertyName)
            jsonGraphSelectionField(title: detailDataTypeTitle, value: detail.dataType)
            jsonGraphSelectionValueSection(detail: detail)
            jsonGraphSelectionField(title: detailSimpleGraphTitle, value: detail.simpleGraph)
        }
    }

    @ViewBuilder
    private func jsonGraphSelectionValueSection(detail: JsonGraphSelectionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detailValueTitle)
                .font(FlipperTypography.caption)
                .foregroundStyle(palette.secondaryText)

            switch detail.valueContent {
            case .scalar(let value):
                jsonGraphSelectionCodeBlock {
                    Text(value)
                        .font(FlipperTypography.code)
                        .foregroundStyle(palette.primaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .structured(let openingToken, let closingToken, let entries):
                jsonGraphSelectionCodeBlock {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(openingToken)
                            .font(FlipperTypography.code)
                            .foregroundStyle(palette.primaryText)

                        if entries.isEmpty {
                            Text("  ")
                                .font(FlipperTypography.code)
                                .foregroundStyle(palette.primaryText)
                        } else {
                            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(jsonGraphSelectionValueEntryPrefix(entry))
                                        .font(FlipperTypography.code)
                                        .foregroundStyle(palette.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if let expandableNodeID = entry.expandableNodeID {
                                        Button {
                                            onSelectNode(expandableNodeID)
                                        } label: {
                                            Text(detailViewMoreTitle)
                                                .font(FlipperTypography.code)
                                                .underline()
                                                .foregroundStyle(palette.accent)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if index < entries.count - 1 {
                                        Text(",")
                                            .font(FlipperTypography.code)
                                            .foregroundStyle(palette.primaryText)
                                    }
                                }
                            }
                        }

                        Text(closingToken)
                            .font(FlipperTypography.code)
                            .foregroundStyle(palette.primaryText)
                    }
                }
            }
        }
    }

    private func jsonGraphSelectionValueEntryPrefix(_ entry: JsonGraphSelectionValueEntry) -> String {
        let label = entry.label.hasPrefix("[") ? entry.label : "\"\(entry.label)\""
        return "  \(label): \(entry.renderedValue)"
    }

    private func jsonGraphSelectionCodeBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xFCFCFD))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private func jsonGraphSelectionField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FlipperTypography.caption)
                .foregroundStyle(palette.secondaryText)

            Text(value)
                .font(FlipperTypography.bodyStrong)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct JsonGraphInteractiveScrollView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let zoomScale: CGFloat
    let onZoomRequested: (CGFloat) -> Void
    let content: Content

    init(
        contentSize: CGSize,
        zoomScale: CGFloat,
        onZoomRequested: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.contentSize = contentSize
        self.zoomScale = zoomScale
        self.onZoomRequested = onZoomRequested
        self.content = content()
    }

    func makeNSView(context: Context) -> JsonGraphPanScrollView {
        let scrollView = JsonGraphPanScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = context.coordinator.documentView
        scrollView.currentZoomScale = zoomScale
        scrollView.onZoomRequested = onZoomRequested
        return scrollView
    }

    func updateNSView(_ scrollView: JsonGraphPanScrollView, context: Context) {
        let rootView = AnyView(
            content
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                .padding(24)
        )

        context.coordinator.documentView.update(
            rootView: rootView,
            contentSize: CGSize(width: contentSize.width + 48, height: contentSize.height + 48)
        )
        scrollView.documentView = context.coordinator.documentView
        scrollView.currentZoomScale = zoomScale
        scrollView.onZoomRequested = onZoomRequested
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let documentView = JsonGraphPanDocumentView()
    }
}

private final class JsonGraphPanScrollView: NSScrollView {
    var currentZoomScale: CGFloat = 1
    var onZoomRequested: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if let nextScale = JsonGraphZoomMath.nextScale(
            currentScale: currentZoomScale,
            scrollDeltaY: event.scrollingDeltaY,
            isControlPressed: event.modifierFlags.contains(.control)
        ) {
            onZoomRequested?(nextScale)
            return
        }

        super.scrollWheel(with: event)
    }
}

private final class JsonGraphPanDocumentView: NSView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var lastRightDragWindowLocation: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func update(rootView: AnyView, contentSize: CGSize) {
        hostingView.rootView = rootView
        frame = CGRect(origin: .zero, size: contentSize)
        needsLayout = true
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastRightDragWindowLocation = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard
            let lastRightDragWindowLocation,
            let scrollView = enclosingScrollView
        else {
            return
        }

        let currentWindowLocation = event.locationInWindow
        let translation = JsonGraphPanGestureMath.translation(
            previousWindowLocation: lastRightDragWindowLocation,
            currentWindowLocation: currentWindowLocation
        )

        let clipView = scrollView.contentView
        let nextOrigin = JsonGraphPanMath.nextOrigin(
            currentOrigin: clipView.bounds.origin,
            translation: translation,
            contentSize: frame.size,
            viewportSize: clipView.bounds.size
        )
        clipView.setBoundsOrigin(nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
        self.lastRightDragWindowLocation = currentWindowLocation
    }

    override func rightMouseUp(with event: NSEvent) {
        lastRightDragWindowLocation = nil
    }
}

private struct JsonGraphCanvasView: View {
    let layout: JsonGraphLayoutDocument
    let scale: CGFloat
    let palette: FlipperPalette
    let selectedNodeID: String?
    let onSelectNode: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                JsonGraphEdgeView(
                    edge: edge,
                    scale: scale,
                    palette: palette,
                    isHighlighted: selectedNodeID == edge.fromID || selectedNodeID == edge.toID
                )
            }

            ForEach(layout.nodes) { node in
                JsonGraphNodeCard(
                    node: node,
                    scale: scale,
                    palette: palette,
                    isSelected: selectedNodeID == node.id,
                    onSelect: { onSelectNode(node.id) }
                )
                    .position(
                        x: node.frame.midX,
                        y: node.frame.midY
                    )
            }
        }
    }
}

private struct JsonGraphEdgeView: View {
    let edge: JsonGraphLayoutEdge
    let scale: CGFloat
    let palette: FlipperPalette
    let isHighlighted: Bool

    private var edgeColor: Color {
        isHighlighted ? palette.accent : Color(hex: 0x8C8C8C, opacity: 0.92)
    }

    private var labelBackground: Color {
        isHighlighted ? palette.accentMuted : Color.white
    }

    private var labelForeground: Color {
        isHighlighted ? palette.accent : Color(hex: 0x434343)
    }

    private var labelPosition: CGPoint {
        let midpointX = edge.fromPoint.x + ((edge.toPoint.x - edge.fromPoint.x) * 0.5)
        return CGPoint(x: midpointX, y: edge.fromPoint.y - (14 * scale))
    }

    private var underStrokeWidth: CGFloat {
        max(3.5, 5 * scale)
    }

    private var mainStrokeWidth: CGFloat {
        max(1.8, (isHighlighted ? 2.6 : 2.1) * scale)
    }

    private var anchorDiameter: CGFloat {
        max(7, 8 * scale)
    }

    private var anchorStrokeWidth: CGFloat {
        max(1.2, (isHighlighted ? 2 : 1.5) * scale)
    }

    private var labelHorizontalPadding: CGFloat {
        max(5, 6 * scale)
    }

    private var labelVerticalPadding: CGFloat {
        max(2.5, 3 * scale)
    }

    private var labelFont: Font {
        .system(size: max(9, 10 * scale), weight: .semibold)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            JsonGraphEdgeShape(edge: edge)
                .stroke(Color.white, style: StrokeStyle(lineWidth: underStrokeWidth, lineCap: .round, lineJoin: .round))

            JsonGraphEdgeShape(edge: edge)
                .stroke(edgeColor, style: StrokeStyle(lineWidth: mainStrokeWidth, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(Color.white)
                .overlay(
                    Circle()
                        .stroke(edgeColor, lineWidth: anchorStrokeWidth)
                )
                .frame(width: anchorDiameter, height: anchorDiameter)
                .position(edge.fromPoint)

            Circle()
                .fill(Color.white)
                .overlay(
                    Circle()
                        .stroke(edgeColor, lineWidth: anchorStrokeWidth)
                )
                .frame(width: anchorDiameter, height: anchorDiameter)
                .position(edge.toPoint)

            Text(edge.label)
                .font(labelFont)
                .foregroundStyle(labelForeground)
                .padding(.horizontal, labelHorizontalPadding)
                .padding(.vertical, labelVerticalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(labelBackground)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isHighlighted ? palette.accent : palette.border, lineWidth: 1)
                )
                .position(labelPosition)
        }
    }
}

private struct JsonGraphNodeCard: View {
    let node: JsonGraphLayoutNode
    let scale: CGFloat
    let palette: FlipperPalette
    let isSelected: Bool
    let onSelect: () -> Void

    private var badgeBackgroundColor: Color {
        switch node.kind {
        case .object:
            return Color(hex: 0xE6F4FF)
        case .array:
            return Color(hex: 0xF9F0FF)
        case .string:
            return Color(hex: 0xF6FFED)
        case .number:
            return Color(hex: 0xFFF7E6)
        case .boolean:
            return Color(hex: 0xE6FFFB)
        case .null:
            return Color(hex: 0xF5F5F5)
        }
    }

    private var badgeForegroundColor: Color {
        switch node.kind {
        case .object:
            return Color(hex: 0x0958D9)
        case .array:
            return Color(hex: 0x722ED1)
        case .string:
            return Color(hex: 0x389E0D)
        case .number:
            return Color(hex: 0xD46B08)
        case .boolean:
            return Color(hex: 0x08979C)
        case .null:
            return Color(hex: 0x595959)
        }
    }

    private var cardCornerRadius: CGFloat {
        max(10, 12 * scale)
    }

    private var contentPadding: CGFloat {
        max(10, 12 * scale)
    }

    private var contentSpacing: CGFloat {
        max(6, 8 * scale)
    }

    private var badgeHorizontalPadding: CGFloat {
        max(6, 8 * scale)
    }

    private var badgeVerticalPadding: CGFloat {
        max(3, 4 * scale)
    }

    private var badgeFont: Font {
        .system(size: max(9, 10 * scale), weight: .semibold)
    }

    private var previewFont: Font {
        .system(size: max(12, 15 * scale), weight: .semibold)
    }

    private var pathFont: Font {
        .system(size: max(10, 12 * scale), weight: .regular)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                Text(node.kind.title.uppercased())
                    .font(badgeFont)
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, badgeHorizontalPadding)
                    .padding(.vertical, badgeVerticalPadding)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badgeBackgroundColor)
                    )

                Text(node.preview)
                    .font(previewFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Text(node.path)
                    .font(pathFont)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(contentPadding)
            .frame(width: node.frame.width, height: node.frame.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(isSelected ? Color(hex: 0xF3E8FF) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(isSelected ? palette.accent : palette.border, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct JsonGraphEdgeShape: Shape {
    let edge: JsonGraphLayoutEdge

    func path(in rect: CGRect) -> Path {
        let start = edge.fromPoint
        let end = edge.toPoint
        let midpointX = start.x + ((end.x - start.x) * 0.5)

        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: midpointX, y: start.y))
        path.addLine(to: CGPoint(x: midpointX, y: end.y))
        path.addLine(to: end)
        return path
    }
}
