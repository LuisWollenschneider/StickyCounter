import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case folder(UUID)
    case counter(UUID)
}

struct ContentView: View {
    @EnvironmentObject var store: CounterStore
    @State private var selection: SidebarSelection? = .all
    @State private var searchText = ""
    
    let columns = [
        GridItem(.adaptive(minimum: 280), spacing: 12)
    ]
    
    var countersToDisplay: [Counter] {
        if let sel = selection {
            switch sel {
            case .all:
                return store.getCounters(in: nil)
            case .folder(let fId):
                return store.getCounters(in: fId)
            case .counter(let cId):
                if let c = store.counters.first(where: { $0.id == cId }) {
                    return [c]
                }
                return []
            }
        }
        return store.getCounters(in: nil)
    }
  
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("All Counters", systemImage: "tray")
                        .tag(SidebarSelection.all)
                        .dropDestination(for: String.self) { items, location in
                            guard let firstStr = items.first, let droppedId = UUID(uuidString: firstStr) else { return false }
                            withAnimation {
                                if store.counters.contains(where: { $0.id == droppedId }) {
                                    store.moveCounter(id: droppedId, toFolder: nil)
                                }
                            }
                            return true
                        }
                }
                
                Section("Folders") {
                    let nodes = store.filteredFolderNodes(searchText: searchText)
                    ForEach(nodes, id: \.id) { node in
                        FolderRow(node: node, store: store)
                    }
                    
                    // Empty drop target for dragging folders back to root
                    Color.clear
                        .frame(height: 10)
                        .dropDestination(for: String.self) { items, location in
                            guard let firstStr = items.first, let droppedId = UUID(uuidString: firstStr) else { return false }
                            withAnimation {
                                if store.folders.contains(where: { $0.id == droppedId }) {
                                    store.moveFolder(id: droppedId, toParent: nil)
                                }
                            }
                            return true
                        }
                }
            }
            .navigationTitle("Counters")
            .searchable(text: $searchText, prompt: "Search Counters")
            .onDeleteCommand {
                if let sel = selection {
                    withAnimation {
                        if case .folder(let id) = sel {
                            store.deleteFolder(id: id)
                        } else if case .counter(let id) = sel {
                            store.counters.removeAll { $0.id == id }
                        }
                        selection = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.bottom, 8)
                    Button(action: {
                        var parentId: UUID? = nil
                        if case .folder(let id) = selection { parentId = id }
                        store.addFolder(name: "New Folder", parentId: parentId)
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .foregroundColor(.primary)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Add Folder")
                    .padding(.bottom, 12)
                }
                .background(.ultraThinMaterial)
            }
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        if searchText.isEmpty {
                            ForEach(countersToDisplay) { counter in
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
                                        store.counters.removeAll(where: { $0.id == counterId })
                                    }
                                })
                                .draggable(counter.id.uuidString)
                            }
                            
                            if case .counter(_) = selection {
                                // Don't show add grid button if selecting a specific single counter
                            } else {
                                // Add Button at the end of the grid
                                Button(action: {
                                    withAnimation {
                                        var fId: UUID? = nil
                                        if case .folder(let id) = selection { fId = id }
                                        store.addCounter(name: "New Counter", folderId: fId)
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.accentColor)
                                        Text("Add Counter")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 120)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            // Search Results Mode
                            let results = store.counters.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                            let grouped = Dictionary(grouping: results, by: { $0.folderId })
                            let sortedKeys = grouped.keys.sorted(by: { store.getFolderPath(for: $0) < store.getFolderPath(for: $1) })
                            
                            ForEach(sortedKeys, id: \.self) { folderId in
                                Section(header: 
                                    HStack {
                                        Text(store.getFolderPath(for: folderId))
                                            .font(.title2.bold())
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                    .padding(.top, 24)
                                    .padding(.bottom, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Jump to folder and clear search
                                        searchText = ""
                                        if let fId = folderId {
                                            selection = .folder(fId)
                                        } else {
                                            selection = .all
                                        }
                                    }
                                ) {
                                    ForEach(grouped[folderId] ?? []) { counter in
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
                                                store.counters.removeAll(where: { $0.id == counterId })
                                            }
                                        })
                                        .draggable(counter.id.uuidString)
                                    }
                                }
                            }
                            if results.isEmpty {
                                Text("No counters found matching \"\(searchText)\"")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 40)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .padding(16)
                }
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if case .folder(_) = selection {
                        Button(action: {
                            let newWindowId = UUID()
                            for counter in countersToDisplay {
                                if let index = store.counters.firstIndex(where: { $0.id == counter.id }) {
                                    store.counters[index].windowIds.insert(newWindowId.uuidString)
                                }
                            }
                            PopoutWindowManager.shared.openPopout(id: newWindowId, store: store)
                        }) {
                            Image(systemName: "macwindow.badge.plus")
                                .help("Pop out all counters in this folder")
                        }
                    }
                }
            }
        }
    }
}

