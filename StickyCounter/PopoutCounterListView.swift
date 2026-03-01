import SwiftUI
import UniformTypeIdentifiers

struct PopoutCounterListView: View {
    let windowId: UUID
    @EnvironmentObject var store: CounterStore
    @AppStorage private var isWindowSticky: Bool
    @AppStorage private var uiScale: Double
    @State private var isHoveringPin = false
    
    init(windowId: UUID) {
        self.windowId = windowId
        _isWindowSticky = AppStorage(wrappedValue: true, "isSticky_popout_\(windowId.uuidString)")
        _uiScale = AppStorage(wrappedValue: 1.0, "uiScale_popout_\(windowId.uuidString)")
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280 * uiScale), spacing: 12 * uiScale)], spacing: 12 * uiScale) {
                    ForEach(store.counters) { counter in
                        if counter.windowIds.contains(windowId.uuidString) {
                            let counterId = counter.id
                            let counterBinding = Binding<Counter>(
                                get: { self.store.counters.first(where: { $0.id == counterId }) ?? counter },
                                set: { newValue in
                                    if let index = self.store.counters.firstIndex(where: { $0.id == counterId }) {
                                        self.store.counters[index] = newValue
                                    }
                                }
                            )
                            
                            CounterCardView(counter: counterBinding, onRemove: {
                                withAnimation {
                                    if let idx = store.counters.firstIndex(where: { $0.id == counterId }) {
                                        store.counters[idx].windowIds.remove(windowId.uuidString)
                                    }
                                }
                            }, isPopout: true, uiScale: uiScale)
                        }
                    }
                }
                .padding()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NSApp.keyWindow?.makeFirstResponder(nil)
                if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == windowId.uuidString }) {
                    window.makeKey()
                }
            }
            
            // Hidden Keyboard Shortcut Interceptors
            Group {
                Button("") {
                    if uiScale < 3.0 { uiScale += 0.1 }
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("") {
                    if uiScale > 0.4 { uiScale -= 0.1 }
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("") {
                    isWindowSticky.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
            
            // Hoverable Floating Pin Button
            VStack {
                Button(action: {
                    isWindowSticky.toggle()
                }) {
                    Image(systemName: isWindowSticky ? "pin.fill" : "pin")
                        .foregroundColor(isWindowSticky ? .accentColor : .secondary)
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(isWindowSticky ? 45 : 0))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Always on top (Cmd+F)")
                .opacity(isHoveringPin ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isHoveringPin)
            }
            .padding(8)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringPin = hovering
            }
        }
        .onChange(of: store.counters.filter({ $0.windowIds.contains(windowId.uuidString) }).count) { _, newCount in
            if newCount == 0 {
                PopoutWindowManager.shared.closePopout(id: windowId)
            }
        }
        .onChange(of: isWindowSticky) { _, newValue in
            PopoutWindowManager.shared.setSticky(id: windowId, isSticky: newValue, store: store)
        }
        .onAppear {
            PopoutWindowManager.shared.setSticky(id: windowId, isSticky: isWindowSticky, store: store)
        }
        .frame(minWidth: 250 * uiScale, idealWidth: 320 * uiScale, maxWidth: .infinity, minHeight: 170 * uiScale, idealHeight: 400 * uiScale, maxHeight: .infinity)
        // Ensure standard window frame behaves with no large titlebar
        .ignoresSafeArea(.all)
    }
}
