//
//  SidebarSettingsStore.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

struct SidebarSectionState: Codable {
    var issuesExpanded: Bool = true
    var gitFlowExpanded: Bool = true
    var branchesExpanded: Bool = false
    var tagsExpanded: Bool = true
    var remotesExpanded: Bool = true
    var stashesExpanded: Bool = true
    var worktreesExpanded: Bool = false
    var submodulesExpanded: Bool = true
    var subtreesExpanded: Bool = true

    init(
        issuesExpanded: Bool = true,
        gitFlowExpanded: Bool = true,
        branchesExpanded: Bool = false,
        tagsExpanded: Bool = true,
        remotesExpanded: Bool = true,
        stashesExpanded: Bool = true,
        worktreesExpanded: Bool = false,
        submodulesExpanded: Bool = true,
        subtreesExpanded: Bool = true
    ) {
        self.issuesExpanded = issuesExpanded
        self.gitFlowExpanded = gitFlowExpanded
        self.branchesExpanded = branchesExpanded
        self.tagsExpanded = tagsExpanded
        self.remotesExpanded = remotesExpanded
        self.stashesExpanded = stashesExpanded
        self.worktreesExpanded = worktreesExpanded
        self.submodulesExpanded = submodulesExpanded
        self.subtreesExpanded = subtreesExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issuesExpanded = try container.decodeIfPresent(Bool.self, forKey: .issuesExpanded) ?? true
        gitFlowExpanded = try container.decodeIfPresent(Bool.self, forKey: .gitFlowExpanded) ?? true
        branchesExpanded = try container.decodeIfPresent(Bool.self, forKey: .branchesExpanded) ?? false
        tagsExpanded = try container.decodeIfPresent(Bool.self, forKey: .tagsExpanded) ?? true
        remotesExpanded = try container.decodeIfPresent(Bool.self, forKey: .remotesExpanded) ?? true
        stashesExpanded = try container.decodeIfPresent(Bool.self, forKey: .stashesExpanded) ?? true
        worktreesExpanded = try container.decodeIfPresent(Bool.self, forKey: .worktreesExpanded) ?? false
        submodulesExpanded = try container.decodeIfPresent(Bool.self, forKey: .submodulesExpanded) ?? true
        subtreesExpanded = try container.decodeIfPresent(Bool.self, forKey: .subtreesExpanded) ?? true
    }
}

final class SidebarSettingsStore {
    static let shared = SidebarSettingsStore()
    private let key = "dev.thanhtran.macgit.sidebarSettings"

    private var settings: [String: SidebarSectionState] = [:]

    private init() {
        load()
    }

    func state(for repositoryPath: String) -> SidebarSectionState {
        settings[repositoryPath] ?? SidebarSectionState()
    }

    func update(for repositoryPath: String, state: SidebarSectionState) {
        settings[repositoryPath] = state
        save()
    }

    func toggleSection(_ section: SidebarSection, for repositoryPath: String) {
        var state = self.state(for: repositoryPath)
        switch section {
        case .issues:
            state.issuesExpanded.toggle()
        case .gitFlow:
            state.gitFlowExpanded.toggle()
        case .branches:
            state.branchesExpanded.toggle()
        case .tags:
            state.tagsExpanded.toggle()
        case .remotes:
            state.remotesExpanded.toggle()
        case .stashes:
            state.stashesExpanded.toggle()
        case .worktrees:
            state.worktreesExpanded.toggle()
        case .submodules:
            state.submodulesExpanded.toggle()
        case .subtrees:
            state.subtreesExpanded.toggle()
        default:
            break
        }
        update(for: repositoryPath, state: state)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SidebarSectionState].self, from: data) else {
            return
        }
        settings = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
