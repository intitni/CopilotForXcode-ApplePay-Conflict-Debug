import SwiftUI

struct Content: View {
    var body: some View {
        Form {
            Text("Please first try loading each window one by one to see if you can reproduce the issue.")
            
            Section("Loading windows") {
                Button(action: {
                    Task {
                        _ = windowsController.windows.fullscreenDetector
                    }
                }) {
                    Text("Load fullscreen detector window")
                }

                Button(action: {
                    Task {
                        _ = windowsController.windows.widgetWindow
                    }
                }) {
                    Text("Load widget window")
                }

                Button(action: {
                    Task {
                        _ = windowsController.windows.sharedPanelWindow
                    }
                }) {
                    Text("Load shared panel window")
                }

                Button(action: {
                    Task {
                        _ = windowsController.windows.toastWindow
                    }
                }) {
                    Text("Load toast window")
                }

                Button(action: {
                    Task {
                        _ = windowsController.windows.suggestionPanelWindow
                    }
                }) {
                    Text("Load suggestion panel window")
                }

                Button(action: {
                    Task {
                        _ = windowsController.windows.chatPanelWindow
                    }
                }) {
                    Text("Load chat panel window")
                }
            }

            Section("Trigger events") {
                Button(action: { Task { windowsController.windows.orderFront() } }) {
                    Text("Order windows front")
                }

                Button(action: {
                    Task {
                        await windowsController.updateWindowLocation(
                            animated: true,
                            immediately: true
                        )
                    }
                }) {
                    Text("Update window location")
                }

                Button(action: {
                    Task {
                        await windowsController.updateWindowOpacity(immediately: true)
                    }
                }) {
                    Text("Update window opacity")
                }
            }
        }
        .formStyle(.grouped)
    }
}

