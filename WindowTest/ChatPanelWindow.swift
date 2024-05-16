import AppKit
import Combine
import Foundation
import SwiftUI

final class ChatPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var cancellable: Set<AnyCancellable> = []

    var minimizeWindow: () -> Void = {}

    init(
        minimizeWindow: @escaping () -> Void
    ) {
        self.minimizeWindow = minimizeWindow
        super.init(
            contentRect: .zero,
            styleMask: [.resizable, .titled, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        addTitlebarAccessoryViewController({
            let controller = NSTitlebarAccessoryViewController()
            let view = NSHostingView(rootView: Text("title bar"))
            controller.view = view
            view.frame = .init(x: 0, y: 0, width: 100, height: 40)
            controller.layoutAttribute = .right
            return controller
        }())
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        level = .init(NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [
            .fullScreenAuxiliary,
            .transient,
            .fullScreenPrimary,
            .fullScreenAllowsTiling,
        ]
        hasShadow = true
        contentView = NSHostingView(
            rootView: Text("chatPanelWindow").padding(200).background(.white)
        )
        setIsVisible(true)
        isPanelDisplayed = false
    }

    func setFloatOnTop(_ isFloatOnTop: Bool) {
        let targetLevel: NSWindow.Level = isFloatOnTop
            ? .init(NSWindow.Level.floating.rawValue + 1)
            : .normal

        if targetLevel != level {
            level = targetLevel
        }
    }

    var isWindowHidden: Bool = false {
        didSet {
            alphaValue = isPanelDisplayed && !isWindowHidden ? 1 : 0
        }
    }

    var isPanelDisplayed: Bool = false {
        didSet {
            alphaValue = isPanelDisplayed && !isWindowHidden ? 1 : 0
        }
    }

    override var alphaValue: CGFloat {
        didSet {
            ignoresMouseEvents = alphaValue <= 0
        }
    }

    override func miniaturize(_: Any?) {
        minimizeWindow()
    }
}