// Separate recursive view struct utilizing OutlineGroup specifically
struct FolderRow: View {
    let node: FolderNode
    @ObservedObject var store: CounterStore
    
    var body: some View {
        // Automatically creates the native hierarchical Disclosure look
        OutlineGroup([node], children: \.children) { childNode in
            FolderLabel(folder: childNode.folder, store: store)
        }
    }
}

struct FolderLabel: View {
    let folder: Folder
    @ObservedObject var store: CounterStore
    @State private var folderName: String
    
    init(folder: Folder, store: CounterStore) {
        self.folder = folder
        self.store = store
        _folderName = State(initialValue: folder.name)
    }
    
    var body: some View {
        HStack {
            Image(systemName: "folder")
            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.plain)
                .onSubmit {
                    store.updateFolderName(id: folder.id, newName: folderName)
                }
        }
        .tag(SidebarSelection.folder(folder.id))
        .itemProvider {
            let provider = NSItemProvider(object: folder.id.uuidString as NSString)
            provider.suggestedName = "Folder"
            return provider
        }
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    store.deleteFolder(id: folder.id)
                }
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard let firstStr = items.first, let droppedId = UUID(uuidString: firstStr) else { return false }
            
            withAnimation {
                if store.counters.contains(where: { $0.id == droppedId }) {
                    store.moveCounter(id: droppedId, toFolder: folder.id)
                } else if store.folders.contains(where: { $0.id == droppedId }) {
                    // Prevent dropping a folder into itself or its own descendant tree
                    if droppedId != folder.id {
                        store.moveFolder(id: droppedId, toParent: folder.id)
                    }
                }
            }
            return true
        }
    }
}

struct CounterCardView: View {
    @Binding var counter: Counter
    var onRemove: () -> Void
    var isPopout: Bool = false
    var uiScale: Double = 1.0
    @EnvironmentObject var store: CounterStore
    
