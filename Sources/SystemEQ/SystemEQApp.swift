import AppKit
import SwiftUI

@main
struct SystemEQApp: App {
    @StateObject private var controller = AudioController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 920, height: 620)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit System EQ") {
                    controller.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
