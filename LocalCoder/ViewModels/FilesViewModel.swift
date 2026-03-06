import Foundation
import SwiftUI

@MainActor
final class FilesViewModel: ObservableObject {
    @Published var files: [FileItem] = []
    @Published var currentPath: String
    @Published var pathStack: [String] = []
    @Published var selectedFile: String?
    @Published var fileContent: String = ""
    @Published var isEditing = false
    @Published var error: String?

    private let fileService = FileService.shared
    private let gitSync = GitSyncManager.shared

    /// The root directory - uses active git repo if available, otherwise FileService.projectsRoot
    var rootPath: String {
        if let repoURL = gitSync.activeRepoURL {
            return repoURL.path
        }
        return fileService.projectsRoot.path
    }

    init() {
        // Start at the active repo if one exists, otherwise use FileService root
        if let repoURL = GitSyncManager.shared.activeRepoURL {
            currentPath = repoURL.path
        } else {
            currentPath = FileService.shared.projectsRoot.path
        }
        refresh()
    }

    /// Call this when the active repo changes to update the view
    func syncWithActiveRepo() {
        let newRoot = rootPath
        // If we're not within the new root, navigate to it
        if !currentPath.hasPrefix(newRoot) {
            pathStack.removeAll()
            currentPath = newRoot
        }
        refresh()
    }

    func refresh() {
        files = fileService.listFiles(at: currentPath)
    }

    func navigateTo(_ item: FileItem) {
        if item.isDirectory {
            pathStack.append(currentPath)
            currentPath = item.path
            refresh()
        } else {
            selectedFile = item.path
            fileContent = fileService.readFile(at: item.path) ?? ""
            isEditing = true
        }
    }

    func navigateBack() {
        if let previous = pathStack.popLast() {
            currentPath = previous
            refresh()
        }
    }

    func navigateToRoot() {
        pathStack.removeAll()
        currentPath = rootPath
        refresh()
    }

    var currentDirName: String {
        URL(fileURLWithPath: currentPath).lastPathComponent
    }

    var isAtRoot: Bool {
        currentPath == rootPath
    }

    func saveFile() {
        guard let path = selectedFile else { return }
        do {
            try fileService.writeFile(content: fileContent, to: path)
            isEditing = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createNewFile(name: String, content: String = "") {
        let path = URL(fileURLWithPath: currentPath).appendingPathComponent(name).path
        do {
            try fileService.writeFile(content: content, to: path)
            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createNewFolder(name: String) {
        do {
            try fileService.createDirectory(named: name, at: currentPath)
            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteItem(_ item: FileItem) {
        do {
            try fileService.deleteItem(at: item.path)
            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func renameItem(_ item: FileItem, to newName: String) {
        do {
            try fileService.renameItem(at: item.path, to: newName)
            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
