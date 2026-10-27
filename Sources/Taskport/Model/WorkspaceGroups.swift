import Foundation
import SwiftUI

extension WorkspaceStore {
    func validateGroup(_ id: UUID?) throws {
        guard id == nil || document.groups.contains(where: { $0.id == id }) else {
            throw WorkspaceError("Group not found. Choose an existing group or Projects.")
        }
    }

    @discardableResult
    func saveGroup(name: String, replacing original: ProjectGroup? = nil, assigning projectID: UUID? = nil) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkspaceError("Enter a group name.") }
        guard name.caseInsensitiveCompare("Projects") != .orderedSame else {
            throw WorkspaceError("Projects is the default group. Choose another name.")
        }
        guard projectID == nil || document.projects.contains(where: { $0.id == projectID }) else {
            throw WorkspaceError("The project was removed. No group has been created.")
        }
        guard !document.groups.contains(where: { $0.id != original?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw WorkspaceError("A group with this name already exists.")
        }
        let id = original?.id ?? UUID()
        if let original {
            guard let current = document.groups.first(where: { $0.id == id }), current.name == original.name else {
                throw WorkspaceError("This group changed or was removed. Reopen the editor before saving.")
            }
        }
        try commit { document in
            if let index = document.groups.firstIndex(where: { $0.id == id }) {
                document.groups[index].name = name
            } else { document.groups.append(ProjectGroup(id: id, name: name)) }
            if let project = document.projects.firstIndex(where: { $0.id == projectID }) {
                document.projects[project].groupID = id
                if let group = document.groups.firstIndex(where: { $0.id == id }) { document.groups[group].isCollapsed = false }
            }
        }
        return id
    }

    func setGroupCollapsed(_ id: UUID?, _ collapsed: Bool) throws {
        try validateGroup(id)
        try commit { document in
            if let index = document.groups.firstIndex(where: { $0.id == id }) {
                document.groups[index].isCollapsed = collapsed
            } else { document.projectsGroupCollapsed = collapsed }
        }
    }

    var hasExpandedGroups: Bool {
        !document.groups.isEmpty && (document.groups.contains { !$0.isCollapsed } || document.projectsGroupCollapsed != true)
    }

    func setAllGroupsCollapsed(_ collapsed: Bool) throws {
        guard !document.groups.isEmpty else { return }
        try commit { document in
            for index in document.groups.indices { document.groups[index].isCollapsed = collapsed }
            document.projectsGroupCollapsed = collapsed
        }
    }

    func moveGroup(_ id: UUID, relativeTo targetID: UUID?, after: Bool = false) throws {
        try validateGroup(id)
        try validateGroup(targetID)
        guard id != targetID else { return }
        try commit { document in
            let index = document.groups.firstIndex(where: { $0.id == id })!
            let group = document.groups.remove(at: index)
            let target = document.groups.firstIndex(where: { $0.id == targetID })
            document.groups.insert(group, at: target.map { $0 + (after ? 1 : 0) } ?? document.groups.count)
        }
    }

    func removeGroup(_ id: UUID) throws {
        try validateGroup(id)
        try commit { document in
            document.groups.removeAll { $0.id == id }
            if document.projects.contains(where: { $0.groupID == id }) { document.projectsGroupCollapsed = false }
            for index in document.projects.indices where document.projects[index].groupID == id {
                document.projects[index].groupID = nil
            }
        }
    }

    func moveProject(_ id: UUID, toGroup groupID: UUID?) throws {
        try validateGroup(groupID)
        guard document.projects.contains(where: { $0.id == id }) else { throw WorkspaceError("Project not found.") }
        try commit { document in
            if let index = document.projects.firstIndex(where: { $0.id == id }) { document.projects[index].groupID = groupID }
            if let group = document.groups.firstIndex(where: { $0.id == groupID }) { document.groups[group].isCollapsed = false }
            else { document.projectsGroupCollapsed = false }
        }
    }

    func moveProjects(inGroup groupID: UUID?, from offsets: IndexSet, to destination: Int) {
        let indices = document.projects.indices.filter { document.projects[$0].groupID == groupID }
        guard offsets.allSatisfy({ indices.indices.contains($0) }), (0...indices.count).contains(destination) else { return }
        var ordered = indices.map { document.projects[$0] }
        ordered.move(fromOffsets: offsets, toOffset: destination)
        perform {
            try commit { document in
                for (index, project) in zip(indices, ordered) { document.projects[index] = project }
            }
        }
    }
}
