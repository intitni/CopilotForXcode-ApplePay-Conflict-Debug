import AppKit
import Foundation
import SwiftUI

actor WidgetWindowsController: NSObject {
    let windows: WidgetWindows
    var currentApplicationProcessIdentifier: pid_t?
    var isChatPanelDetached = true

    var updateWindowOpacityTask: Task<Void, Error>?
    var lastUpdateWindowOpacityTime = Date(timeIntervalSince1970: 0)

    var updateWindowLocationTask: Task<Void, Error>?
    var lastUpdateWindowLocationTime = Date(timeIntervalSince1970: 0)

    let xcodeInspector = XcodeInspector()

    override init() {
        windows = .init()
        super.init()
        windows.controller = self
    }
}

class XcodeInspector {
    struct App {
        var isXcode: Bool { app.bundleIdentifier == "com.apple.dt.Xcode" }
        var isExtensionService: Bool { app.bundleIdentifier == Bundle.main.bundleIdentifier }
        var app: NSRunningApplication
        var appElement: AXUIElement
        var focusedEditorElement: AXUIElement?
    }

    var focusedEditor: AXUIElement? {
        guard let xcode = activeApplication, xcode.isXcode else { return nil }
        return xcode.focusedEditorElement
    }

    var latestActiveXcode: App? {
        let runningApplications = NSWorkspace.shared.runningApplications
        let xcode = runningApplications.first { $0.bundleIdentifier == "com.apple.dt.Xcode" }
        if let xcode {
            let element = AXUIElementCreateApplication(xcode.processIdentifier)
            return App(
                app: xcode,
                appElement: element,
                focusedEditorElement: element.focusedElement
            )
        } else {
            return nil
        }
    }

    var activeApplication: App? {
        let runningApplications = NSWorkspace.shared.runningApplications
        guard let activeApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(activeApp.processIdentifier)
        return App(
            app: activeApp,
            appElement: element,
            focusedEditorElement: nil
        )
    }

    var previousActiveApplication: App? {
        activeApplication
    }
}

// MARK: - Observation

private extension WidgetWindowsController {}

// MARK: - Window Updating

extension WidgetWindowsController {
    @MainActor
    func hidePanelWindows() {
        windows.sharedPanelWindow.alphaValue = 0
        windows.suggestionPanelWindow.alphaValue = 0
    }

    @MainActor
    func hideSuggestionPanelWindow() {
        windows.suggestionPanelWindow.alphaValue = 0
    }

