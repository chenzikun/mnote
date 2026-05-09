import Foundation

struct WorkspaceNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case directory
        case markdownFile
    }

    let id: URL
    let url: URL
    let name: String
    let kind: Kind
    var children: [WorkspaceNode]

    var childNodes: [WorkspaceNode]? {
        children.isEmpty ? nil : children
    }
}
