import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import SwiftUI
import UniformTypeIdentifiers

struct Folder: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var parentId: UUID? // nil means root level
    var order: Int = 0 // For native List reordering
}

// Tree structure for native SwiftUI OutlineGroup / List(children:)
struct FolderNode: Identifiable, Hashable {
    let folder: Folder
    var children: [FolderNode]?
    
    var id: UUID { folder.id }
}

struct Counter: Identifiable, Codable, Equatable, Hashable, Transferable {
    var id = UUID()
    var name: String
    var count: Int
    var step: Int
    var windowIds: Set<String> = []
    var folderId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case id, name, count, step, windowIds, windowId, folderId
    }
    
    init(id: UUID = UUID(), name: String, count: Int, step: Int, windowIds: Set<String> = [], folderId: UUID? = nil) {
        self.id = id
        self.name = name
        self.count = count
        self.step = step
        self.windowIds = windowIds
        self.folderId = folderId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        count = try container.decode(Int.self, forKey: .count)
        step = try container.decode(Int.self, forKey: .step)
        
        if let ids = try? container.decodeIfPresent(Set<String>.self, forKey: .windowIds) {
            windowIds = ids
        } else if let singleId = try? container.decodeIfPresent(String.self, forKey: .windowId) {
            windowIds = [singleId]
        } else {
            windowIds = []
        }
        
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(count, forKey: .count)
        try container.encode(step, forKey: .step)
        try container.encode(windowIds, forKey: .windowIds)
        try container.encodeIfPresent(folderId, forKey: .folderId)
    }
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

class CounterStore: ObservableObject {
    @Published var counters: [Counter] = [] {
        didSet { saveCounters() }
    }
    
    @Published var folders: [Folder] = [] {
        didSet { saveFolders() }
    }
    
    var folderNodes: [FolderNode] {
        buildTree(parentId: nil)
    }
    
    func filteredFolderNodes(searchText: String) -> [FolderNode] {
        if searchText.isEmpty { return folderNodes }
        return filterTree(nodes: folderNodes, searchText: searchText)
    }
    
    private let saveCountersKey = "SavedCounters"
    private let saveFoldersKey = "SavedFolders"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: saveCountersKey) {
            if let decoded = try? JSONDecoder().decode([Counter].self, from: data) {
                counters = decoded
            }
        }
        
        if let data = UserDefaults.standard.data(forKey: saveFoldersKey) {
            if let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
                folders = decoded
            }
        }
    }
    
    private func saveCounters() {
        if let encoded = try? JSONEncoder().encode(counters) {
            UserDefaults.standard.set(encoded, forKey: saveCountersKey)
        }
    }
    
    private func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(encoded, forKey: saveFoldersKey)
        }
    }
    
    func addCounter(name: String = "New Counter", folderId: UUID? = nil) {
        let counter = Counter(name: name, count: 0, step: 1, folderId: folderId)
        counters.append(counter)
    }
    
    func addFolder(name: String = "New Folder", parentId: UUID? = nil) {
        let siblings = getSubfolders(of: parentId)
        let newOrder = (siblings.map { $0.order }.max() ?? -1) + 1
        let folder = Folder(name: name, parentId: parentId, order: newOrder)
        folders.append(folder)
    }
    
    func removeCounters(at offsets: IndexSet) {
        counters.remove(atOffsets: offsets)
    }
    
    func getCounters(in folderId: UUID?) -> [Counter] {
        counters.filter { $0.folderId == folderId }
    }
    
    func getSubfolders(of parentId: UUID?) -> [Folder] {
        folders.filter { $0.parentId == parentId }.sorted { $0.order < $1.order }
    }
    
    // Recursive builder for internal usage
    private func buildTree(parentId: UUID?) -> [FolderNode] {
        let currentLevel = getSubfolders(of: parentId)
        return currentLevel.map { folder in
            let children = buildTree(parentId: folder.id)
            return FolderNode(folder: folder, children: children.isEmpty ? nil : children)
        }
    }
    
    // Recursive search filter
    private func filterTree(nodes: [FolderNode], searchText: String) -> [FolderNode] {
        var result: [FolderNode] = []
        
        for node in nodes {
            // Check if folder name matches
            let nameMatches = node.folder.name.localizedCaseInsensitiveContains(searchText)
            
            // Check if any counters in this folder match
            let countersInFolder = getCounters(in: node.id)
            let countersMatch = countersInFolder.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            
            // Recursively filter children
            var filteredChildren: [FolderNode]? = nil
            if let children = node.children {
                let matchingChildren = filterTree(nodes: children, searchText: searchText)
                if !matchingChildren.isEmpty {
                    filteredChildren = matchingChildren
                }
            }
            
            // Keep node if it matches, its counters match, or its children match
            if nameMatches || countersMatch || (filteredChildren != nil) {
                // If it's kept solely because a nested child matched, we still need to preserve the tree structure down to that child
                result.append(FolderNode(folder: node.folder, children: filteredChildren))
            }
        }
        
        return result
    }
    
    func updateFolderName(id: UUID, newName: String) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].name = newName
        }
    }
    
    func moveCounter(id: UUID, toFolder folderId: UUID?) {
        if let index = counters.firstIndex(where: { $0.id == id }) {
            counters[index].folderId = folderId
            
            // Note: Since this changes nested view structures, trigger UI rebuild globally
            counters.append(counters.remove(at: index))
        }
    }
    
    func moveFolder(id: UUID, toParent parentId: UUID?) {
        if id == parentId { return }
        
        // Prevent infinite loops (dropping a parent into its own child)
        var current: UUID? = parentId
        while let curr = current {
            if curr == id { return } // Attempted drop into a descendant
            current = folders.first(where: { $0.id == curr })?.parentId
        }
        
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].parentId = parentId
            
            // Append at the end of the new parent's children
            let siblings = getSubfolders(of: parentId)
            folders[index].order = (siblings.map { $0.order }.max() ?? -1) + 1
            
            // Trigger UI update
            folders.append(folders.remove(at: index))
        }
    }
    
    // Native List Reordering
    func moveFolderNodes(from source: IndexSet, to destination: Int, parentId: UUID?) {
        var items = getSubfolders(of: parentId)
        items.move(fromOffsets: source, toOffset: destination)
        
        // Update order integers
        for (index, item) in items.enumerated() {
            if let storeIndex = folders.firstIndex(where: { $0.id == item.id }) {
                folders[storeIndex].order = index
            }
        }
        
        // Trigger UI update
        folders = folders
    }
    
    func getFolderPath(for folderId: UUID?) -> String {
        guard let folderId = folderId else { return "Root" }
        var currentId: UUID? = folderId
        var pathComponents: [String] = []
        
        // Prevent infinite loops just in case of corrupted nested loop data
        var visited = Set<UUID>()
        
        while let id = currentId, !visited.contains(id), let folder = folders.first(where: { $0.id == id }) {
            visited.insert(id)
            pathComponents.insert(folder.name, at: 0)
            currentId = folder.parentId
        }
        
        return "Root > " + pathComponents.joined(separator: " > ")
    }
    
    func deleteFolder(id: UUID) {
        var idsToDelete: Set<UUID> = [id]
        var queue = [id]
        
        while !queue.isEmpty {
            let currentId = queue.removeFirst()
            let subfolderIds = folders.filter { $0.parentId == currentId }.map { $0.id }
            idsToDelete.formUnion(subfolderIds)
            queue.append(contentsOf: subfolderIds)
        }
        
        counters.removeAll { $0.folderId != nil && idsToDelete.contains($0.folderId!) }
        folders.removeAll { idsToDelete.contains($0.id) }
    }
}