    func generateWidgetLocation() -> WidgetLocation? {
        if let application = xcodeInspector.latestActiveXcode?.appElement {
            if let focusElement = xcodeInspector.focusedEditor,
               let parent = focusElement.parent,
               let frame = parent.rect,
               let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }),
               let firstScreen = NSScreen.main
            {
                let positionMode = 1
                let suggestionMode = 1

                switch positionMode {
                case 1:
                    var result = UpdateLocationStrategy.FixedToBottom().framesForWindows(
                        editorFrame: frame,
                        mainScreen: screen,
                        activeScreen: firstScreen
                    )
                    switch suggestionMode {
                    case 1:
                        result.suggestionPanelLocation = UpdateLocationStrategy
                            .NearbyTextCursor()
                            .framesForSuggestionWindow(
                                editorFrame: frame, mainScreen: screen,
                                activeScreen: firstScreen,
                                editor: focusElement,
                                completionPanel: nil
                            )
                    default:
                        break
                    }
                    return result
                default:
                    var result = UpdateLocationStrategy.AlignToTextCursor().framesForWindows(
                        editorFrame: frame,
                        mainScreen: screen,
                        activeScreen: firstScreen,
                        editor: focusElement
                    )
                    switch suggestionMode {
                    case 1:
                        result.suggestionPanelLocation = UpdateLocationStrategy
                            .NearbyTextCursor()
                            .framesForSuggestionWindow(
                                editorFrame: frame, mainScreen: screen,
                                activeScreen: firstScreen,
                                editor: focusElement,
                                completionPanel: nil
                            )
                    default:
                        break
                    }
                    return result
                }
            } else if var window = application.focusedWindow,
                      var frame = application.focusedWindow?.rect,
                      !["menu bar", "menu bar item"].contains(window.description),
                      frame.size.height > 300,
                      let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }),
                      let firstScreen = NSScreen.main
            {
                if ["open_quickly"].contains(window.identifier)
                    || ["alert"].contains(window.label)
                {
                    // fallback to use workspace window
                    guard let workspaceWindow = application.windows
                        .first(where: { $0.identifier == "Xcode.WorkspaceWindow" }),
                        let rect = workspaceWindow.rect
                    else {
                        return WidgetLocation(
                            widgetFrame: .zero,
                            tabFrame: .zero,
                            defaultPanelLocation: .init(frame: .zero, alignPanelTop: false)
                        )
                    }

                    window = workspaceWindow
                    frame = rect
                }

                var expendedSize = CGSize.zero
                if ["Xcode.WorkspaceWindow"].contains(window.identifier) {
                    // extra padding to bottom so buttons won't be covered
                    frame.size.height -= 40
                } else {
                    // move a bit away from the window so buttons won't be covered
                    frame.origin.x -= Style.widgetPadding + Style.widgetWidth / 2
                    frame.size.width += Style.widgetPadding * 2 + Style.widgetWidth
                    expendedSize.width = (Style.widgetPadding * 2 + Style.widgetWidth) / 2
                    expendedSize.height += Style.widgetPadding
                }

                return UpdateLocationStrategy.FixedToBottom().framesForWindows(
                    editorFrame: frame,
                    mainScreen: screen,
                    activeScreen: firstScreen,
                    preferredInsideEditorMinWidth: 9_999_999_999, // never
                    editorFrameExpendedSize: expendedSize
                )
            }
        }
        return nil
    }

    func updateWindowOpacity(immediately: Bool) {
        let shouldDebounce = !immediately &&
            !(Date().timeIntervalSince(lastUpdateWindowOpacityTime) > 3)
        lastUpdateWindowOpacityTime = Date()
        updateWindowOpacityTask?.cancel()

        let task = Task {
            if shouldDebounce {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            try Task.checkCancellation()
            let xcodeInspector = self.xcodeInspector
            let activeApp = xcodeInspector.activeApplication
            let latestActiveXcode = xcodeInspector.latestActiveXcode
            let previousActiveApplication = xcodeInspector.previousActiveApplication
            let isChatPanelDetached = self.isChatPanelDetached
            await MainActor.run {
                let hasChat = true

                if let activeApp, activeApp.isXcode {
                    let application = activeApp.appElement
                    /// We need this to hide the windows when Xcode is minimized.
                    let noFocus = application.focusedWindow == nil
                    windows.sharedPanelWindow.alphaValue = noFocus ? 0 : 1
                    windows.suggestionPanelWindow.alphaValue = noFocus ? 0 : 1
                    windows.widgetWindow.alphaValue = noFocus ? 0 : 1
                    windows.toastWindow.alphaValue = noFocus ? 0 : 1

                    if isChatPanelDetached {
                        windows.chatPanelWindow.isWindowHidden = !hasChat
                    } else {
                        windows.chatPanelWindow.isWindowHidden = noFocus
                    }
                } else if let activeApp, activeApp.isExtensionService {
                    let noFocus = {
                        guard let xcode = latestActiveXcode else { return true }
                        if let window = xcode.appElement.focusedWindow,
                           window.role == "AXWindow"
                        {
                            return false
                        }
                        return true
                    }()

                    let previousAppIsXcode = previousActiveApplication?.isXcode ?? false

                    windows.sharedPanelWindow.alphaValue = noFocus ? 0 : 1
                    windows.suggestionPanelWindow.alphaValue = noFocus ? 0 : 1
                    windows.widgetWindow.alphaValue = if noFocus {
                        0
                    } else if previousAppIsXcode {
                        1
                    } else {
                        0
                    }
                    windows.toastWindow.alphaValue = noFocus ? 0 : 1
                    if isChatPanelDetached {
                        windows.chatPanelWindow.isWindowHidden = !hasChat
                    } else {
                        windows.chatPanelWindow.isWindowHidden = noFocus && !windows
                            .chatPanelWindow.isKeyWindow
                    }
                } else {
                    windows.sharedPanelWindow.alphaValue = 0
                    windows.suggestionPanelWindow.alphaValue = 0
                    windows.widgetWindow.alphaValue = 0
                    windows.toastWindow.alphaValue = 0
                    if !isChatPanelDetached {
                        windows.chatPanelWindow.isWindowHidden = true
                    }
                }
            }
        }

        updateWindowOpacityTask = task
    }

    func updateWindowLocation(
        animated: Bool,
        immediately: Bool,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        @Sendable @MainActor
        func update() async {
            guard let widgetLocation = await generateWidgetLocation() else { return }
//            await updatePanelState(widgetLocation)

            windows.widgetWindow.setFrame(
                widgetLocation.widgetFrame,
                display: false,
                animate: animated
            )
            windows.toastWindow.setFrame(
                widgetLocation.defaultPanelLocation.frame,
                display: false,
                animate: animated
            )
            windows.sharedPanelWindow.setFrame(
                widgetLocation.defaultPanelLocation.frame,
                display: false,
                animate: animated
            )

            if let suggestionPanelLocation = widgetLocation.suggestionPanelLocation {
                windows.suggestionPanelWindow.setFrame(
                    suggestionPanelLocation.frame,
                    display: false,
                    animate: animated
                )
            }

            if await isChatPanelDetached {
                // don't update it!
            } else {
                windows.chatPanelWindow.setFrame(
                    widgetLocation.defaultPanelLocation.frame,
                    display: false,
                    animate: animated
                )
            }

            await adjustChatPanelWindowLevel()
        }

        let now = Date()
        let shouldThrottle = !immediately &&
            !(now.timeIntervalSince(lastUpdateWindowLocationTime) > 3)

        updateWindowLocationTask?.cancel()
        let interval: TimeInterval = 0.05

        if shouldThrottle {
            let delay = max(
                0,
                interval - now.timeIntervalSince(lastUpdateWindowLocationTime)
            )

            updateWindowLocationTask = Task {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
                await update()
            }
        } else {
            Task {
                await update()
            }
        }
        lastUpdateWindowLocationTime = Date()
    }

    @MainActor
    func adjustChatPanelWindowLevel() async {
        let disableFloatOnTopWhenTheChatPanelIsDetached = true

        let window = windows.chatPanelWindow
        guard disableFloatOnTopWhenTheChatPanelIsDetached else {
            window.setFloatOnTop(true)
            return
        }

        guard await isChatPanelDetached else {
            window.setFloatOnTop(true)
            return
        }

        let floatOnTopWhenOverlapsXcode = true

        let latestApp = xcodeInspector.activeApplication
        let latestAppIsXcodeOrExtension = if let latestApp {
            latestApp.isXcode || latestApp.isExtensionService
        } else {
            false
        }

        if !floatOnTopWhenOverlapsXcode || !latestAppIsXcodeOrExtension {
            window.setFloatOnTop(false)
        } else {
//            guard let xcode = await xcodeInspector.safe.latestActiveXcode else { return }
//            let windowElements = xcode.appElement.windows
//            let overlap = windowElements.contains {
//                if let position = $0.position, let size = $0.size {
//                    let rect = CGRect(
//                        x: position.x,
//                        y: position.y,
//                        width: size.width,
//                        height: size.height
//                    )
//                    return rect.intersects(window.frame)
//                }
//                return false
//            }

            window.setFloatOnTop(true)
        }
    }
}

