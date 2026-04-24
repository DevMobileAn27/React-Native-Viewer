import AppKit
import SwiftUI

enum RNVJsonGraphLayoutEngine {
    nonisolated static func build(from document: JsonGraphDocument) -> JsonGraphLayoutDocument {
        var nodeSizes: [String: CGSize] = [:]
        var columnWidths: [Int: CGFloat] = [:]
        var columnGapWidths: [Int: CGFloat] = [:]
        collectMeasurements(
            node: document.root,
            depth: 0,
            nodeSizes: &nodeSizes,
            columnWidths: &columnWidths,
            columnGapWidths: &columnGapWidths
        )

        var subtreeHeights: [String: CGFloat] = [:]
        measureSubtree(node: document.root, nodeSizes: nodeSizes, into: &subtreeHeights)

        var nodes: [JsonGraphLayoutNode] = []
        var edges: [JsonGraphLayoutEdge] = []
        _ = layoutNode(
            node: document.root,
            depth: 0,
            topY: RNVJsonGraphSceneMetrics.canvasPadding.height,
            nodeSizes: nodeSizes,
            columnWidths: columnWidths,
            columnGapWidths: columnGapWidths,
            subtreeHeights: subtreeHeights,
            nodes: &nodes,
            edges: &edges
        )

        let nodeMaxX = nodes.map(\.frame.maxX).max() ?? 0
        let nodeMaxY = nodes.map(\.frame.maxY).max() ?? 0
        let edgeLabelBounds = edges.map(RNVJsonGraphSceneMetrics.edgeLabelFrame(for:))
        let edgeMaxX = edgeLabelBounds.map(\.maxX).max() ?? 0
        let edgeMaxY = edgeLabelBounds.map(\.maxY).max() ?? 0
        let edgeMinY = edgeLabelBounds.map(\.minY).min() ?? 0
        let topInset = max(0, -edgeMinY)

        if topInset > 0 {
            nodes = nodes.map { node in
                JsonGraphLayoutNode(
                    id: node.id,
                    path: node.path,
                    edgeLabel: node.edgeLabel,
                    kind: node.kind,
                    preview: node.preview,
                    depth: node.depth,
                    frame: node.frame.offsetBy(dx: 0, dy: topInset)
                )
            }
            edges = edges.map { edge in
                JsonGraphLayoutEdge(
                    id: edge.id,
                    fromID: edge.fromID,
                    toID: edge.toID,
                    fromPoint: CGPoint(x: edge.fromPoint.x, y: edge.fromPoint.y + topInset),
                    toPoint: CGPoint(x: edge.toPoint.x, y: edge.toPoint.y + topInset),
                    label: edge.label
                )
            }
        }

        return JsonGraphLayoutDocument(
            nodes: nodes,
            edges: edges,
            contentSize: CGSize(
                width: max(nodeMaxX, edgeMaxX) + RNVJsonGraphSceneMetrics.canvasPadding.width,
                height: max(nodeMaxY + topInset, edgeMaxY + topInset) + RNVJsonGraphSceneMetrics.canvasPadding.height
            )
        )
    }

    private nonisolated static func collectMeasurements(
        node: JsonGraphNode,
        depth: Int,
        nodeSizes: inout [String: CGSize],
        columnWidths: inout [Int: CGFloat],
        columnGapWidths: inout [Int: CGFloat]
    ) {
        let size = RNVJsonGraphSceneMetrics.nodeSize(for: node)
        nodeSizes[node.id] = size
        columnWidths[depth] = max(columnWidths[depth] ?? 0, size.width)

        for child in node.children {
            let gapWidth = RNVJsonGraphSceneMetrics.minimumGapWidth(
                forEdgeLabel: child.edgeLabel ?? child.path
            )
            columnGapWidths[depth] = max(columnGapWidths[depth] ?? RNVJsonGraphSceneMetrics.horizontalGap, gapWidth)
            collectMeasurements(
                node: child,
                depth: depth + 1,
                nodeSizes: &nodeSizes,
                columnWidths: &columnWidths,
                columnGapWidths: &columnGapWidths
            )
        }
    }

