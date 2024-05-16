import AppKit
import Foundation

public struct WidgetLocation: Equatable {
    struct PanelLocation: Equatable {
        var frame: CGRect
        var alignPanelTop: Bool
    }

    var widgetFrame: CGRect
    var tabFrame: CGRect
    var defaultPanelLocation: PanelLocation
    var suggestionPanelLocation: PanelLocation?
}

enum UpdateLocationStrategy {
    struct AlignToTextCursor {
        func framesForWindows(
            editorFrame: CGRect,
            mainScreen: NSScreen,
            activeScreen: NSScreen,
            editor: AXUIElement,
            hideCircularWidget: Bool = true,
            preferredInsideEditorMinWidth: Double = 999999
        ) -> WidgetLocation {
            guard let selectedRange: AXValue = try? editor
                .copyValue(key: kAXSelectedTextRangeAttribute),
                let rect: AXValue = try? editor.copyParameterizedValue(
                    key: kAXBoundsForRangeParameterizedAttribute,
                    parameters: selectedRange
                )
            else {
                return FixedToBottom().framesForWindows(
                    editorFrame: editorFrame,
                    mainScreen: mainScreen,
                    activeScreen: activeScreen,
                    hideCircularWidget: hideCircularWidget
                )
            }
            var frame: CGRect = .zero
            let found = AXValueGetValue(rect, .cgRect, &frame)
            guard found else {
                return FixedToBottom().framesForWindows(
                    editorFrame: editorFrame,
                    mainScreen: mainScreen,
                    activeScreen: activeScreen,
                    hideCircularWidget: hideCircularWidget
                )
            }
            return HorizontalMovable().framesForWindows(
                y: mainScreen.frame.height - frame.maxY,
                alignPanelTopToAnchor: nil,
                editorFrame: editorFrame,
                mainScreen: mainScreen,
                activeScreen: activeScreen,
                preferredInsideEditorMinWidth: preferredInsideEditorMinWidth,
                hideCircularWidget: hideCircularWidget
            )
        }
    }

    struct FixedToBottom {
        func framesForWindows(
            editorFrame: CGRect,
            mainScreen: NSScreen,
            activeScreen: NSScreen,
            hideCircularWidget: Bool = true,
            preferredInsideEditorMinWidth: Double = 999999999,
            editorFrameExpendedSize: CGSize = .zero
        ) -> WidgetLocation {
            return HorizontalMovable().framesForWindows(
                y: mainScreen.frame.height - editorFrame.maxY + Style.widgetPadding,
                alignPanelTopToAnchor: false,
                editorFrame: editorFrame,
                mainScreen: mainScreen,
                activeScreen: activeScreen,
                preferredInsideEditorMinWidth: preferredInsideEditorMinWidth,
                hideCircularWidget: hideCircularWidget,
                editorFrameExpendedSize: editorFrameExpendedSize
            )
        }
    }

