import SwiftUI

@main
struct StickyCounterApp: App {
    @StateObject private var store = CounterStore()
    @AppStorage("isSticky") private var isSticky = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    setupMainWindowBehavior()
                }
                .onChange(of: isSticky) { _, _ in
                    setupMainWindowBehavior()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                    setupMainWindowBehavior()
                }
        }
    }
    
    private func setupMainWindowBehavior() {
        // Only apply to the main content window to avoid overriding popouts
        for window in NSApplication.shared.windows {
            // A crude heuristic: the main window has a title if not hidden
            if window.styleMask.contains(.titled) && !window.styleMask.contains(.fullSizeContentView) {
                window.level = isSticky ? .floating : .normal
                window.collectionBehavior.remove(.canJoinAllSpaces)
            }
        }
    }
}
