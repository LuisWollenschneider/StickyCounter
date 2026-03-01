import SwiftUI
import AppKit

class PopoutPanel: NSPanel {
    // Allows the panel to accept keyboard shortcuts (Cmd+, Cmd-)
    override var canBecomeKey: Bool {
        return true
    }
    
    // Explicitly prevents the panel from pulling the main application forward when it's a HUD,
    // but permits it to anchor the application if it's acting as a normal window on another Space.
    override var canBecomeMain: Bool {
        return !isFloatingPanel
    }
}

class PopoutWindowManager {
    static let shared = PopoutWindowManager()
    private var panels: [UUID: NSWindow] = [:]
    
    func openPopout(id: UUID, store: CounterStore, isSticky: Bool = true, initialFrame: NSRect? = nil) {
        if let existing = panels[id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        var mask: NSWindow.StyleMask = [.resizable, .closable, .titled, .fullSizeContentView]
        if isSticky {
            mask.insert(.nonactivatingPanel)
        }
        
        let contentRect = initialFrame ?? NSRect(x: 0, y: 0, width: 320, height: 400)
        let window: NSWindow
        
        if isSticky {
            let panel = PopoutPanel(
                contentRect: contentRect,
                styleMask: mask,
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            window = panel
        } else {
            window = NSWindow(
                contentRect: contentRect,
                styleMask: mask,
                backing: .buffered,
                defer: false
            )
            window.level = .normal
            window.isReleasedWhenClosed = false
        }
        
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        let hostedView = PopoutCounterListView(windowId: id).environmentObject(store)
        window.contentView = NSHostingView(rootView: hostedView)
        
        panels[id] = window
        
        if initialFrame == nil {
            window.center()
        }
        
        window.makeKeyAndOrderFront(nil)

        // Apply frame after the window is shown to avoid triggering layout recursion
        // (calling setFrame before makeKeyAndOrderFront can cause -layoutSubtreeIfNeeded
        // to be invoked while a layout pass is already in progress).
        if let frame = initialFrame {
            window.setFrame(frame, display: false)
        }
        
        if !isSticky {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func closePopout(id: UUID) {
        panels[id]?.close()
        panels.removeValue(forKey: id)
    }
    
    func setSticky(id: UUID, isSticky: Bool, store: CounterStore) {
        guard let oldPanel = panels[id] else { return }
        
        // Prevent infinite loops if state matches
        let isCurrentlyFloating = oldPanel.level == .floating
        if isCurrentlyFloating == isSticky { return }
        
        let currentFrame = oldPanel.frame
        
        // Use userInteractive QoS to match the calling thread's priority and avoid
        // the "Thread running at User-interactive QoS waiting on Default QoS" hang risk.
        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
            oldPanel.close()
            self?.panels.removeValue(forKey: id)
            self?.openPopout(id: id, store: store, isSticky: isSticky, initialFrame: currentFrame)
        }
    }
}