    struct HorizontalMovable {
        func framesForWindows(
            y: CGFloat,
            alignPanelTopToAnchor fixedAlignment: Bool?,
            editorFrame: CGRect,
            mainScreen: NSScreen,
            activeScreen: NSScreen,
            preferredInsideEditorMinWidth: Double,
            hideCircularWidget: Bool = true,
            editorFrameExpendedSize: CGSize = .zero
        ) -> WidgetLocation {
            let maxY = max(
                y,
                mainScreen.frame.height - editorFrame.maxY + Style.widgetPadding,
                4 + activeScreen.frame.minY
            )
            let y = min(
                maxY,
                activeScreen.frame.maxY - 4,
                mainScreen.frame.height - editorFrame.minY - Style.widgetHeight - Style
                    .widgetPadding
            )

            var proposedAnchorFrameOnTheRightSide = CGRect(
                x: editorFrame.maxX - Style.widgetPadding,
                y: y,
                width: 0,
                height: 0
            )

            let widgetFrameOnTheRightSide = CGRect(
                x: editorFrame.maxX - Style.widgetPadding - Style.widgetWidth,
                y: y,
                width: Style.widgetWidth,
                height: Style.widgetHeight
            )

            if !hideCircularWidget {
                proposedAnchorFrameOnTheRightSide = widgetFrameOnTheRightSide
            }

            let proposedPanelX = proposedAnchorFrameOnTheRightSide.maxX
                + Style.widgetPadding * 2
                - editorFrameExpendedSize.width
            let putPanelToTheRight = {
                if editorFrame.size.width >= preferredInsideEditorMinWidth { return false }
                return activeScreen.frame.maxX > proposedPanelX + Style.panelWidth
            }()
            let alignPanelTopToAnchor = fixedAlignment ?? (y > activeScreen.frame.midY)

            if putPanelToTheRight {
                let anchorFrame = proposedAnchorFrameOnTheRightSide
                let panelFrame = CGRect(
                    x: proposedPanelX,
                    y: alignPanelTopToAnchor
                        ? anchorFrame.maxY - Style.panelHeight
                        : anchorFrame.minY - editorFrameExpendedSize.height,
                    width: Style.panelWidth,
                    height: Style.panelHeight
                )
                let tabFrame = CGRect(
                    x: anchorFrame.origin.x,
                    y: alignPanelTopToAnchor
                        ? anchorFrame.minY - Style.widgetHeight - Style.widgetPadding
                        : anchorFrame.maxY + Style.widgetPadding,
                    width: Style.widgetWidth,
                    height: Style.widgetHeight
                )

                return .init(
                    widgetFrame: widgetFrameOnTheRightSide,
                    tabFrame: tabFrame,
                    defaultPanelLocation: .init(
                        frame: panelFrame,
                        alignPanelTop: alignPanelTopToAnchor
                    ),
                    suggestionPanelLocation: nil
                )
            } else {
                var proposedAnchorFrameOnTheLeftSide = CGRect(
                    x: editorFrame.minX + Style.widgetPadding,
                    y: proposedAnchorFrameOnTheRightSide.origin.y,
                    width: 0,
                    height: 0
                )

                let widgetFrameOnTheLeftSide = CGRect(
                    x: editorFrame.minX + Style.widgetPadding,
                    y: proposedAnchorFrameOnTheRightSide.origin.y,
                    width: Style.widgetWidth,
                    height: Style.widgetHeight
                )

                if !hideCircularWidget {
                    proposedAnchorFrameOnTheLeftSide = widgetFrameOnTheLeftSide
                }

                let proposedPanelX = proposedAnchorFrameOnTheLeftSide.minX
                    - Style.widgetPadding * 2
                    - Style.panelWidth
                    + editorFrameExpendedSize.width
                let putAnchorToTheLeft = {
                    if editorFrame.size.width >= preferredInsideEditorMinWidth {
                        if editorFrame.maxX <= activeScreen.frame.maxX {
                            return false
                        }
                    }
                    return proposedPanelX > activeScreen.frame.minX
                }()

                if putAnchorToTheLeft {
                    let anchorFrame = proposedAnchorFrameOnTheLeftSide
                    let panelFrame = CGRect(
                        x: proposedPanelX,
                        y: alignPanelTopToAnchor
                            ? anchorFrame.maxY - Style.panelHeight
                            : anchorFrame.minY - editorFrameExpendedSize.height,
                        width: Style.panelWidth,
                        height: Style.panelHeight
                    )
                    let tabFrame = CGRect(
                        x: anchorFrame.origin.x,
                        y: alignPanelTopToAnchor
                            ? anchorFrame.minY - Style.widgetHeight - Style.widgetPadding
                            : anchorFrame.maxY + Style.widgetPadding,
                        width: Style.widgetWidth,
                        height: Style.widgetHeight
                    )
                    return .init(
                        widgetFrame: widgetFrameOnTheLeftSide,
                        tabFrame: tabFrame,
                        defaultPanelLocation: .init(
                            frame: panelFrame,
                            alignPanelTop: alignPanelTopToAnchor
                        ),
                        suggestionPanelLocation: nil
                    )
                } else {
                    let anchorFrame = proposedAnchorFrameOnTheRightSide
                    let panelFrame = CGRect(
                        x: anchorFrame.maxX - Style.panelWidth,
                        y: alignPanelTopToAnchor
                            ? anchorFrame.maxY - Style.panelHeight - Style.widgetHeight
                            - Style.widgetPadding
                            : anchorFrame.maxY + Style.widgetPadding
                            - editorFrameExpendedSize.height,
                        width: Style.panelWidth,
                        height: Style.panelHeight
                    )
                    let tabFrame = CGRect(
                        x: anchorFrame.minX - Style.widgetPadding - Style.widgetWidth,
                        y: anchorFrame.origin.y,
                        width: Style.widgetWidth,
                        height: Style.widgetHeight
                    )
                    return .init(
                        widgetFrame: widgetFrameOnTheRightSide,
                        tabFrame: tabFrame,
                        defaultPanelLocation: .init(
                            frame: panelFrame,
                            alignPanelTop: alignPanelTopToAnchor
                        ),
                        suggestionPanelLocation: nil
                    )
                }
            }
        }
    }