    @discardableResult
    private nonisolated static func measureSubtree(
        node: JsonGraphNode,
        nodeSizes: [String: CGSize],
        into heights: inout [String: CGFloat]
    ) -> CGFloat {
        let nodeHeight = nodeSizes[node.id]?.height ?? RNVJsonGraphSceneMetrics.minimumNodeHeight
        guard !node.children.isEmpty else {
            heights[node.id] = nodeHeight
            return nodeHeight
        }

        let childrenHeight = node.children.enumerated().reduce(CGFloat.zero) { partial, entry in
            let childHeight = measureSubtree(node: entry.element, nodeSizes: nodeSizes, into: &heights)
            return partial + childHeight + (entry.offset == 0 ? 0 : RNVJsonGraphSceneMetrics.verticalGap)
        }

        let subtreeHeight = max(nodeHeight, childrenHeight)
        heights[node.id] = subtreeHeight
        return subtreeHeight
    }

    @discardableResult
    private nonisolated static func layoutNode(
        node: JsonGraphNode,
        depth: Int,
        topY: CGFloat,
        nodeSizes: [String: CGSize],
        columnWidths: [Int: CGFloat],
        columnGapWidths: [Int: CGFloat],
        subtreeHeights: [String: CGFloat],
        nodes: inout [JsonGraphLayoutNode],
        edges: inout [JsonGraphLayoutEdge]
    ) -> CGRect {
        let nodeSize = nodeSizes[node.id] ?? CGSize(
            width: RNVJsonGraphSceneMetrics.minimumNodeWidth,
            height: RNVJsonGraphSceneMetrics.minimumNodeHeight
        )
        let subtreeHeight = subtreeHeights[node.id] ?? nodeSize.height
        let x = xPosition(
            for: depth,
            columnWidths: columnWidths,
            columnGapWidths: columnGapWidths
        )

        guard !node.children.isEmpty else {
            let y = topY + max((subtreeHeight - nodeSize.height) / 2, 0)
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: nodeSize)
            nodes.append(
                JsonGraphLayoutNode(
                    id: node.id,
                    path: node.path,
                    edgeLabel: node.edgeLabel,
                    kind: node.kind,
                    preview: node.preview,
                    depth: depth,
                    frame: frame
                )
            )
            return frame
        }

        let childrenTotalHeight = node.children.enumerated().reduce(CGFloat.zero) { partial, entry in
            let childHeight = subtreeHeights[entry.element.id] ?? nodeSize.height
            return partial + childHeight + (entry.offset == 0 ? 0 : RNVJsonGraphSceneMetrics.verticalGap)
        }

        var childTopY = topY + max((subtreeHeight - childrenTotalHeight) / 2, 0)
        var childFrames: [CGRect] = []

        for child in node.children {
            let childFrame = layoutNode(
                node: child,
                depth: depth + 1,
                topY: childTopY,
                nodeSizes: nodeSizes,
                columnWidths: columnWidths,
                columnGapWidths: columnGapWidths,
                subtreeHeights: subtreeHeights,
                nodes: &nodes,
                edges: &edges
            )
            childFrames.append(childFrame)
            childTopY += (subtreeHeights[child.id] ?? childFrame.height) + RNVJsonGraphSceneMetrics.verticalGap
        }

        let centerY = (childFrames.first!.midY + childFrames.last!.midY) / 2
        let y = centerY - (nodeSize.height / 2)
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: nodeSize)

        nodes.append(
            JsonGraphLayoutNode(
                id: node.id,
                path: node.path,
                edgeLabel: node.edgeLabel,
                kind: node.kind,
                preview: node.preview,
                depth: depth,
                frame: frame
            )
        )

        for (child, childFrame) in zip(node.children, childFrames) {
            edges.append(
                JsonGraphLayoutEdge(
                    id: "\(node.id)->\(child.id)",
                    fromID: node.id,
                    toID: child.id,
                    fromPoint: CGPoint(x: frame.maxX, y: frame.midY),
                    toPoint: CGPoint(x: childFrame.minX, y: childFrame.midY),
                    label: child.edgeLabel ?? child.path
                )
            )
        }

        return frame
    }

    private nonisolated static func xPosition(
        for depth: Int,
        columnWidths: [Int: CGFloat],
        columnGapWidths: [Int: CGFloat]
    ) -> CGFloat {
        guard depth > 0 else {
            return RNVJsonGraphSceneMetrics.canvasPadding.width
        }

        let previousColumnsWidth = (0..<depth).reduce(CGFloat.zero) { partial, level in
            partial + (columnWidths[level] ?? RNVJsonGraphSceneMetrics.minimumNodeWidth)
        }
        let previousGaps = (0..<depth).reduce(CGFloat.zero) { partial, level in
            partial + (columnGapWidths[level] ?? RNVJsonGraphSceneMetrics.horizontalGap)
        }
        return RNVJsonGraphSceneMetrics.canvasPadding.width + previousColumnsWidth + previousGaps
    }
}