// MARK: - NSWindowDelegate

extension WidgetWindowsController: NSWindowDelegate {
    nonisolated
    func windowWillMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            guard window === windows.chatPanelWindow else { return }
            await Task.yield()
        }
    }

    nonisolated
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            guard window === windows.chatPanelWindow else { return }
            await Task.yield()
        }
    }

    nonisolated
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            guard window === windows.chatPanelWindow else { return }
            await Task.yield()
        }
    }

    nonisolated
    func windowWillExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            guard window === windows.chatPanelWindow else { return }
            await Task.yield()
        }
    }
}

// MARK: - Windows

public final class WidgetWindows {
    weak var controller: WidgetWindowsController?

    // you should make these window `.transient` so they never show up in the mission control.

    @MainActor
    lazy var fullscreenDetector = {
        let it = CanBecomeKeyWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        it.isReleasedWhenClosed = false
        it.isOpaque = false
        it.backgroundColor = .clear
        it.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        it.hasShadow = false
        it.setIsVisible(false)
        it.canBecomeKeyChecker = { false }
        return it
    }()

    @MainActor
    lazy var widgetWindow = {
        let it = CanBecomeKeyWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        it.isReleasedWhenClosed = false
        it.isOpaque = false
        it.backgroundColor = .clear
        it.level = .floating
        it.collectionBehavior = [.fullScreenAuxiliary, .transient]
        it.hasShadow = true
        it.contentView = NSHostingView(
            rootView: Text("widgetWindow").padding(100).xcodeStyleFrame()
        )
        it.setIsVisible(true)
        it.canBecomeKeyChecker = { false }
        return it
    }()