    struct NearbyTextCursor {
        func framesForSuggestionWindow(
            editorFrame: CGRect,
            mainScreen: NSScreen,
            activeScreen: NSScreen,
            editor: AXUIElement,
            completionPanel: AXUIElement?
        ) -> WidgetLocation.PanelLocation? {
            guard let selectionFrame = UpdateLocationStrategy
                .getSelectionFirstLineFrame(editor: editor) else { return nil }

            // hide it when the line of code is outside of the editor visible rect
            if selectionFrame.maxY < editorFrame.minY || selectionFrame.minY > editorFrame.maxY {
                return nil
            }

            let proposedY = mainScreen.frame.height - selectionFrame.maxY
            let proposedX = selectionFrame.maxX - 40
            let maxY = max(
                proposedY,
                4 + activeScreen.frame.minY
            )
            let y = min(
                maxY,
                activeScreen.frame.maxY - 4
            )

            // align panel to top == place under the selection frame.
            // we initially try to place it at the bottom side, but if there is no enough space
            // we move it to the top of the selection frame.
            let alignPanelTopToAnchor = y - Style.inlineSuggestionMaxHeight
                >= activeScreen.frame.minY

            let caseIgnoreCompletionPanel = {
                (alignPanelTopToAnchor: Bool) -> WidgetLocation.PanelLocation? in
                let x: Double = {
                    if proposedX + Style.inlineSuggestionMinWidth <= activeScreen.frame.maxX {
                        return proposedX
                    }
                    return activeScreen.frame.maxX - Style.inlineSuggestionMinWidth
                }()
                if alignPanelTopToAnchor {
                    // case: present under selection
                    return .init(
                        frame: .init(
                            x: x,
                            y: y - Style.inlineSuggestionMaxHeight,
                            width: Style.inlineSuggestionMinWidth,
                            height: Style.inlineSuggestionMaxHeight
                        ),
                        alignPanelTop: alignPanelTopToAnchor
                    )
                } else {
                    // case: present above selection
                    return .init(
                        frame: .init(
                            x: x,
                            y: y + selectionFrame.height + Style.widgetPadding,
                            width: Style.inlineSuggestionMinWidth,
                            height: Style.inlineSuggestionMaxHeight
                        ),
                        alignPanelTop: alignPanelTopToAnchor
                    )
                }
            }

            let caseConsiderCompletionPanel = {
                (completionPanelRect: CGRect) -> WidgetLocation.PanelLocation? in
                let completionPanelBelowCursor = completionPanelRect.minY >= selectionFrame.midY
                switch (completionPanelBelowCursor, alignPanelTopToAnchor) {
                case (true, false), (false, true):
                    // case: different position, place the suggestion as it should be
                    return caseIgnoreCompletionPanel(alignPanelTopToAnchor)
                case (true, true), (false, false):
                    // case: same position, place the suggestion next to the completion panel
                    let y = completionPanelBelowCursor
                        ? y - Style.inlineSuggestionMaxHeight
                        : y + selectionFrame.height - Style.widgetPadding
                    if let x = {
                        let proposedX = completionPanelRect.maxX + Style.widgetPadding
                        if proposedX + Style.inlineSuggestionMinWidth <= activeScreen.frame.maxX {
                            return proposedX
                        }
                        let leftSideX = completionPanelRect.minX
                            - Style.widgetPadding
                            - Style.inlineSuggestionMinWidth
                        if leftSideX >= activeScreen.frame.minX {
                            return leftSideX
                        }
                        return nil
                    }() {
                        return .init(
                            frame: .init(
                                x: x,
                                y: y,
                                width: Style.inlineSuggestionMinWidth,
                                height: Style.inlineSuggestionMaxHeight
                            ),
                            alignPanelTop: alignPanelTopToAnchor
                        )
                    }
                    // case: no enough horizontal space, place the suggestion on the other side
                    return caseIgnoreCompletionPanel(!alignPanelTopToAnchor)
                }
            }

            if let completionPanel, let completionPanelRect = completionPanel.rect {
                return caseConsiderCompletionPanel(completionPanelRect)
            } else {
                return caseIgnoreCompletionPanel(alignPanelTopToAnchor)
            }
        }
    }