private enum RNVJsonGraphSceneMetrics {
    nonisolated static let minimumNodeWidth: CGFloat = 220
    nonisolated static let maximumNodeWidth: CGFloat = 360
    nonisolated static let minimumNodeHeight: CGFloat = 92
    nonisolated static let horizontalGap: CGFloat = 84
    nonisolated static let verticalGap: CGFloat = 32
    nonisolated static let canvasPadding = CGSize(width: 48, height: 52)
    nonisolated static let nodePadding = CGSize(width: 12, height: 12)
    nonisolated static let nodeSpacing: CGFloat = 8
    nonisolated static let badgeHorizontalPadding: CGFloat = 8
    nonisolated static let badgeVerticalPadding: CGFloat = 4
    nonisolated static let edgeLabelHorizontalPadding: CGFloat = 6
    nonisolated static let edgeLabelVerticalPadding: CGFloat = 3

    nonisolated static func nodeSize(for node: JsonGraphNode) -> CGSize {
        let badgeFont = badgeFont()
        let previewFont = previewFont()
        let pathFont = pathFont()
        let badgeSize = textSize(
            node.kind.title.uppercased(),
            font: badgeFont,
            maxWidth: .greatestFiniteMagnitude,
            lineBreakMode: .byClipping
        )
        let previewNaturalWidth = textSize(
            node.preview,
            font: previewFont,
            maxWidth: .greatestFiniteMagnitude,
            lineBreakMode: .byClipping
        ).width
        let pathNaturalWidth = textSize(
            node.path,
            font: pathFont,
            maxWidth: .greatestFiniteMagnitude,
            lineBreakMode: .byClipping
        ).width

        let badgeWidth = badgeSize.width + (badgeHorizontalPadding * 2)
        let desiredContentWidth = min(
            maximumNodeWidth - (nodePadding.width * 2),
            max(previewNaturalWidth, pathNaturalWidth, badgeWidth)
        )
        let width = max(
            minimumNodeWidth,
            min(maximumNodeWidth, ceil(desiredContentWidth + (nodePadding.width * 2)))
        )

        let contentWidth = width - (nodePadding.width * 2)
        let previewHeight = min(
            textSize(
                node.preview,
                font: previewFont,
                maxWidth: contentWidth,
                lineBreakMode: .byTruncatingTail
            ).height,
            lineHeight(for: previewFont) * 2
        )
        let pathHeight = lineHeight(for: pathFont)
        let badgeHeight = lineHeight(for: badgeFont) + (badgeVerticalPadding * 2)
        let height = max(
            minimumNodeHeight,
            ceil(
                nodePadding.height +
                badgeHeight +
                nodeSpacing +
                previewHeight +
                nodeSpacing +
                pathHeight +
                nodePadding.height
            )
        )

        return CGSize(width: width, height: height)
    }

    nonisolated static func edgeLabelFrame(for edge: JsonGraphLayoutEdge) -> CGRect {
        let edgeLabelFont = edgeLabelFont()
        let labelSize = edgeLabelSize(for: edge.label, font: edgeLabelFont)
        let width = labelSize.width
        let height = labelSize.height
        let midpointX = edge.fromPoint.x + ((edge.toPoint.x - edge.fromPoint.x) * 0.5)
        let anchorY = edge.toPoint.y
        return CGRect(
            x: midpointX - (width / 2),
            y: anchorY - 14 - (height / 2),
            width: width,
            height: height
        )
    }

    nonisolated static func minimumGapWidth(forEdgeLabel label: String) -> CGFloat {
        let labelSize = edgeLabelSize(for: label, font: edgeLabelFont())
        return max(horizontalGap, labelSize.width + 16)
    }