    @MainActor
    lazy var sharedPanelWindow = {
        let it = CanBecomeKeyWindow(
            contentRect: .init(x: 0, y: 0, width: Style.panelWidth, height: Style.panelHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        it.isReleasedWhenClosed = false
        it.isOpaque = false
        it.backgroundColor = .clear
        it.level = .init(NSWindow.Level.floating.rawValue + 2)
        it.collectionBehavior = [.fullScreenAuxiliary, .transient]
        it.hasShadow = true
        it.contentView = NSHostingView(
            rootView: Text("sharedPanelWindow").padding(100).xcodeStyleFrame()
        )
        it.setIsVisible(true)
        it.canBecomeKeyChecker = { true }
        return it
    }()

    @MainActor
    lazy var suggestionPanelWindow = {
        let it = CanBecomeKeyWindow(
            contentRect: .init(x: 0, y: 0, width: Style.panelWidth, height: Style.panelHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        it.isReleasedWhenClosed = false
        it.isOpaque = false
        it.backgroundColor = .clear
        it.level = .init(NSWindow.Level.floating.rawValue + 2)
        it.collectionBehavior = [.fullScreenAuxiliary, .transient]
        it.hasShadow = true
        it.contentView = NSHostingView(
            rootView: Text("suggestionPanelWindow").padding(100).xcodeStyleFrame()
        )
        it.canBecomeKeyChecker = { false }
        it.setIsVisible(true)
        return it
    }()

    @MainActor
    lazy var chatPanelWindow = {
        let it = ChatPanelWindow(
            minimizeWindow: { [weak self] in
                print("minimize")
            }
        )
        it.delegate = controller
        return it
    }()

    @MainActor
    lazy var toastWindow = {
        let it = CanBecomeKeyWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        it.isReleasedWhenClosed = false
        it.isOpaque = true
        it.backgroundColor = .clear
        it.level = .floating
        it.collectionBehavior = [.fullScreenAuxiliary, .transient]
        it.hasShadow = false
        it.contentView = NSHostingView(
            rootView: Text("toastWindow").padding(100).background(.white)
        )
        it.setIsVisible(true)
        it.ignoresMouseEvents = true
        it.canBecomeKeyChecker = { false }
        return it
    }()

    init() {}

    @MainActor
    func orderFront() {
        widgetWindow.orderFrontRegardless()
        toastWindow.orderFrontRegardless()
        sharedPanelWindow.orderFrontRegardless()
        suggestionPanelWindow.orderFrontRegardless()
        if chatPanelWindow.level.rawValue > NSWindow.Level.normal.rawValue {
            chatPanelWindow.orderFrontRegardless()
        }
    }
}

// MARK: - Window Subclasses

class CanBecomeKeyWindow: NSWindow {
    var canBecomeKeyChecker: () -> Bool = { true }
    override var canBecomeKey: Bool { canBecomeKeyChecker() }
    override var canBecomeMain: Bool { canBecomeKeyChecker() }
}