    /// Get the frame of the selection.
    static func getSelectionFrame(editor: AXUIElement) -> CGRect? {
        guard let selectedRange: AXValue = try? editor
            .copyValue(key: kAXSelectedTextRangeAttribute),
            let rect: AXValue = try? editor.copyParameterizedValue(
                key: kAXBoundsForRangeParameterizedAttribute,
                parameters: selectedRange
            )
        else {
            return nil
        }
        var selectionFrame: CGRect = .zero
        let found = AXValueGetValue(rect, .cgRect, &selectionFrame)
        guard found else { return nil }
        return selectionFrame
    }

    /// Get the frame of the first line of the selection.
    static func getSelectionFirstLineFrame(editor: AXUIElement) -> CGRect? {
        // Find selection range rect
        guard let selectedRange: AXValue = try? editor
            .copyValue(key: kAXSelectedTextRangeAttribute),
            let rect: AXValue = try? editor.copyParameterizedValue(
                key: kAXBoundsForRangeParameterizedAttribute,
                parameters: selectedRange
            )
        else {
            return nil
        }
        var selectionFrame: CGRect = .zero
        let found = AXValueGetValue(rect, .cgRect, &selectionFrame)
        guard found else { return nil }

        var firstLineRange: CFRange = .init()
        let foundFirstLine = AXValueGetValue(selectedRange, .cfRange, &firstLineRange)
        firstLineRange.length = 0

        if foundFirstLine,
           let firstLineSelectionRange = AXValueCreate(.cfRange, &firstLineRange),
           let firstLineRect: AXValue = try? editor.copyParameterizedValue(
               key: kAXBoundsForRangeParameterizedAttribute,
               parameters: firstLineSelectionRange
           )
        {
            var firstLineFrame: CGRect = .zero
            let foundFirstLineFrame = AXValueGetValue(firstLineRect, .cgRect, &firstLineFrame)
            if foundFirstLineFrame {
                selectionFrame = firstLineFrame
            }
        }

        return selectionFrame
    }
}

public extension AXUIElement {
    /// Set global timeout in seconds.
    static func setGlobalMessagingTimeout(_ timeout: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeout)
    }

    /// Set timeout in seconds for this element.
    func setMessagingTimeout(_ timeout: Float) {
        AXUIElementSetMessagingTimeout(self, timeout)
    }

    var identifier: String {
        (try? copyValue(key: kAXIdentifierAttribute)) ?? ""
    }

    var value: String {
        (try? copyValue(key: kAXValueAttribute)) ?? ""
    }
    
    var intValue: Int? {
        (try? copyValue(key: kAXValueAttribute))
    }

    var title: String {
        (try? copyValue(key: kAXTitleAttribute)) ?? ""
    }

    var role: String {
        (try? copyValue(key: kAXRoleAttribute)) ?? ""
    }

    var doubleValue: Double {
        (try? copyValue(key: kAXValueAttribute)) ?? 0.0
    }

    var document: String? {
        try? copyValue(key: kAXDocumentAttribute)
    }

    /// Label in Accessibility Inspector.
    var description: String {
        (try? copyValue(key: kAXDescriptionAttribute)) ?? ""
    }

    /// Type in Accessibility Inspector.
    var roleDescription: String {
        (try? copyValue(key: kAXRoleDescriptionAttribute)) ?? ""
    }

    var label: String {
        (try? copyValue(key: kAXLabelValueAttribute)) ?? ""
    }

    var isSourceEditor: Bool {
        description == "Source Editor"
    }

    var selectedTextRange: ClosedRange<Int>? {
        guard let value: AXValue = try? copyValue(key: kAXSelectedTextRangeAttribute)
        else { return nil }
        var range: CFRange = .init(location: 0, length: 0)
        if AXValueGetValue(value, .cfRange, &range) {
            return range.location...(range.location + range.length)
        }
        return nil
    }

    var isFocused: Bool {
        (try? copyValue(key: kAXFocusedAttribute)) ?? false
    }

    var isEnabled: Bool {
        (try? copyValue(key: kAXEnabledAttribute)) ?? false
    }

    var isHidden: Bool {
        (try? copyValue(key: kAXHiddenAttribute)) ?? false
    }
}

