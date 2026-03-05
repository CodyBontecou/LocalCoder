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

    init() {
        currentPath = FileService.shared.projectsRoot.path
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
        currentPath = fileService.projectsRoot.path
        refresh()
    }

    var currentDirName: String {
        URL(fileURLWithPath: currentPath).lastPathComponent
    }

    var isAtRoot: Bool {
        currentPath == fileService.projectsRoot.path
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