    // Extracted colors to match the design roughly
    let cardBackgroundColor = Color(red: 0.12, green: 0.12, blue: 0.13)
    let incrementBgColor = Color(red: 0.17, green: 0.28, blue: 0.18)
    let incrementFgColor = Color(red: 0.21, green: 0.85, blue: 0.35)
    let decrementBgColor = Color(red: 0.24, green: 0.14, blue: 0.14)
    let decrementFgColor = Color(red: 0.98, green: 0.29, blue: 0.31)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16 * uiScale) {
            // Top Bar: Title & Menu
            HStack(alignment: .top) {
                TextField("Counter Name", text: $counter.name)
                    .font(.system(size: 28 * uiScale, weight: .bold))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                Menu {
                    Button("Pop Out to Window") {
                        let newWindowId = UUID()
                        counter.windowIds.insert(newWindowId.uuidString)
                        PopoutWindowManager.shared.openPopout(id: newWindowId, store: store)
                    }
                    
                    Picker("Step Size", selection: $counter.step) {
                        Text("1").tag(1)
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("50").tag(50)
                        Text("100").tag(100)
                    }
                    
                    if isPopout {
                        Button("Remove from Window", role: .destructive, action: onRemove)
                    } else {
                        Button("Delete Counter", role: .destructive, action: onRemove)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20 * uiScale))
                        .foregroundColor(.gray)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Middle: Big Number and Controls
            HStack(alignment: .center) {
                Spacer()
                
                VStack {
                    TextField("Count", value: $counter.count, format: .number)
                        .font(.system(size: 80 * uiScale, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(white: 0.9))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity)
                    
                    HStack(spacing: 2 * uiScale) {
                        Text("±")
                            .font(.system(size: 14 * uiScale, weight: .regular))
                            .foregroundColor(.gray)
                            .italic()
                        
                        TextField("Step", value: $counter.step, format: .number)
                            .font(.system(size: 14 * uiScale, weight: .regular))
                            .foregroundColor(.gray)
                            .italic()
                            .textFieldStyle(.plain)
                            .frame(width: 40 * uiScale)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 16 * uiScale) {
                    if isPopout {
                        NonActivatingButton(action: {
                            counter.count += counter.step
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 36 * uiScale, weight: .bold))
                                .frame(width: 60 * uiScale, height: 60 * uiScale)
                                .background(incrementBgColor)
                                .foregroundColor(incrementFgColor)
                                .clipShape(Circle())
                        }
                        
                        NonActivatingButton(action: {
                            counter.count -= counter.step
                        }) {
                            Image(systemName: "minus")
                                .font(.system(size: 28 * uiScale, weight: .bold))
                                .frame(width: 48 * uiScale, height: 48 * uiScale)
                                .background(decrementBgColor)
                                .foregroundColor(decrementFgColor)
                                .clipShape(Circle())
                        }
                    } else {
                        Button(action: {
                            counter.count += counter.step
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 36 * uiScale, weight: .bold))
                                .frame(width: 60 * uiScale, height: 60 * uiScale)
                                .background(incrementBgColor)
                                .foregroundColor(incrementFgColor)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            counter.count -= counter.step
                        }) {
                            Image(systemName: "minus")
                                .font(.system(size: 28 * uiScale, weight: .bold))
                                .frame(width: 48 * uiScale, height: 48 * uiScale)
                                .background(decrementBgColor)
                                .foregroundColor(decrementFgColor)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                // .padding(.trailing, 20)
            }
            .padding(.bottom, 16 * uiScale)
        }
        .padding(16 * uiScale)
        .background(cardBackgroundColor)
        .cornerRadius(16 * uiScale)
        .shadow(color: Color.black.opacity(0.3), radius: 8 * uiScale, x: 0, y: 4 * uiScale)
    }
}

#Preview {
    ContentView()
        .environmentObject(CounterStore())
        .frame(width: 400, height: 600)
}

struct NonActivatingButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    
    @State private var isPressed = false
    
    var body: some View {
        label()
            .opacity(isPressed ? 0.7 : 1.0)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .overlay(
                NonActivatingView(isPressed: $isPressed, action: action)
            )
    }
}

private struct NonActivatingView: NSViewRepresentable {
    @Binding var isPressed: Bool
    var action: () -> Void
    
    func makeNSView(context: Context) -> EventTrackingView {
        let view = EventTrackingView()
        view.onMouseDown = {
            DispatchQueue.main.async { isPressed = true }
        }
        view.onMouseUp = {
            DispatchQueue.main.async { 
                isPressed = false
                action()
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: EventTrackingView, context: Context) {
        nsView.onMouseDown = {
            DispatchQueue.main.async { isPressed = true }
        }
        nsView.onMouseUp = {
            DispatchQueue.main.async { 
                isPressed = false
                action()
            }
        }
    }
}

private class EventTrackingView: NSView {
    var onMouseDown: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var isTrackingClick = false
    
    override var acceptsFirstResponder: Bool { false }
    
    // Returning true here is what tells macOS "this view handles the click, 
    // but don't activate the application if it's currently in the background".
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        isTrackingClick = true
        onMouseDown?()
    }
    
    override func mouseUp(with event: NSEvent) {
        if isTrackingClick {
            isTrackingClick = false
            onMouseUp?()
        }
    }
}
