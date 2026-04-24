import Combine
import Foundation
import XCTest
@testable import ReactNativeViewer

@MainActor
final class ReactNativeViewerTests: XCTestCase {
    override func setUp() {
        super.setUp()

        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("ConsoleDebuggerViewModel.") }
            .forEach { defaults.removeObject(forKey: $0) }
    }

    private func makeDebuggerPersistence(testName: String = #function) -> ConsoleDebuggerViewModel.Persistence {
        let suiteName = "ReactNativeViewerTests.\(testName)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return ConsoleDebuggerViewModel.Persistence(userDefaults: userDefaults)
    }

    func testDisplayNameMatchesExpectedProductName() {
        XCTAssertEqual(AppConstants.displayName, "React Native Viewer")
    }

    func testAppLanguageSystemResolvesVietnameseFromPreferredLanguages() {
        let resolvedLanguage = AppLanguage.system.resolvedLanguage(
            preferredLanguages: ["vi-VN"],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(resolvedLanguage, .vietnamese)
    }

    func testAppLanguageQuickSelectionReflectsResolvedLanguage() {
        XCTAssertEqual(AppLanguage.english.quickSelection, .english)
        XCTAssertEqual(AppLanguage.vietnamese.quickSelection, .vietnamese)
    }

    func testAppStringsReturnVietnameseTextWithDiacritics() {
        XCTAssertEqual(
            AppStrings.text(.displayLanguage, language: .vietnamese),
            "Ngôn ngữ hiển thị"
        )
        XCTAssertEqual(
            AppStrings.languageOptionTitle(.vietnamese, currentLanguage: .vietnamese),
            "Tiếng Việt"
        )
    }

    func testAppStringsLocalizeDynamicFinderStatusInVietnamese() {
        XCTAssertEqual(
            AppStrings.foundConnectableLinks(3, language: .vietnamese),
            "Đã tìm thấy 3 liên kết có thể kết nối."
        )
        XCTAssertEqual(
            AppStrings.detectionFinished(2, language: .vietnamese),
            "Đã quét xong với 2 liên kết khả dụng."
        )
    }

    func testResolveInputTreatsWebSocketURLAsDirectConnection() throws {
        let resolution = try XCTUnwrap(
            DevtoolsEndpointParser.resolveInput(" ws://127.0.0.1:8081/inspector/debug?device=sim&page=3 ")
        )

        switch resolution {
        case .direct(let candidate):
            XCTAssertEqual(candidate.webSocketURL.absoluteString, "ws://127.0.0.1:8081/inspector/debug?device=sim&page=3")
            XCTAssertEqual(candidate.displayName, "127.0.0.1:8081")
        case .jsonList:
            XCTFail("Expected a direct websocket candidate")
        }
    }

    func testResolveInputTransformsInspectorHTTPURLIntoWebSocketConnection() throws {
        let resolution = try XCTUnwrap(
            DevtoolsEndpointParser.resolveInput("http://localhost:8081/inspector/debug?device=device-42&page=9")
        )

        switch resolution {
        case .direct(let candidate):
            XCTAssertEqual(candidate.webSocketURL.absoluteString, "ws://localhost:8081/inspector/debug?device=device-42&page=9")
            XCTAssertEqual(candidate.displayName, "localhost:8081")
        case .jsonList:
            XCTFail("Expected an inspector link to resolve directly to websocket")
        }
    }

    func testResolveInputKeepsJSONListEndpointForDiscovery() throws {
        let resolution = try XCTUnwrap(
            DevtoolsEndpointParser.resolveInput("http://localhost:8081/json/list")
        )

        switch resolution {
        case .direct:
            XCTFail("Expected /json/list input to stay as a discovery endpoint")
        case .jsonList(let url):
            XCTAssertEqual(url.absoluteString, "http://localhost:8081/json/list")
        }
    }

    func testDecodeJSONListProducesConsoleCandidates() throws {
        let json = """
        [
          {
            "id": "page-1",
            "title": "React Native Experimental",
            "description": "index.bundle?platform=ios",
            "webSocketDebuggerUrl": "ws://localhost:8081/inspector/debug?device=device-1&page=1",
            "vm": "Hermes"
          },
          {
            "id": "page-2",
            "title": "Secondary Screen",
            "description": "src/screens/Settings.tsx",
            "websocketDebuggerUrl": "ws://localhost:8081/inspector/debug?device=device-1&page=2"
          }
        ]
        """
        let data = Data(json.utf8)

        let candidates = try DevtoolsEndpointParser.decodeJSONList(
            data: data,
            sourceURL: URL(string: "http://localhost:8081/json/list")!
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].displayName, "React Native Experimental")
        XCTAssertEqual(candidates[0].detailText, "index.bundle?platform=ios")
        XCTAssertEqual(candidates[0].webSocketURL.absoluteString, "ws://localhost:8081/inspector/debug?device=device-1&page=1")
        XCTAssertEqual(candidates[1].displayName, "Secondary Screen")
        XCTAssertEqual(candidates[1].detailText, "src/screens/Settings.tsx")
    }

    func testConsoleDebuggerFiltersLogsByTextContainsAcrossMessageAndSource() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Booted React Native bridge",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .error,
                message: "Unhandled promise rejection",
                source: "src/api/client.ts"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs)
        viewModel.searchText = "client.ts"

        XCTAssertEqual(viewModel.filteredLogs.count, 1)
        XCTAssertEqual(viewModel.filteredLogs.first?.message, "Unhandled promise rejection")
    }

    func testConsoleDebuggerFiltersLogsByAnyKeywordAcrossSearchTokens() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Booted React Native bridge",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .warn,
                message: "Request finished with stale cache",
                source: "src/network/client.ts"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                level: .error,
                message: "Unhandled promise rejection",
                source: "src/api/service.ts"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs)
        viewModel.searchText = "bridge client.ts"

        XCTAssertEqual(viewModel.filteredLogs.map(\.message), [
            "Request finished with stale cache",
            "Booted React Native bridge"
        ])
    }

    func testConsoleDebuggerFiltersLogsByPinnedSearchTermsAndDraftAsOR() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Booted React Native bridge",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .warn,
                message: "Request finished with stale cache",
                source: "src/network/client.ts"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                level: .error,
                message: "Unhandled promise rejection",
                source: "src/api/service.ts"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs)
        viewModel.searchText = "bridge"
        viewModel.addSearchTermFromDraft()
        viewModel.searchText = "service.ts"

        XCTAssertEqual(viewModel.searchTerms, ["bridge"])
        XCTAssertEqual(viewModel.filteredLogs.map(\.message), [
            "Unhandled promise rejection",
            "Booted React Native bridge"
        ])
    }

    func testConsoleDebuggerFiltersLogsBySelectedLevels() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Booted React Native bridge",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .warn,
                message: "VirtualizedList slow update",
                source: "src/screens/Home.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                level: .error,
                message: "Unhandled promise rejection",
                source: "src/api/client.ts"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs)
        viewModel.selectedLevels = [.warn, .error]

        XCTAssertEqual(viewModel.filteredLogs.map(\.level), [.error, .warn])
        XCTAssertEqual(viewModel.levelFilterTitle, "WARN + ERROR")
    }

    func testConsoleDebuggerOrdersNewestLogsFirst() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Oldest log",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                level: .error,
                message: "Newest log",
                source: "src/api/client.ts"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .warn,
                message: "Middle log",
                source: "src/screens/Home.tsx"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs)

        XCTAssertEqual(viewModel.filteredLogs.map(\.message), [
            "Newest log",
            "Middle log",
            "Oldest log"
        ])
    }

    func testConsoleDebuggerCanToggleLogSortOrderToOldestFirst() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Oldest log",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                level: .error,
                message: "Newest log",
                source: "src/api/client.ts"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .warn,
                message: "Middle log",
                source: "src/screens/Home.tsx"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs)
        viewModel.toggleConsoleLogSortOrder()

        XCTAssertEqual(viewModel.filteredLogs.map(\.message), [
            "Oldest log",
            "Middle log",
            "Newest log"
        ])
    }

    func testConsoleDebuggerPersistsSortOrderAcrossViewModels() {
        let persistence = makeDebuggerPersistence()

        let firstViewModel = ConsoleDebuggerViewModel(persistence: persistence)
        firstViewModel.toggleConsoleLogSortOrder()

        let restoredViewModel = ConsoleDebuggerViewModel(persistence: persistence)

        XCTAssertEqual(restoredViewModel.consoleLogSortOrder, .oldestFirst)
    }

    func testConsoleDebuggerPersistsSearchDraftAndPinnedTermsPerTab() {
        let persistence = makeDebuggerPersistence()

        let firstViewModel = ConsoleDebuggerViewModel(persistence: persistence)
        firstViewModel.setDraftSearchText("bridge", for: .console)
        firstViewModel.addSearchTermFromDraft(for: .console)
        firstViewModel.setDraftSearchText("current draft", for: .console)
        firstViewModel.setDraftSearchText("documents", for: .network)
        firstViewModel.addSearchTermFromDraft(for: .network)
        firstViewModel.setDraftSearchText("network draft", for: .network)

        let restoredViewModel = ConsoleDebuggerViewModel(persistence: persistence)

        XCTAssertEqual(restoredViewModel.pinnedSearchTerms(for: .console), ["bridge"])
        XCTAssertEqual(restoredViewModel.draftSearchText(for: .console), "current draft")
        XCTAssertEqual(restoredViewModel.pinnedSearchTerms(for: .network), ["documents"])
        XCTAssertEqual(restoredViewModel.draftSearchText(for: .network), "network draft")
    }

    func testConsoleDebuggerPersistenceDefaultsSidebarModeToExpanded() {
        let persistence = makeDebuggerPersistence()

        XCTAssertEqual(persistence.loadSidebarDisplayMode(), .expanded)
    }

    func testConsoleDebuggerPersistenceStoresSidebarMode() {
        let persistence = makeDebuggerPersistence()

        persistence.saveSidebarDisplayMode(.iconOnly)

        XCTAssertEqual(persistence.loadSidebarDisplayMode(), .iconOnly)
    }

    func testConsoleDebuggerCompareTextsMarksMatchingInputsAsSame() {
        let viewModel = ConsoleDebuggerViewModel()
        viewModel.compareFirstText = "react-native"
        viewModel.compareSecondText = "react-native"

        viewModel.compareTexts()

        XCTAssertEqual(viewModel.compareMode, .results)
        XCTAssertEqual(viewModel.compareResult, .same)
    }

    func testConsoleDebuggerCompareTextsMarksDifferentInputsAsDifferent() {
        let viewModel = ConsoleDebuggerViewModel()
        viewModel.compareFirstText = "ios"
        viewModel.compareSecondText = "android"

        viewModel.compareTexts()

        XCTAssertEqual(viewModel.compareMode, .results)
        XCTAssertEqual(viewModel.compareResult, .different)
    }

    func testConsoleDebuggerCompareTextsBuildsHighlightedDifferenceSegments() {
        let viewModel = ConsoleDebuggerViewModel()
        viewModel.compareFirstText = "hello ios world"
        viewModel.compareSecondText = "hello android world"

        viewModel.compareTexts()

        XCTAssertTrue(viewModel.compareFirstSegments.contains {
            $0.isDifferent && $0.text.contains("ios")
        })
        XCTAssertTrue(viewModel.compareSecondSegments.contains {
            $0.isDifferent && $0.text.contains("android")
        })
    }

    func testConsoleDebuggerResetCompareReturnsToEditingModeWithoutClearingInputs() {
        let viewModel = ConsoleDebuggerViewModel()
        viewModel.compareFirstText = "left"
        viewModel.compareSecondText = "right"
        viewModel.compareTexts()

        viewModel.resetCompare()

        XCTAssertEqual(viewModel.compareMode, .editing)
        XCTAssertEqual(viewModel.compareResult, .idle)
        XCTAssertTrue(viewModel.compareFirstSegments.isEmpty)
        XCTAssertTrue(viewModel.compareSecondSegments.isEmpty)
        XCTAssertEqual(viewModel.compareFirstText, "left")
        XCTAssertEqual(viewModel.compareSecondText, "right")
    }

    func testJsonGraphBuilderParsesNestedObjectIntoNodeTree() throws {
        let json = """
        {
          "user": {
            "name": "An",
            "active": true
          },
          "items": [1, null]
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 20)

        XCTAssertEqual(document.root.kind, .object)
        XCTAssertEqual(document.nodeCount, 7)
        XCTAssertEqual(document.root.children.map(\.edgeLabel), ["items", "user"])
        XCTAssertEqual(document.root.children[0].kind, .array)
        XCTAssertEqual(document.root.children[0].children.map(\.edgeLabel), ["[0]", "[1]"])
        XCTAssertEqual(document.root.children[1].kind, .object)
        XCTAssertEqual(document.root.children[1].children.map(\.edgeLabel), ["active", "name"])
        XCTAssertEqual(document.root.children[1].children[1].preview, "\"An\"")
    }

    func testJsonGraphBuilderParsesTopLevelArray() throws {
        let json = """
        [
          {"id": 1},
          {"id": 2}
        ]
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 20)

        XCTAssertEqual(document.root.kind, .array)
        XCTAssertEqual(document.root.children.map(\.path), ["$[0]", "$[1]"])
        XCTAssertEqual(document.root.children.first?.children.first?.path, "$[0].id")
    }

    func testJsonGraphBuilderThrowsParseErrorForInvalidJSON() {
        XCTAssertThrowsError(
            try JsonGraphBuilder.build(from: "{\"user\":", nodeLimit: 20)
        ) { error in
            XCTAssertEqual(error as? JsonGraphBuildError, .invalidJSON("The data is not in the correct format."))
        }
    }

    func testJsonGraphBuilderThrowsNodeLimitExceededError() {
        let json = """
        {
          "user": {
            "name": "An",
            "active": true
          },
          "items": [1, null]
        }
        """

        XCTAssertThrowsError(
            try JsonGraphBuilder.build(from: json, nodeLimit: 3)
        ) { error in
            XCTAssertEqual(error as? JsonGraphBuildError, .nodeLimitExceeded(limit: 3))
        }
    }

    func testJsonGraphWorkspaceViewModelImportsNetworkBodies() {
        let viewModel = JsonGraphWorkspaceViewModel()

        viewModel.useRequestBody("{\"request\":true}")
        XCTAssertEqual(viewModel.inputText, "{\"request\":true}")

        viewModel.useResponseBody("{\"response\":true}")
        XCTAssertEqual(viewModel.inputText, "{\"response\":true}")
    }

    @MainActor
    func testJsonGraphWorkspaceViewModelBuildsSelectionDetailForSelectedNode() {
        let viewModel = JsonGraphWorkspaceViewModel()
        viewModel.inputText = """
        {
          "profile": {
            "username": "abc"
          }
        }
        """

        viewModel.render()

        guard case .rendered = viewModel.renderState else {
            return XCTFail("Expected rendered state")
        }

        viewModel.toggleSelection(nodeID: "$.profile.username")

        XCTAssertEqual(viewModel.selectedNodeDetail?.propertyName, "username")
        XCTAssertEqual(viewModel.selectedNodeDetail?.dataType, "String")
        XCTAssertEqual(viewModel.selectedNodeDetail?.simpleGraph, "Root -> profile -> username")
    }

    @MainActor
    func testJsonGraphWorkspaceViewModelClearsSelectionWhenResetting() {
        let viewModel = JsonGraphWorkspaceViewModel()
        viewModel.inputText = """
        {
          "profile": {
            "username": "abc"
          }
        }
        """

        viewModel.render()

        guard case .rendered = viewModel.renderState else {
            return XCTFail("Expected rendered state")
        }

        viewModel.toggleSelection(nodeID: "$.profile")
        XCTAssertNotNil(viewModel.selectedNodeDetail)

        viewModel.reset()

        XCTAssertNil(viewModel.selectedNodeID)
        XCTAssertNil(viewModel.selectedNodeDetail)
    }

    func testJsonGraphLayoutBuilderCreatesStableFlatLayout() throws {
        let json = """
        {
          "menus": [
            {
              "menuId": 3,
              "menuName": "Văn bản đến"
            },
            {
              "menuId": 2,
              "menuName": "Văn bản đi"
            }
          ]
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 50)
        let layout = JsonGraphLayoutBuilder.build(from: document)

        XCTAssertEqual(layout.nodes.count, document.nodeCount)
        XCTAssertEqual(layout.edges.count, document.nodeCount - 1)
        XCTAssertEqual(layout.nodes.first(where: { $0.path == "$" })?.depth, 0)
        XCTAssertEqual(layout.nodes.first(where: { $0.path == "$.menus" })?.depth, 1)
        XCTAssertGreaterThan(layout.contentSize.width, 0)
        XCTAssertGreaterThan(layout.contentSize.height, 0)
    }

    func testJsonGraphLayoutBuilderExpandsNodeWidthForLongContent() throws {
        let json = """
        {
          "superLongPropertyNameThatShouldStretchTheNodeWidth": "This is a long preview text that should no longer be forced into a constant 220 point card."
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 20)
        let layout = JsonGraphLayoutBuilder.build(from: document)
        let childNode = try XCTUnwrap(
            layout.nodes.first(where: { $0.path == "$.superLongPropertyNameThatShouldStretchTheNodeWidth" })
        )

        XCTAssertGreaterThan(childNode.frame.width, 220)
    }

    func testJsonGraphLayoutDocumentScalingMultipliesFramesAndEdges() {
        let layout = JsonGraphLayoutDocument(
            nodes: [
                JsonGraphLayoutNode(
                    id: "$",
                    path: "$",
                    edgeLabel: nil,
                    kind: .object,
                    preview: "2 key(s)",
                    depth: 0,
                    frame: CGRect(x: 10, y: 20, width: 220, height: 92)
                ),
                JsonGraphLayoutNode(
                    id: "$.name",
                    path: "$.name",
                    edgeLabel: "name",
                    kind: .string,
                    preview: "\"An\"",
                    depth: 1,
                    frame: CGRect(x: 314, y: 40, width: 220, height: 92)
                )
            ],
            edges: [
                JsonGraphLayoutEdge(
                    id: "$->$.name",
                    fromID: "$",
                    toID: "$.name",
                    fromPoint: CGPoint(x: 230, y: 66),
                    toPoint: CGPoint(x: 314, y: 86),
                    label: "name"
                )
            ],
            contentSize: CGSize(width: 600, height: 240)
        )

        let scaled = layout.scaled(by: 1.5)

        XCTAssertEqual(scaled.nodes[0].frame.origin.x, 15, accuracy: 0.001)
        XCTAssertEqual(scaled.nodes[0].frame.origin.y, 30, accuracy: 0.001)
        XCTAssertEqual(scaled.nodes[0].frame.width, 330, accuracy: 0.001)
        XCTAssertEqual(scaled.edges[0].fromPoint.x, 345, accuracy: 0.001)
        XCTAssertEqual(scaled.edges[0].toPoint.y, 129, accuracy: 0.001)
        XCTAssertEqual(scaled.contentSize.width, 900, accuracy: 0.001)
        XCTAssertEqual(scaled.contentSize.height, 360, accuracy: 0.001)
    }

    func testJsonGraphDrawingStyleShrinksFontsWhenZoomingOut() {
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: 0.35)

        XCTAssertLessThan(style.previewFontSize, 12)
        XCTAssertLessThan(style.pathFontSize, 10)
        XCTAssertLessThan(style.badgeFontSize, 9)
    }

    @MainActor
    func testJsonGraphEdgeLabelFrameUsesScaledEdgeCoordinatesWithoutDoubleScaling() {
        let edge = JsonGraphLayoutEdge(
            id: "root->child",
            fromID: "root",
            toID: "child",
            fromPoint: CGPoint(x: 100, y: 80),
            toPoint: CGPoint(x: 220, y: 120),
            label: "parentId"
        )
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: 0.35)

        let frame = RNVJsonGraphEdgeLabelLayout.frame(
            for: edge,
            font: style.edgeLabelFont(),
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )

        XCTAssertEqual(frame.midX, 160, accuracy: 0.001)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    @MainActor
    func testJsonGraphLayoutKeepsLongEdgeLabelsClearOfConnectedNodes() throws {
        let json = """
        {
          "userTokenServer": {
            "deptId": "5176",
            "userId": "17107",
            "roleId": "918"
          }
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 20)
        let layout = JsonGraphLayoutBuilder.build(from: document)
        let parent = try XCTUnwrap(layout.nodes.first(where: { $0.path == "$" }))
        let child = try XCTUnwrap(layout.nodes.first(where: { $0.path == "$.userTokenServer" }))
        let edge = try XCTUnwrap(layout.edges.first(where: { $0.toID == "$.userTokenServer" }))
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: 1)
        let labelFrame = RNVJsonGraphEdgeLabelLayout.frame(
            for: edge,
            font: style.edgeLabelFont(),
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )

        XCTAssertGreaterThanOrEqual(labelFrame.minX - parent.frame.maxX, 8)
        XCTAssertGreaterThanOrEqual(child.frame.minX - labelFrame.maxX, 8)
    }

    @MainActor
    func testJsonGraphLayoutKeepsExtraLongEdgeLabelsClearOfConnectedNodes() throws {
        let key = "userTokenServerAuthorizationContextMetadataPayload"
        let json = """
        {
          "\(key)": {
            "deptId": "5176",
            "userId": "17107",
            "roleId": "918"
          }
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 20)
        let layout = JsonGraphLayoutBuilder.build(from: document)
        let parent = try XCTUnwrap(layout.nodes.first(where: { $0.path == "$" }))
        let childPath = "$.\(key)"
        let child = try XCTUnwrap(layout.nodes.first(where: { $0.path == childPath }))
        let edge = try XCTUnwrap(layout.edges.first(where: { $0.toID == childPath }))
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: 1)
        let labelFrame = RNVJsonGraphEdgeLabelLayout.frame(
            for: edge,
            font: style.edgeLabelFont(),
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )

        XCTAssertGreaterThanOrEqual(labelFrame.minX - parent.frame.maxX, 8)
        XCTAssertGreaterThanOrEqual(child.frame.minX - labelFrame.maxX, 8)
    }

    @MainActor
    func testJsonGraphLayoutSeparatesSiblingEdgeLabelsVertically() throws {
        let json = """
        {
          "title": "Tong so van ban den",
          "parentId": 1
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 10)
        let layout = JsonGraphLayoutBuilder.build(from: document)
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: 1)

        let titleEdge = try XCTUnwrap(layout.edges.first(where: { $0.toID == "$.title" }))
        let parentIDEdge = try XCTUnwrap(layout.edges.first(where: { $0.toID == "$.parentId" }))

        let titleFrame = RNVJsonGraphEdgeLabelLayout.frame(
            for: titleEdge,
            font: style.edgeLabelFont(),
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )
        let parentIDFrame = RNVJsonGraphEdgeLabelLayout.frame(
            for: parentIDEdge,
            font: style.edgeLabelFont(),
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )

        XCTAssertFalse(titleFrame.intersects(parentIDFrame))
    }

    @MainActor
    func testJsonGraphEdgeLabelStaysFullyAboveConnectedLine() {
        let edge = JsonGraphLayoutEdge(
            id: "edge",
            fromID: "parent",
            toID: "child",
            fromPoint: CGPoint(x: 120, y: 180),
            toPoint: CGPoint(x: 320, y: 240),
            label: "userTokenServerAuthorizationContextMetadataPayload"
        )
        let style = RNVJsonGraphSceneDrawingStyle(zoomScale: 2.2)
        let labelFrame = RNVJsonGraphEdgeLabelLayout.frame(
            for: edge,
            font: style.edgeLabelFont(),
            horizontalPadding: style.edgeLabelHorizontalPadding,
            verticalPadding: style.edgeLabelVerticalPadding
        )

        XCTAssertLessThanOrEqual(labelFrame.maxY, edge.toPoint.y - 4)
    }

    func testJsonGraphLayoutKeepsMinimumVerticalGapBetweenSiblingNodes() throws {
        let json = """
        {
          "nonce": "nonce",
          "token": "token",
          "consumerKey": "consumer",
          "userName": "huong",
          "deviceId": "devmobile",
          "roleId": "918",
          "userTokenServer": {
            "deptId": "5176",
            "userId": "17107",
            "roleId": "918"
          },
          "fromDate": "2026-04-20T00:00:00.000Z",
          "toDate": "2026-04-26T23:59:59.999Z",
          "filterType": 10,
          "deptCalendarId": 5176
        }
        """

        let document = try JsonGraphBuilder.build(from: json, nodeLimit: 40)
        let layout = JsonGraphLayoutBuilder.build(from: document)
        let depthOneNodes = layout.nodes
            .filter { $0.depth == 1 }
            .sorted { $0.frame.minY < $1.frame.minY }
        let siblingGaps = zip(depthOneNodes, depthOneNodes.dropFirst()).map { nextPair in
            nextPair.1.frame.minY - nextPair.0.frame.maxY
        }

        XCTAssertFalse(siblingGaps.isEmpty)
        XCTAssertGreaterThanOrEqual(siblingGaps.min() ?? 0, 32)
    }

    func testJsonGraphSelectionDetailBuildsStructuredMetadataFromNodeAndAncestors() {
        let leaf = JsonGraphNode(
            path: "$.profile.username",
            edgeLabel: "username",
            kind: .string,
            preview: "\"abc\""
        )
        let parent = JsonGraphNode(
            path: "$.profile",
            edgeLabel: "profile",
            kind: .object,
            preview: "1 key(s)",
            children: [leaf]
        )
        let root = JsonGraphNode(
            path: "$",
            edgeLabel: nil,
            kind: .object,
            preview: "1 key(s)",
            children: [parent]
        )

        let detail = JsonGraphSelectionDetail(node: leaf, ancestors: [root, parent])

        XCTAssertEqual(detail.propertyName, "username")
        XCTAssertEqual(detail.dataType, "String")
        XCTAssertEqual(detail.simpleGraph, "Root -> profile -> username")
        XCTAssertEqual(detail.valueContent, .scalar("\"abc\""))
    }

    func testJsonGraphSelectionDetailBuildsExpandableOneLevelPreviewForObjectNode() {
        let school = JsonGraphNode(
            path: "$.profile.school",
            edgeLabel: "school",
            kind: .object,
            preview: "2 key(s)",
            children: [
                JsonGraphNode(path: "$.profile.school.name", edgeLabel: "name", kind: .string, preview: "\"NST\""),
                JsonGraphNode(path: "$.profile.school.code", edgeLabel: "code", kind: .number, preview: "123")
            ]
        )
        let profile = JsonGraphNode(
            path: "$.profile",
            edgeLabel: "profile",
            kind: .object,
            preview: "3 key(s)",
            children: [
                JsonGraphNode(path: "$.profile.username", edgeLabel: "username", kind: .string, preview: "\"abc\""),
                JsonGraphNode(path: "$.profile.password", edgeLabel: "password", kind: .number, preview: "123"),
                school
            ]
        )
        let root = JsonGraphNode(
            path: "$",
            edgeLabel: nil,
            kind: .object,
            preview: "1 key(s)",
            children: [profile]
        )

        let detail = JsonGraphSelectionDetail(node: profile, ancestors: [root])

        XCTAssertEqual(detail.propertyName, "profile")
        XCTAssertEqual(detail.dataType, "Object")
        XCTAssertEqual(detail.simpleGraph, "Root -> profile")
        XCTAssertEqual(
            detail.valueContent,
            .structured(
                openingToken: "{",
                closingToken: "}",
                entries: [
                    JsonGraphSelectionValueEntry(label: "username", renderedValue: "\"abc\"", expandableNodeID: nil),
                    JsonGraphSelectionValueEntry(label: "password", renderedValue: "123", expandableNodeID: nil),
                    JsonGraphSelectionValueEntry(label: "school", renderedValue: "{...}", expandableNodeID: "$.profile.school")
                ]
            )
        )
    }

    func testJsonGraphPanMathMovesViewportWithExpectedAxisDirectionsAndClampsBounds() {
        let moved = JsonGraphPanMath.nextOrigin(
            currentOrigin: CGPoint(x: 60, y: 40),
            translation: CGSize(width: 20, height: -15),
            contentSize: CGSize(width: 500, height: 400),
            viewportSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(moved.x, 40, accuracy: 0.001)
        XCTAssertEqual(moved.y, 25, accuracy: 0.001)

        let clamped = JsonGraphPanMath.nextOrigin(
            currentOrigin: CGPoint(x: 5, y: 8),
            translation: CGSize(width: 30, height: -50),
            contentSize: CGSize(width: 500, height: 400),
            viewportSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(clamped.x, 0, accuracy: 0.001)
        XCTAssertEqual(clamped.y, 0, accuracy: 0.001)
    }

    func testJsonGraphPanGestureMathUsesStableWindowCoordinates() {
        let translation = JsonGraphPanGestureMath.translation(
            previousWindowLocation: CGPoint(x: 120, y: 80),
            currentWindowLocation: CGPoint(x: 145, y: 62)
        )

        XCTAssertEqual(translation.width, 25, accuracy: 0.001)
        XCTAssertEqual(translation.height, -18, accuracy: 0.001)
    }

    func testJsonGraphZoomMathOnlyZoomsWhenControlIsPressed() {
        XCTAssertNil(
            JsonGraphZoomMath.nextScale(
                currentScale: 1,
                scrollDeltaY: 4,
                isControlPressed: false
            )
        )

        let zoomedIn = JsonGraphZoomMath.nextScale(
            currentScale: 1,
            scrollDeltaY: 4,
            isControlPressed: true
        )

        XCTAssertNotNil(zoomedIn)
        XCTAssertGreaterThan(zoomedIn ?? 0, 1)
    }

    func testJsonGraphZoomAnchorMathKeepsCursorTargetStableAcrossZoom() {
        let nextOrigin = JsonGraphZoomAnchorMath.nextOrigin(
            currentOrigin: CGPoint(x: 100, y: 50),
            viewportPoint: CGPoint(x: 200, y: 100),
            currentScale: 1,
            nextScale: 1.2,
            contentSize: CGSize(width: 1200, height: 900),
            viewportSize: CGSize(width: 400, height: 300)
        )

        XCTAssertEqual(nextOrigin.x, 160, accuracy: 0.001)
        XCTAssertEqual(nextOrigin.y, 80, accuracy: 0.001)
    }

    func testJsonGraphTabHidesWorkspaceHeader() {
        XCTAssertFalse(DebuggerLogTab.jsonGraph.showsWorkspaceHeader)
        XCTAssertTrue(DebuggerLogTab.console.showsWorkspaceHeader)
    }

    func testConsoleScrollMetricsOnlyPinWhenBottomAnchorIsReallyAtBottom() {
        XCTAssertTrue(
            ConsoleScrollMetrics.pinnedState(
                currentlyPinned: false,
                contentHeight: 1000,
                visibleHeight: 200,
                visibleMaxY: 1000,
                changeSource: .scrollPosition
            )
        )
        XCTAssertTrue(
            ConsoleScrollMetrics.pinnedState(
                currentlyPinned: false,
                contentHeight: 1000,
                visibleHeight: 200,
                visibleMaxY: 984,
                changeSource: .scrollPosition
            )
        )
        XCTAssertFalse(
            ConsoleScrollMetrics.pinnedState(
                currentlyPinned: false,
                contentHeight: 1000,
                visibleHeight: 200,
                visibleMaxY: 983,
                changeSource: .scrollPosition
            )
        )
    }

    func testConsoleScrollMetricsKeepFollowTailWhenContentGrowsAtBottom() {
        XCTAssertTrue(
            ConsoleScrollMetrics.pinnedState(
                currentlyPinned: true,
                contentHeight: 1040,
                visibleHeight: 200,
                visibleMaxY: 1000,
                changeSource: .contentSize
            )
        )
        XCTAssertFalse(
            ConsoleScrollMetrics.pinnedState(
                currentlyPinned: false,
                contentHeight: 1040,
                visibleHeight: 200,
                visibleMaxY: 1000,
                changeSource: .contentSize
            )
        )
    }

    func testConsoleDebuggerFiltersActualNetworkRequests() {
        let requests = [
            NetworkRequestEntry(
                id: "request-1",
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                method: "GET",
                url: "https://example.com/api/profile"
            ),
            NetworkRequestEntry(
                id: "request-2",
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                method: "POST",
                url: "https://example.com/api/documents",
                statusCode: 500,
                failureText: "Request failed"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(networkRequests: requests)
        viewModel.setDraftSearchText("documents", for: .network)

        XCTAssertEqual(viewModel.filteredNetworkRequests.map(\.id), ["request-2"])
    }

    func testConsoleDebuggerKeepsSearchTermsScopedPerTab() {
        let logs = [
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_111),
                level: .log,
                message: "Booted React Native bridge",
                source: "App.tsx"
            ),
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_112),
                level: .warn,
                message: "Cache miss",
                source: "src/network/client.ts"
            )
        ]
        let requests = [
            NetworkRequestEntry(
                id: "request-1",
                timestamp: Date(timeIntervalSince1970: 1_711_111_113),
                method: "GET",
                url: "https://example.com/api/profile"
            ),
            NetworkRequestEntry(
                id: "request-2",
                timestamp: Date(timeIntervalSince1970: 1_711_111_114),
                method: "POST",
                url: "https://example.com/api/documents"
            )
        ]

        let viewModel = ConsoleDebuggerViewModel(logs: logs, networkRequests: requests)
        viewModel.searchText = "bridge"
        viewModel.addSearchTermFromDraft(for: .console)
        viewModel.setDraftSearchText("documents", for: .network)
        viewModel.addSearchTermFromDraft(for: .network)

        XCTAssertEqual(viewModel.searchTerms, ["bridge"])
        XCTAssertEqual(viewModel.pinnedSearchTerms(for: .network), ["documents"])
        XCTAssertEqual(viewModel.filteredLogs.map(\.message), ["Booted React Native bridge"])
        XCTAssertEqual(viewModel.filteredNetworkRequests.map(\.id), ["request-2"])
    }

    func testConsoleTimestampFormatterShowsTimeOnlyForTodayEntries() {
        let timeZone = TimeZone(secondsFromGMT: 7 * 60 * 60)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let locale = Locale(identifier: "en_US_POSIX")

        let now = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 26,
            hour: 10,
            minute: 0,
            second: 0
        ))!
        let sameDayLog = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 26,
            hour: 9,
            minute: 25,
            second: 13
        ))!

        XCTAssertEqual(
            ConsoleTimestampFormatter.string(
                for: sameDayLog,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "09:25:13"
        )
    }

    func testConsoleTimestampFormatterIncludesDateForOlderEntries() {
        let timeZone = TimeZone(secondsFromGMT: 7 * 60 * 60)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let locale = Locale(identifier: "en_US_POSIX")

        let now = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 26,
            hour: 10,
            minute: 0,
            second: 0
        ))!
        let previousDayLog = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 25,
            hour: 14,
            minute: 36,
            second: 13
        ))!

        XCTAssertEqual(
            ConsoleTimestampFormatter.string(
                for: previousDayLog,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "25 Mar 14:36:13"
        )
    }

    func testConsoleDebuggerReplaceLogsPublishesChanges() {
        let viewModel = ConsoleDebuggerViewModel()
        let expectation = expectation(description: "replaceLogs publishes changes")
        expectation.expectedFulfillmentCount = 1

        var cancellable: AnyCancellable?
        cancellable = viewModel.objectWillChange.sink {
            expectation.fulfill()
        }

        viewModel.replaceLogs([
            ConsoleLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_711_111_114),
                level: .info,
                message: "Connected to Hermes target",
                source: "Console"
            )
        ])

        wait(for: [expectation], timeout: 0.2)
        cancellable?.cancel()
    }

    func testDevtoolsConsoleSessionClearLogsRemovesStoredEntries() {
        let candidate = DevtoolsConnectionCandidate(
            displayName: "Test Device",
            detailText: "Hermes Console",
            webSocketURL: URL(string: "ws://localhost:8081/inspector/debug?device=test&page=1")!
        )
        let session = DevtoolsConsoleSession(
            candidate: candidate,
            initialLogs: [
                ConsoleLogEntry(
                    timestamp: Date(timeIntervalSince1970: 1_711_111_114),
                    level: .info,
                    message: "Connected to Hermes target",
                    source: "Console"
                ),
                ConsoleLogEntry(
                    timestamp: Date(timeIntervalSince1970: 1_711_111_115),
                    level: .warn,
                    message: "VirtualizedList slow update",
                    source: "src/screens/Home.tsx"
                )
            ]
        )

        XCTAssertEqual(session.logs.count, 2)

        session.clearLogs()

        XCTAssertTrue(session.logs.isEmpty)
    }

    func testConsoleLogEntryCollapsesOnlyLongWarnAndErrorMessages() {
        let longWarningMessage = String(repeating: "W", count: 180)
        let longInfoMessage = String(repeating: "I", count: 180)

        let warningEntry = ConsoleLogEntry(level: .warn, message: longWarningMessage, source: "warn.js")
        let errorEntry = ConsoleLogEntry(level: .error, message: longWarningMessage, source: "error.js")
        let infoEntry = ConsoleLogEntry(level: .info, message: longInfoMessage, source: "info.js")

        XCTAssertTrue(warningEntry.isCollapsible)
        XCTAssertTrue(errorEntry.isCollapsible)
        XCTAssertFalse(infoEntry.isCollapsible)
    }

    func testConsoleLogEntryCollapsedMessageUsesThresholdAndEllipsis() {
        let longMessage = String(repeating: "A", count: 170)
        let entry = ConsoleLogEntry(level: .warn, message: longMessage, source: "warn.js")

        XCTAssertEqual(entry.displayMessage(isExpanded: false).count, 153)
        XCTAssertTrue(entry.displayMessage(isExpanded: false).hasSuffix("..."))
        XCTAssertEqual(entry.displayMessage(isExpanded: true), longMessage)
    }

    func testParseRuntimeConsoleAPICalledNotificationProducesConsoleLogEntry() throws {
        let payload = """
        {
          "method": "Runtime.consoleAPICalled",
          "params": {
            "type": "warning",
            "timestamp": 1711111111.25,
            "args": [
              {
                "type": "string",
                "value": "VirtualizedList slow update"
              }
            ],
            "stackTrace": {
              "callFrames": [
                {
                  "functionName": "render",
                  "scriptId": "12",
                  "url": "src/screens/Home.tsx",
                  "lineNumber": 21,
                  "columnNumber": 4
                }
              ]
            }
          }
        }
        """

        let entry = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNotification(Data(payload.utf8))
        )

        XCTAssertEqual(entry.level, .warn)
        XCTAssertEqual(entry.message, "VirtualizedList slow update")
        XCTAssertEqual(entry.source, "src/screens/Home.tsx")
    }

    func testParseRuntimeConsoleAPICalledNotificationSupportsMillisecondEpochTimestamp() throws {
        let payload = """
        {
          "method": "Runtime.consoleAPICalled",
          "params": {
            "type": "log",
            "timestamp": 1774486923123,
            "args": [
              {
                "type": "string",
                "value": "Rendered current screen"
              }
            ]
          }
        }
        """

        let entry = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNotification(Data(payload.utf8))
        )

        XCTAssertEqual(entry.message, "Rendered current screen")
        XCTAssertEqual(entry.timestamp.timeIntervalSince1970, 1_774_486_923.123, accuracy: 0.001)
    }

    func testParseRuntimeConsoleAPICalledNotificationFallsBackForImplausibleTimestamp() throws {
        let payload = """
        {
          "method": "Runtime.consoleAPICalled",
          "params": {
            "type": "log",
            "timestamp": 11600000,
            "args": [
              {
                "type": "string",
                "value": "Buffered log entry"
              }
            ]
          }
        }
        """

        let beforeParsing = Date()
        let entry = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNotification(Data(payload.utf8))
        )
        let afterParsing = Date()

        XCTAssertGreaterThanOrEqual(entry.timestamp, beforeParsing)
        XCTAssertLessThanOrEqual(entry.timestamp, afterParsing)
    }

    func testParseRuntimeConsoleAPICalledNotificationRendersPlainObjectsAsBracePreview() throws {
        let payload = """
        {
          "method": "Runtime.consoleAPICalled",
          "params": {
            "type": "log",
            "timestamp": 1711111111.25,
            "args": [
              {
                "type": "object",
                "className": "Object",
                "description": "Object",
                "objectId": "123.1.1"
              }
            ]
          }
        }
        """

        let entry = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNotification(Data(payload.utf8))
        )

        XCTAssertEqual(entry.message, "{...}")
    }

    func testParseLogEntryAddedNotificationProducesConsoleLogEntry() throws {
        let payload = """
        {
          "method": "Log.entryAdded",
          "params": {
            "entry": {
              "source": "javascript",
              "level": "error",
              "text": "Unhandled promise rejection",
              "timestamp": 1711111112.5,
              "url": "src/api/client.ts",
              "lineNumber": 88
            }
          }
        }
        """

        let entry = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNotification(Data(payload.utf8))
        )

        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.message, "Unhandled promise rejection")
        XCTAssertEqual(entry.source, "src/api/client.ts")
    }

    func testParseConsoleMessageAddedNotificationProducesConsoleLogEntry() throws {
        let payload = """
        {
          "method": "Console.messageAdded",
          "params": {
            "message": {
              "source": "console-api",
              "level": "log",
              "text": "Mounted app root",
              "url": "src/App.tsx",
              "line": 12,
              "column": 4
            }
          }
        }
        """

        let entry = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNotification(Data(payload.utf8))
        )

        XCTAssertEqual(entry.level, .log)
        XCTAssertEqual(entry.message, "Mounted app root")
        XCTAssertEqual(entry.source, "src/App.tsx")
    }

    func testParseNetworkRequestWillBeSentProducesNetworkRequestEvent() throws {
        let payload = """
        {
          "method": "Network.requestWillBeSent",
          "params": {
            "requestId": "request-1",
            "timestamp": 1711111112.5,
            "type": "XHR",
            "request": {
              "url": "https://example.com/api/profile",
              "method": "GET",
              "headers": {
                "Accept": "application/json"
              }
            }
          }
        }
        """

        let event = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNetworkNotification(Data(payload.utf8))
        )

        switch event {
        case .requestWillBeSent(let requestId, let timestamp, let method, let url, let headers, _, let resourceType):
            XCTAssertEqual(requestId, "request-1")
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(url, "https://example.com/api/profile")
            XCTAssertEqual(headers["Accept"], "application/json")
            XCTAssertEqual(resourceType, "XHR")
            XCTAssertEqual(timestamp.timeIntervalSince1970, 1_711_111_112.5, accuracy: 0.001)
        default:
            XCTFail("Expected requestWillBeSent event")
        }
    }

    func testParseNetworkResponseReceivedProducesNetworkRequestEvent() throws {
        let payload = """
        {
          "method": "Network.responseReceived",
          "params": {
            "requestId": "request-1",
            "timestamp": 1711111113.5,
            "type": "XHR",
            "response": {
              "status": 200,
              "statusText": "OK",
              "mimeType": "application/json",
              "headers": {
                "Content-Type": "application/json"
              }
            }
          }
        }
        """

        let event = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseNetworkNotification(Data(payload.utf8))
        )

        switch event {
        case .responseReceived(let requestId, let timestamp, let statusCode, let statusText, let mimeType, let headers, let resourceType):
            XCTAssertEqual(requestId, "request-1")
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(statusText, "OK")
            XCTAssertEqual(mimeType, "application/json")
            XCTAssertEqual(headers["Content-Type"], "application/json")
            XCTAssertEqual(resourceType, "XHR")
            XCTAssertEqual(timestamp.timeIntervalSince1970, 1_711_111_113.5, accuracy: 0.001)
        default:
            XCTFail("Expected responseReceived event")
        }
    }

    func testParseCommandResponseReturnsErrorForUnsupportedNetworkDomain() throws {
        let payload = """
        {
          "id": 4,
          "error": {
            "code": -32601,
            "message": "Method not found"
          }
        }
        """

        let response = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseCommandResponse(Data(payload.utf8))
        )

        XCTAssertEqual(response.id, 4)
        XCTAssertEqual(response.errorMessage, "Method not found")
    }

    func testParseCommandResponseReturnsSuccessForCompletedCommand() throws {
        let payload = """
        {
          "id": 4,
          "result": {}
        }
        """

        let response = try XCTUnwrap(
            DevtoolsConsoleEventParser.parseCommandResponse(Data(payload.utf8))
        )

        XCTAssertEqual(response.id, 4)
        XCTAssertNil(response.errorMessage)
    }

    func testParseRNVNetworkSDKEnvelopeProducesStructuredEvents() throws {
        let payload = """
        {
          "sdk": {
            "name": "rnv_network_sdk_ios",
            "version": "0.1.0",
            "schemaVersion": 1
          },
          "session": {
            "id": "session-1",
            "platform": "ios",
            "bundleIdentifier": "com.example.viewerhost",
            "appName": "Viewer Host",
            "deviceName": "iPhone 13",
            "systemName": "iOS",
            "systemVersion": "18.0",
            "isSimulator": true
          },
          "events": [
            {
              "schemaVersion": 1,
              "platform": "ios",
              "timestamp": "2026-04-17T09:00:00Z",
              "requestId": "fetch-1",
              "phase": "request",
              "source": "js.fetch",
              "request": {
                "method": "POST",
                "url": "https://example.com/api/login",
                "headers": {
                  "Content-Type": "application/json"
                },
                "body": "{\\"username\\":\\"demo\\",\\"password\\":\\"secret\\"}",
                "bodyPreview": "{\\"username\\":\\"demo\\"}",
                "requestKind": "fetch"
              },
              "startedAt": 1776416400000
            },
            {
              "schemaVersion": 1,
              "platform": "ios",
              "timestamp": "2026-04-17T09:00:00.120Z",
              "requestId": "fetch-1",
              "phase": "response",
              "source": "js.fetch",
              "durationMs": 120,
              "response": {
                "statusCode": 200,
                "statusText": "OK",
                "headers": {
                  "Content-Type": "application/json"
                },
                "body": "{\\"token\\":\\"abc\\",\\"refreshToken\\":\\"def\\"}",
                "bodyPreview": "{\\"token\\":\\"abc\\"}"
              }
            }
          ]
        }
        """

        let envelope = try XCTUnwrap(
            RNVNetworkSDKEnvelopeParser.parseEnvelope(Data(payload.utf8))
        )

        XCTAssertEqual(envelope.session.bundleIdentifier, "com.example.viewerhost")
        XCTAssertEqual(envelope.session.deviceName, "iPhone 13")
        XCTAssertEqual(envelope.events.count, 2)

        let requestEvent = envelope.events[0]
        XCTAssertEqual(requestEvent.requestId, "fetch-1")
        XCTAssertEqual(requestEvent.phase, .request)
        XCTAssertEqual(requestEvent.method, "POST")
        XCTAssertEqual(requestEvent.url, "https://example.com/api/login")
        XCTAssertEqual(requestEvent.requestHeaders["Content-Type"], "application/json")
        XCTAssertEqual(requestEvent.requestBody, "{\"username\":\"demo\",\"password\":\"secret\"}")
        XCTAssertEqual(requestEvent.requestBodyPreview, "{\"username\":\"demo\"}")

        let responseEvent = envelope.events[1]
        XCTAssertEqual(responseEvent.phase, .response)
        XCTAssertEqual(responseEvent.statusCode, 200)
        XCTAssertEqual(responseEvent.statusText, "OK")
        XCTAssertEqual(responseEvent.responseBody, "{\"token\":\"abc\",\"refreshToken\":\"def\"}")
        XCTAssertEqual(responseEvent.responseBodyPreview, "{\"token\":\"abc\"}")
        XCTAssertEqual(responseEvent.durationMs, 120)
    }

    func testDevtoolsConsoleSessionApplySDKEnvelopeBuildsNetworkRequestRows() throws {
        let candidate = DevtoolsConnectionCandidate(
            displayName: "Test Device",
            detailText: "Hermes Console",
            webSocketURL: URL(string: "ws://localhost:8081/inspector/debug?device=test&page=1")!
        )
        let session = DevtoolsConsoleSession(candidate: candidate)

        let payload = """
        {
          "session": {
            "id": "session-1",
            "platform": "ios",
            "bundleIdentifier": "com.example.viewerhost",
            "appName": "Viewer Host",
            "deviceName": "iPhone 13",
            "systemName": "iOS",
            "systemVersion": "18.0",
            "isSimulator": true
          },
          "events": [
            {
              "schemaVersion": 1,
              "platform": "ios",
              "timestamp": "2026-04-17T09:00:00Z",
              "requestId": "xhr-1",
              "phase": "request",
              "source": "js.xhr",
              "request": {
                "method": "PUT",
                "url": "https://example.com/api/profile",
                "headers": {
                  "Content-Type": "application/json"
                },
                "body": "{\\"name\\":\\"Codex\\",\\"role\\":\\"assistant\\"}",
                "bodyPreview": "{\\"name\\":\\"Codex\\"}",
                "requestKind": "xhr"
              }
            },
            {
              "schemaVersion": 1,
              "platform": "ios",
              "timestamp": "2026-04-17T09:00:00.450Z",
              "requestId": "xhr-1",
              "phase": "response",
              "source": "js.xhr",
              "durationMs": 450,
              "response": {
                "statusCode": 201,
                "statusText": "Created",
                "headers": {
                  "Content-Type": "application/json"
                },
                "body": "{\\"ok\\":true,\\"id\\":123}",
                "bodyPreview": "{\\"ok\\":true}"
              }
            }
          ]
        }
        """

        let envelope = try XCTUnwrap(
            RNVNetworkSDKEnvelopeParser.parseEnvelope(Data(payload.utf8))
        )

        session.applySDKEnvelope(envelope)

        XCTAssertEqual(session.networkRequests.count, 1)

        let entry = try XCTUnwrap(session.networkRequests.first)
        XCTAssertEqual(entry.method, "PUT")
        XCTAssertEqual(entry.url, "https://example.com/api/profile")
        XCTAssertEqual(entry.statusCode, 201)
        XCTAssertEqual(entry.statusText, "Created")
        XCTAssertEqual(entry.requestHeaders["Content-Type"], "application/json")
        XCTAssertEqual(entry.requestBody, "{\"name\":\"Codex\",\"role\":\"assistant\"}")
        XCTAssertEqual(entry.responseBody, "{\"ok\":true,\"id\":123}")
        XCTAssertEqual(entry.durationMs, 450)
    }

    func testWorkspaceSessionStoreConnectsSessionAndSelectsIt() {
        let store = WorkspaceSessionStore()
        let firstSession = makeWorkspaceSession(
            name: "Device 1",
            webSocketURL: "ws://localhost:8081/inspector/debug?device=device-1&page=1"
        )

        store.connect(firstSession)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSession?.id, firstSession.id)
    }

    func testWorkspaceSessionStoreShowHomeKeepsConnectedSessions() {
        let store = WorkspaceSessionStore()
        let firstSession = makeWorkspaceSession(
            name: "Device 1",
            webSocketURL: "ws://localhost:8081/inspector/debug?device=device-1&page=1"
        )

        store.connect(firstSession)
        store.showHome()

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNil(store.activeSession)
    }

    func testWorkspaceSessionStoreDisconnectRemovesSessionAndReturnsHome() {
        let store = WorkspaceSessionStore()
        let firstSession = makeWorkspaceSession(
            name: "Device 1",
            webSocketURL: "ws://localhost:8081/inspector/debug?device=device-1&page=1"
        )

        store.connect(firstSession)
        store.disconnect(firstSession)

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.activeSession)
    }

    func testWorkspaceSessionStoreRoutesSDKEnvelopesToMatchingSessionsWithoutCrossContamination() async {
        let envelopeSubject = PassthroughSubject<RNVNetworkSDKEnvelope, Never>()
        let clientStatesSubject = CurrentValueSubject<[String: RNVNetworkSDKClientState], Never>([:])
        let store = WorkspaceSessionStore(
            sdkEnvelopePublisher: envelopeSubject.eraseToAnyPublisher(),
            sdkClientStatesPublisher: clientStatesSubject.eraseToAnyPublisher()
        )

        let firstSession = makeWorkspaceSession(
            name: "com.example.first (iPhone 13)",
            webSocketURL: "ws://localhost:8081/inspector/debug?device=device-1&page=1"
        )
        let secondSession = makeWorkspaceSession(
            name: "com.example.second (Pixel 8)",
            webSocketURL: "ws://localhost:8081/inspector/debug?device=device-2&page=1"
        )

        store.connect(firstSession)
        store.connect(secondSession)

        envelopeSubject.send(
            makeSDKEnvelope(
                sessionID: "sdk-session-1",
                bundleIdentifier: "com.example.first",
                appName: "First App",
                deviceName: "iPhone 13",
                requestID: "request-1",
                url: "https://example.com/first"
            )
        )
        envelopeSubject.send(
            makeSDKEnvelope(
                sessionID: "sdk-session-2",
                bundleIdentifier: "com.example.second",
                appName: "Second App",
                deviceName: "Pixel 8",
                requestID: "request-2",
                url: "https://example.com/second"
            )
        )

        await waitForMainQueue()

        XCTAssertEqual(firstSession.networkRequests.count, 1)
        XCTAssertEqual(firstSession.networkRequests.first?.url, "https://example.com/first")
        XCTAssertEqual(secondSession.networkRequests.count, 1)
        XCTAssertEqual(secondSession.networkRequests.first?.url, "https://example.com/second")
    }

    private func makeWorkspaceSession(name: String, webSocketURL: String) -> DevtoolsConsoleSession {
        DevtoolsConsoleSession(
            candidate: DevtoolsConnectionCandidate(
                displayName: name,
                detailText: "Hermes",
                webSocketURL: URL(string: webSocketURL)!
            )
        )
    }

    private func makeSDKEnvelope(
        sessionID: String,
        bundleIdentifier: String,
        appName: String,
        deviceName: String,
        requestID: String,
        url: String
    ) -> RNVNetworkSDKEnvelope {
        RNVNetworkSDKEnvelope(
            session: RNVNetworkSDKSession(
                id: sessionID,
                platform: "ios",
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                deviceName: deviceName,
                systemName: "iOS",
                systemVersion: "18.0",
                isSimulator: true
            ),
            events: [
                RNVNetworkSDKEvent(
                    requestId: requestID,
                    phase: .request,
                    source: "js.fetch",
                    timestamp: Date(timeIntervalSince1970: 1_776_416_400),
                    method: "GET",
                    url: url,
                    requestHeaders: [:],
                    requestBody: nil,
                    requestBodyPreview: nil,
                    requestKind: "fetch",
                    statusCode: nil,
                    statusText: nil,
                    responseHeaders: [:],
                    responseBody: nil,
                    responseBodyPreview: nil,
                    durationMs: nil,
                    errorMessage: nil
                )
            ]
        )
    }

    private func waitForMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
