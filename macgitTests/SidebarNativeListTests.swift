// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import XCTest
@testable import macgit

@MainActor
final class SidebarNativeListTests: XCTestCase {
    private func input(branch: String = "main") -> SidebarNativeInput {
        .init(trees: [], expanded: [], flags: [], currentBranch: branch, headHash: "",
            sync: [:], fallbackSync: nil, integration: nil, syncingBranches: [], remotes: [],
            remoteBranches: [:], upstream: [:], gitFlow: GitFlowConfiguration(),
            gitFlowCommands: GitFlowCommandState(isEnabled: false, currentKind: nil,
                operationInProgress: false, hasPendingFinish: false, hasInvalidRecoveryState: false),
            worktrees: [], stashes: [], submodules: [], subtrees: [])
    }

    private func list(input: SidebarNativeInput? = nil, selection: SidebarSelection? = nil,
                      rows: @escaping () -> [SidebarNativeRow]) -> SidebarNativeList {
        .init(repositoryURL: URL(fileURLWithPath: "/tmp/sidebar-native-tests"),
            input: input ?? self.input(), makeRows: rows, selection: selection, textScale: 1,
            backgroundMenu: { SidebarNativeMenu() }, acceptDrop: { _, _, _ in false })
    }

    private func row(_ name: String, select: (() -> Void)? = nil) -> SidebarNativeRow {
        .init(id: .init(section: .branches, kind: "ref", key: name),
            appearance: .init(title: name), selection: .branch(name), select: select)
    }

    private func row(_ name: String, select: (() -> Void)? = nil,
                     activate: (() -> Void)?) -> SidebarNativeRow {
        .init(id: .init(section: .branches, kind: "ref", key: name),
            appearance: .init(title: name), selection: .branch(name),
            select: select, activate: activate)
    }

    private func coordinator(_ list: SidebarNativeList) -> (SidebarNativeList.Coordinator, SidebarNativeList.Table) {
        let owner = list.makeCoordinator()
        let table = SidebarNativeList.Table(frame: NSRect(x: 0, y: 0, width: 280, height: 300))
        table.headerView = nil
        table.addTableColumn(NSTableColumn(identifier: .init("test")))
        table.delegate = owner
        table.dataSource = owner
        table.owner = owner
        owner.table = table
        owner.update(list)
        return (owner, table)
    }

    func testIssueRowsFollowHostedProvider() {
        XCTAssertEqual(SidebarSection.issueRows(hostedProvider: nil).map(\.item), [.jira])
        for (provider, title) in [(HostedIssueProvider.github, "GitHub Issues"), (.gitlab, "GitLab Issues"),
                                  (.bitbucket, "Bitbucket Issues"), (.azureBoards, "Azure Boards")] {
            let rows = SidebarSection.issueRows(hostedProvider: provider)
            XCTAssertEqual(rows.map(\.item), [.jira, .hostedIssues])
            XCTAssertEqual(rows.last?.title, title)
            XCTAssertEqual(rows.last?.icon, provider.iconName)
        }
    }

    func testHostedProviderChangeInvalidatesNativeInput() {
        var github = input(branch: "main")
        github.hostedIssueProvider = .github
        var gitlab = github
        gitlab.hostedIssueProvider = .gitlab
        XCTAssertNotEqual(github, gitlab)
    }

    func testIssuesSectionIsVisibleByDefaultAndJiraIsNotAWorkspaceRow() {
        let suiteName = "SidebarNativeListTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)

        XCTAssertTrue(state.showIssues)
        XCTAssertFalse(SidebarSection.visibleWorkspaceItems(appState: state).contains(.jira))
        XCTAssertTrue(SidebarSection.visibleWorkspaceItems(appState: state).contains(.pullRequests))
    }

    func testSelectionDoesNotRebuildTenThousandRows() {
        var builds = 0
        let rows = (0..<10_000).map { row("branch-\($0)") }
        let initial = list { builds += 1; return rows }
        let (owner, table) = coordinator(initial)
        owner.update(list(selection: .branch("branch-9999")) { builds += 1; return rows })
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(table.selectedRow, 9999)
        XCTAssertEqual(owner.rows.count, 10_000)
    }

    func testHiddenSelectionIsNotPublishedAsDeselection() {
        var selections = 0
        let initial = list(selection: .branch("main")) { [self.row("main") { selections += 1 }] }
        let (owner, table) = coordinator(initial)
        owner.update(list(input: input(branch: "changed"), selection: .branch("main")) { [] })
        XCTAssertEqual(table.selectedRow, -1)
        XCTAssertEqual(owner.parent.selection, .branch("main"))
        XCTAssertEqual(selections, 0)
    }