// MARK: - Rect

public extension AXUIElement {
    var position: CGPoint? {
        guard let value: AXValue = try? copyValue(key: kAXPositionAttribute)
        else { return nil }
        var point: CGPoint = .zero
        if AXValueGetValue(value, .cgPoint, &point) {
            return point
        }
        return nil
    }

    var size: CGSize? {
        guard let value: AXValue = try? copyValue(key: kAXSizeAttribute)
        else { return nil }
        var size: CGSize = .zero
        if AXValueGetValue(value, .cgSize, &size) {
            return size
        }
        return nil
    }

    var rect: CGRect? {
        guard let position, let size else { return nil }
        return .init(origin: position, size: size)
    }
}

// MARK: - Relationship

public extension AXUIElement {
    var focusedElement: AXUIElement? {
        try? copyValue(key: kAXFocusedUIElementAttribute)
    }

    var sharedFocusElements: [AXUIElement] {
        (try? copyValue(key: kAXChildrenAttribute)) ?? []
    }

    var window: AXUIElement? {
        try? copyValue(key: kAXWindowAttribute)
    }

    var windows: [AXUIElement] {
        (try? copyValue(key: kAXWindowsAttribute)) ?? []
    }

    var isFullScreen: Bool {
        (try? copyValue(key: "AXFullScreen")) ?? false
    }

    var focusedWindow: AXUIElement? {
        try? copyValue(key: kAXFocusedWindowAttribute)
    }

    var topLevelElement: AXUIElement? {
        try? copyValue(key: kAXTopLevelUIElementAttribute)
    }

    var rows: [AXUIElement] {
        (try? copyValue(key: kAXRowsAttribute)) ?? []
    }

    var parent: AXUIElement? {
        try? copyValue(key: kAXParentAttribute)
    }

    var children: [AXUIElement] {
        (try? copyValue(key: kAXChildrenAttribute)) ?? []
    }

    var menuBar: AXUIElement? {
        try? copyValue(key: kAXMenuBarAttribute)
    }

    var visibleChildren: [AXUIElement] {
        (try? copyValue(key: kAXVisibleChildrenAttribute)) ?? []
    }

    func child(
        identifier: String? = nil,
        title: String? = nil,
        role: String? = nil
    ) -> AXUIElement? {
        for child in children {
            let match = {
                if let identifier, child.identifier != identifier { return false }
                if let title, child.title != title { return false }
                if let role, child.role != role { return false }
                return true
            }()
            if match { return child }
        }
        for child in children {
            if let target = child.child(
                identifier: identifier,
                title: title,
                role: role
            ) { return target }
        }
        return nil
    }

    func children(where match: (AXUIElement) -> Bool) -> [AXUIElement] {
        var all = [AXUIElement]()
        for child in children {
            if match(child) { all.append(child) }
        }
        for child in children {
            all.append(contentsOf: child.children(where: match))
        }
        return all
    }

    func firstParent(where match: (AXUIElement) -> Bool) -> AXUIElement? {
        guard let parent = parent else { return nil }
        if match(parent) { return parent }
        return parent.firstParent(where: match)
    }

    func firstChild(where match: (AXUIElement) -> Bool) -> AXUIElement? {
        for child in children {
            if match(child) { return child }
        }
        for child in children {
            if let target = child.firstChild(where: match) {
                return target
            }
        }
        return nil
    }

    func visibleChild(identifier: String) -> AXUIElement? {
        for child in visibleChildren {
            if child.identifier == identifier { return child }
            if let target = child.visibleChild(identifier: identifier) { return target }
        }
        return nil
    }

    var verticalScrollBar: AXUIElement? {
        try? copyValue(key: kAXVerticalScrollBarAttribute)
    }
}

// MARK: - Helper

public extension AXUIElement {
    func copyValue<T>(key: String, ofType _: T.Type = T.self) throws -> T {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(self, key as CFString, &value)
        if error == .success, let value = value as? T {
            return value
        }
        throw error
    }

    func copyParameterizedValue<T>(
        key: String,
        parameters: AnyObject,
        ofType _: T.Type = T.self
    ) throws -> T {
        var value: AnyObject?
        let error = AXUIElementCopyParameterizedAttributeValue(
            self,
            key as CFString,
            parameters as CFTypeRef,
            &value
        )
        if error == .success, let value = value as? T {
            return value
        }
        throw error
    }
}

extension AXError: Error {}