    private nonisolated static func edgeLabelSize(for label: String, font: NSFont) -> CGSize {
        let labelTextSize = textSize(
            label,
            font: font,
            maxWidth: maximumNodeWidth,
            lineBreakMode: .byTruncatingMiddle
        )
        return CGSize(
            width: labelTextSize.width + (edgeLabelHorizontalPadding * 2),
            height: labelTextSize.height + (edgeLabelVerticalPadding * 2)
        )
    }

    private nonisolated static func textSize(
        _ text: String,
        font: NSFont,
        maxWidth: CGFloat,
        lineBreakMode: NSLineBreakMode
    ) -> CGSize {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lineBreakMode

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let measured = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral

        return CGSize(
            width: ceil(max(measured.width, 1)),
            height: ceil(max(measured.height, lineHeight(for: font)))
        )
    }

    private nonisolated static func badgeFont() -> NSFont {
        NSFont.systemFont(ofSize: 10, weight: .semibold)
    }

    private nonisolated static func previewFont() -> NSFont {
        NSFont.systemFont(ofSize: 15, weight: .semibold)
    }

    private nonisolated static func pathFont() -> NSFont {
        NSFont.systemFont(ofSize: 12, weight: .regular)
    }

    private nonisolated static func edgeLabelFont() -> NSFont {
        NSFont.systemFont(ofSize: 10, weight: .semibold)
    }

    nonisolated static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
}

struct RNVJsonGraphSceneDrawingStyle {
    let zoomScale: CGFloat
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    let contentSpacing: CGFloat
    let badgeHorizontalPadding: CGFloat
    let badgeVerticalPadding: CGFloat
    let edgeLabelHorizontalPadding: CGFloat
    let edgeLabelVerticalPadding: CGFloat
    let badgeFontSize: CGFloat
    let previewFontSize: CGFloat
    let pathFontSize: CGFloat
    let edgeLabelFontSize: CGFloat

    nonisolated init(zoomScale: CGFloat) {
        let resolvedScale = max(zoomScale, 0.25)
        self.zoomScale = resolvedScale
        self.cornerRadius = max(4, 12 * resolvedScale)
        self.contentPadding = max(4, 12 * resolvedScale)
        self.contentSpacing = max(2, 8 * resolvedScale)
        self.badgeHorizontalPadding = max(3, 8 * resolvedScale)
        self.badgeVerticalPadding = max(2, 4 * resolvedScale)
        self.edgeLabelHorizontalPadding = max(3, 6 * resolvedScale)
        self.edgeLabelVerticalPadding = max(1.5, 3 * resolvedScale)
        self.badgeFontSize = max(3.5, 10 * resolvedScale)
        self.previewFontSize = max(5, 15 * resolvedScale)
        self.pathFontSize = max(4, 12 * resolvedScale)
        self.edgeLabelFontSize = max(3.5, 10 * resolvedScale)
    }

    @MainActor
    func badgeFont() -> NSFont {
        NSFont.systemFont(ofSize: badgeFontSize, weight: .semibold)
    }

    @MainActor
    func previewFont() -> NSFont {
        NSFont.systemFont(ofSize: previewFontSize, weight: .semibold)
    }

    @MainActor
    func pathFont() -> NSFont {
        NSFont.systemFont(ofSize: pathFontSize, weight: .regular)
    }

    @MainActor
    func edgeLabelFont() -> NSFont {
        NSFont.systemFont(ofSize: edgeLabelFontSize, weight: .semibold)
    }
}

