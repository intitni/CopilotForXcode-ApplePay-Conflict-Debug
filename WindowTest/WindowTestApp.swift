import AppKit
import SwiftUI

let windowsController = WidgetWindowsController()

@main
struct WindowTestApp: App {
    var body: some Scene {
        WindowGroup {
            Content()
                .onAppear {
                    AXIsProcessTrustedWithOptions([
                        kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true,
                    ] as CFDictionary)
                }
        }
    }
}