    func testReorderRestoresSemanticSelectionWithoutDispatch() {
        var selections = 0
        let first = row("first") { selections += 1 }
        let second = row("second") { selections += 1 }
        let (owner, table) = coordinator(list(selection: .branch("second")) { [first, second] })
        owner.update(list(input: input(branch: "changed"), selection: .branch("second")) { [second, first] })
        XCTAssertEqual(table.selectedRow, 0)
        XCTAssertEqual(selections, 0)
    }

    func testPrimaryPressSelectsOnlyAfterClickCompletes() {
        var selections = 0
        let branch = row("feature") { selections += 1 }
        let (owner, table) = coordinator(list { [branch] })

        XCTAssertFalse(owner.beginPrimaryClick(row: 0, at: 10))
        XCTAssertEqual(selections, 0)
        XCTAssertEqual(table.selectedRow, -1)

        owner.completePrimaryClick(row: 0, at: 10.1)
        XCTAssertEqual(selections, 1)
        XCTAssertEqual(table.selectedRow, 0)
    }

    func testSecondMouseDownActivatesSameBranchWithinForkStyleWindow() {
        var selections = 0, activations = 0
        let branch = row("feature", select: { selections += 1 }, activate: { activations += 1 })
        let (owner, _) = coordinator(list { [branch] })

        owner.completePrimaryClick(row: 0, at: 10)

        XCTAssertTrue(owner.beginPrimaryClick(row: 0, at: 10.79))
        XCTAssertEqual(selections, 1)
        XCTAssertEqual(activations, 1)
    }

    func testExpiredOrDifferentSecondPressDoesNotActivate() {
        var activations = 0
        let first = row("first", activate: { activations += 1 })
        let second = row("second", activate: { activations += 1 })
        let (owner, _) = coordinator(list { [first, second] })

        owner.completePrimaryClick(row: 0, at: 10)
        XCTAssertFalse(owner.beginPrimaryClick(row: 1, at: 10.4))
        XCTAssertFalse(owner.beginPrimaryClick(row: 0, at: 10.7))

        owner.completePrimaryClick(row: 0, at: 20)
        XCTAssertFalse(owner.beginPrimaryClick(row: 0, at: 20.81))
        XCTAssertEqual(activations, 0)
    }

    func testIdentitySeparatesFoldersAndRefNamespaces() {
        let branch = SidebarNativeRow.ID(section: .branches, kind: "ref", key: "release")
        let folder = SidebarNativeRow.ID(section: .branches, kind: "folder", key: "release")
        let tag = SidebarNativeRow.ID(section: .tags, kind: "ref", key: "release")
        XCTAssertEqual(Set([branch, folder, tag]).count, 3)
    }

    func testMenuIsCreatedOnlyForRequestedRowAndInvalidatedAfterRefresh() {
        var builds = 0, actions = 0
        var target = row("target")
        target.menu = {
            builds += 1
            let menu = SidebarNativeMenu()
            menu.item("Run") { actions += 1 }
            return menu
        }
        let (owner, table) = coordinator(list { [target] })
        XCTAssertEqual(builds, 0)
        let menu = owner.menu(row: 0)
        XCTAssertEqual(builds, 1)
        owner.update(list(input: input(branch: "changed")) { [] })
        (menu.item(at: 0)?.representedObject as? SidebarNativeMenu.Action)?.invoke()
        XCTAssertEqual(actions, 0)
        withExtendedLifetime(table) {}
    }

    func testTrackingSubmenuIsLazyAndInheritsActionValidation() {
        let menu = SidebarNativeMenu()
        var builds = 0, actions = 0, valid = true
        menu.lazySubmenu("Tracking", enabled: true) { sub in
            builds += 1
            sub.item("origin/main") { actions += 1 }
        }
        menu.installGuard { valid }
        XCTAssertEqual(builds, 0)
        let sub = menu.item(at: 0)?.submenu as! SidebarNativeMenu
        sub.menuNeedsUpdate(sub)
        sub.menuNeedsUpdate(sub)
        XCTAssertEqual(builds, 1)
        valid = false
        (sub.item(at: 0)?.representedObject as? SidebarNativeMenu.Action)?.invoke()
        XCTAssertEqual(actions, 0)
    }

    func testCellReuseClearsBadgesSubtitleAndAccessory() {
        let cell = SidebarNativeList.Cell()
        cell.configure(.init(title: "First", subtitle: "path", badge: "HEAD", accessory: "plus", accessoryLabel: "Add"), scale: 1)
        cell.configure(.init(title: "Second"), scale: 1)
        XCTAssertEqual(cell.title.stringValue, "Second")
        XCTAssertEqual(cell.subtitle.stringValue, "")
        XCTAssertEqual(cell.badge.stringValue, "")
        XCTAssertTrue(cell.button.isHidden)
    }
}