enum RNVJsonGraphEdgeLabelLayout {
    nonisolated static func frame(
        for edge: JsonGraphLayoutEdge,
        font: NSFont,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) -> CGRect {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingMiddle

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: edge.label, attributes: attributes)
        let measured = attributedString.boundingRect(
            with: CGSize(width: RNVJsonGraphSceneMetrics.maximumNodeWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral

        let width = ceil(max(measured.width, 1)) + (horizontalPadding * 2)
        let height = ceil(max(measured.height, RNVJsonGraphSceneMetrics.lineHeight(for: font))) + (verticalPadding * 2)
        let midpointX = edge.fromPoint.x + ((edge.toPoint.x - edge.fromPoint.x) * 0.5)
        let anchorY = edge.toPoint.y
        return CGRect(
            x: midpointX - (width / 2),
            y: anchorY - (14 * max(font.pointSize / 10, 0.35)) - (height / 2),
            width: width,
            height: height
        )
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

struct RNVJsonGraphSceneScrollView: NSViewRepresentable {
    let layout: JsonGraphLayoutDocument
    let zoomScale: CGFloat
    let palette: FlipperPalette
    let selectedNodeID: String?
    let onZoomRequested: (CGFloat) -> Void
    let onSelectNode: (String) -> Void

    func makeNSView(context: Context) -> RNVJsonGraphPanScrollView {
        let scrollView = RNVJsonGraphPanScrollView()
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

    func updateNSView(_ scrollView: RNVJsonGraphPanScrollView, context: Context) {
        context.coordinator.documentView.update(
            baseLayout: layout,
            zoomScale: zoomScale,
            palette: palette,
            selectedNodeID: selectedNodeID,
            onSelectNode: onSelectNode
        )
        scrollView.documentView = context.coordinator.documentView
        scrollView.currentZoomScale = zoomScale
        scrollView.onZoomRequested = onZoomRequested
        scrollView.applyPendingZoomAnchorIfNeeded(contentSize: context.coordinator.documentView.frame.size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let documentView = RNVJsonGraphDocumentView()
    }
}

final class RNVJsonGraphPanScrollView: NSScrollView {
    private struct PendingZoomAnchor {
        let currentOrigin: CGPoint
        let viewportPoint: CGPoint
        let previousScale: CGFloat
        let nextScale: CGFloat
    }

    var currentZoomScale: CGFloat = 1
    var onZoomRequested: ((CGFloat) -> Void)?
    private var pendingZoomAnchor: PendingZoomAnchor?

    override func scrollWheel(with event: NSEvent) {
        if let nextScale = JsonGraphZoomMath.nextScale(
            currentScale: currentZoomScale,
            scrollDeltaY: event.scrollingDeltaY,
            isControlPressed: event.modifierFlags.contains(.control)
        ) {
            guard abs(nextScale - currentZoomScale) > 0.0001 else {
                return
            }

            let clipView = contentView
            let locationInClip = clipView.convert(event.locationInWindow, from: nil)
            let viewportPoint = CGPoint(
                x: min(max(locationInClip.x - clipView.bounds.origin.x, 0), clipView.bounds.width),
                y: min(max(locationInClip.y - clipView.bounds.origin.y, 0), clipView.bounds.height)
            )

            pendingZoomAnchor = PendingZoomAnchor(
                currentOrigin: clipView.bounds.origin,
                viewportPoint: viewportPoint,
                previousScale: currentZoomScale,
                nextScale: nextScale
            )
            onZoomRequested?(nextScale)
            return
        }

        super.scrollWheel(with: event)
    }

    func applyPendingZoomAnchorIfNeeded(contentSize: CGSize) {
        guard let pendingZoomAnchor else {
            return
        }
        guard abs(currentZoomScale - pendingZoomAnchor.nextScale) <= 0.0001 else {
            return
        }

        let clipView = contentView
        let nextOrigin = JsonGraphZoomAnchorMath.nextOrigin(
            currentOrigin: pendingZoomAnchor.currentOrigin,
            viewportPoint: pendingZoomAnchor.viewportPoint,
            currentScale: pendingZoomAnchor.previousScale,
            nextScale: pendingZoomAnchor.nextScale,
            contentSize: contentSize,
            viewportSize: clipView.bounds.size
        )
        clipView.setBoundsOrigin(nextOrigin)
        reflectScrolledClipView(clipView)
        self.pendingZoomAnchor = nil
    }
}

final class RNVJsonGraphDocumentView: NSView {
    private var layoutDocument = JsonGraphLayoutDocument(nodes: [], edges: [], contentSize: .zero)
    private var zoomScale: CGFloat = 1
    private var palette = FlipperPalette(for: .light)
    private var selectedNodeID: String?
    private var onSelectNode: ((String) -> Void)?
    private var lastRightDragWindowLocation: CGPoint?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        baseLayout: JsonGraphLayoutDocument,
        zoomScale: CGFloat,
        palette: FlipperPalette,
        selectedNodeID: String?,
        onSelectNode: @escaping (String) -> Void
    ) {
        self.layoutDocument = baseLayout.scaled(by: zoomScale)
        self.zoomScale = zoomScale
        self.palette = palette
        self.selectedNodeID = selectedNodeID
        self.onSelectNode = onSelectNode
        frame = CGRect(
            origin: .zero,
            size: CGSize(
                width: layoutDocument.contentSize.width + 48,
                height: layoutDocument.contentSize.height + 48
            )
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for edge in layoutDocument.edges {
            drawEdgeStroke(edge)
        }

        for edge in layoutDocument.edges {
            drawEdgeLabel(edge)
        }

        for node in layoutDocument.nodes {
            drawNode(node, isSelected: node.id == selectedNodeID)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let node = layoutDocument.nodes.reversed().first(where: { $0.frame.contains(location) }) else {
            return
        }

        onSelectNode?(node.id)
    }

    override var acceptsFirstResponder: Bool {
        true
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

    private func drawEdgeStroke(_ edge: JsonGraphLayoutEdge) {
        let path = NSBezierPath()
        let start = edge.fromPoint
        let end = edge.toPoint
        let midpointX = start.x + ((end.x - start.x) * 0.5)

        path.move(to: start)
        path.line(to: CGPoint(x: midpointX, y: start.y))
        path.line(to: CGPoint(x: midpointX, y: end.y))
        path.line(to: end)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let isHighlighted = selectedNodeID == edge.fromID || selectedNodeID == edge.toID
        let underStrokeWidth = max(3.5, 5 * zoomScale)
        let mainStrokeWidth = max(1.8, (isHighlighted ? 2.6 : 2.1) * zoomScale)
        let edgeColor = isHighlighted ? nsColor(palette.accent) : nsColor(hex: 0x8C8C8C, alpha: 0.92)

        path.lineWidth = underStrokeWidth
        NSColor.white.setStroke()
        path.stroke()

        path.lineWidth = mainStrokeWidth
        edgeColor.setStroke()
        path.stroke()

        let anchorDiameter = max(7, 8 * zoomScale)
        let anchorRadius = anchorDiameter / 2
        drawAnchor(
            center: start,
            radius: anchorRadius,
            strokeColor: edgeColor,
            lineWidth: max(1.2, (isHighlighted ? 2 : 1.5) * zoomScale)
        )
        drawAnchor(
            center: end,
            radius: anchorRadius,
            strokeColor: edgeColor,
            lineWidth: max(1.2, (isHighlighted ? 2 : 1.5) * zoomScale)
        )
    }

    private func drawAnchor(center: CGPoint, radius: CGFloat, strokeColor: NSColor, lineWidth: CGFloat) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill()
        path.fill()
        path.lineWidth = lineWidth
        strokeColor.setStroke()
        path.stroke()
    }

    private func drawEdgeLabel(_ edge: JsonGraphLayoutEdge) {
        let isHighlighted = selectedNodeID == edge.fromID || selectedNodeID == edge.toID
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: zoomScale)
        let edgeLabelFont = style.edgeLabelFont()
        let labelFrame = RNVJsonGraphEdgeLabelLayout.frame(
            for: edge,
            font: edgeLabelFont,
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )
        let backgroundPath = NSBezierPath(
            roundedRect: labelFrame,
            xRadius: labelFrame.height / 2,
            yRadius: labelFrame.height / 2
        )
        let fillColor = isHighlighted ? nsColor(palette.accentMuted) : .white
        fillColor.setFill()
        backgroundPath.fill()

        let strokeColor = isHighlighted ? nsColor(palette.accent) : nsColor(palette.border)
        strokeColor.setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingMiddle

        let attributes: [NSAttributedString.Key: Any] = [
            .font: edgeLabelFont,
            .foregroundColor: isHighlighted ? nsColor(palette.accent) : nsColor(hex: 0x434343),
            .paragraphStyle: paragraphStyle
        ]
        let textRect = labelFrame.insetBy(
            dx: style.edgeLabelHorizontalPadding,
            dy: style.edgeLabelVerticalPadding
        )
        edge.label.draw(in: textRect, withAttributes: attributes)
    }

    private func drawNode(_ node: JsonGraphLayoutNode, isSelected: Bool) {
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: zoomScale)
        let cornerRadius = style.cornerRadius
        let nodePath = NSBezierPath(
            roundedRect: node.frame,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        let fillColor = isSelected ? nsColor(hex: 0xF3E8FF) : .white
        fillColor.setFill()
        nodePath.fill()

        nodePath.lineWidth = isSelected ? 2 : 1
        (isSelected ? nsColor(palette.accent) : nsColor(palette.border)).setStroke()
        nodePath.stroke()

        let badgeFont = style.badgeFont()
        let previewFont = style.previewFont()
        let pathFont = style.pathFont()
        let contentRect = node.frame.insetBy(dx: style.contentPadding, dy: style.contentPadding)
        let badgeText = node.kind.title.uppercased()
        let badgeParagraph = NSMutableParagraphStyle()
        badgeParagraph.lineBreakMode = .byClipping
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: badgeForegroundColor(for: node.kind),
            .paragraphStyle: badgeParagraph
        ]
        let badgeTextSize = (badgeText as NSString).size(withAttributes: badgeAttributes)
        let badgeRect = CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: badgeTextSize.width + (style.badgeHorizontalPadding * 2),
            height: RNVJsonGraphSceneMetrics.lineHeight(for: badgeFont) + (style.badgeVerticalPadding * 2)
        )
        let badgePath = NSBezierPath(
            roundedRect: badgeRect,
            xRadius: badgeRect.height / 2,
            yRadius: badgeRect.height / 2
        )
        badgeBackgroundColor(for: node.kind).setFill()
        badgePath.fill()
        badgeText.draw(
            in: badgeRect.insetBy(dx: style.badgeHorizontalPadding, dy: style.badgeVerticalPadding),
            withAttributes: badgeAttributes
        )

        let previewTop = badgeRect.maxY + style.contentSpacing
        let pathHeight = RNVJsonGraphSceneMetrics.lineHeight(for: pathFont)
        let previewRect = CGRect(
            x: contentRect.minX,
            y: previewTop,
            width: contentRect.width,
            height: max(
                contentRect.maxY - previewTop - style.contentSpacing - pathHeight,
                RNVJsonGraphSceneMetrics.lineHeight(for: previewFont)
            )
        )
        let pathRect = CGRect(
            x: contentRect.minX,
            y: contentRect.maxY - pathHeight,
            width: contentRect.width,
            height: pathHeight
        )

        NSGraphicsContext.saveGraphicsState()
        nodePath.addClip()

        let previewParagraph = NSMutableParagraphStyle()
        previewParagraph.lineBreakMode = .byTruncatingTail
        let previewAttributes: [NSAttributedString.Key: Any] = [
            .font: previewFont,
            .foregroundColor: nsColor(palette.primaryText),
            .paragraphStyle: previewParagraph
        ]
        (node.preview as NSString).draw(
            with: previewRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: previewAttributes
        )

        let pathParagraph = NSMutableParagraphStyle()
        pathParagraph.lineBreakMode = .byTruncatingMiddle
        let pathAttributes: [NSAttributedString.Key: Any] = [
            .font: pathFont,
            .foregroundColor: nsColor(palette.secondaryText),
            .paragraphStyle: pathParagraph
        ]
        (node.path as NSString).draw(
            with: pathRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: pathAttributes
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func badgeBackgroundColor(for kind: JsonGraphNodeKind) -> NSColor {
        switch kind {
        case .object:
            return nsColor(hex: 0xE6F4FF)
        case .array:
            return nsColor(hex: 0xF9F0FF)
        case .string:
            return nsColor(hex: 0xF6FFED)
        case .number:
            return nsColor(hex: 0xFFF7E6)
        case .boolean:
            return nsColor(hex: 0xE6FFFB)
        case .null:
            return nsColor(hex: 0xF5F5F5)
        }
    }

    private func badgeForegroundColor(for kind: JsonGraphNodeKind) -> NSColor {
        switch kind {
        case .object:
            return nsColor(hex: 0x0958D9)
        case .array:
            return nsColor(hex: 0x722ED1)
        case .string:
            return nsColor(hex: 0x389E0D)
        case .number:
            return nsColor(hex: 0xD46B08)
        case .boolean:
            return nsColor(hex: 0x08979C)
        case .null:
            return nsColor(hex: 0x595959)
        }
    }

    private func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }

    private func nsColor(hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
