import XCTest
@testable import sshidoModels
@testable import sshidoCore

final class ShortcutGroupStoreTests: XCTestCase {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshido-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testGroupCodableRoundTrip() throws {
        let id = UUID()
        let scId = UUID()
        let group = ShortcutGroup(
            id: id,
            label: "Claude",
            sfSymbol: "sparkles",
            shortcuts: [
                CustomShortcut(id: scId, label: "⌃A", bytes: [0x01]),
                CustomShortcut(label: "slash", bytes: [0x2f])
            ]
        )
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(ShortcutGroup.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.label, "Claude")
        XCTAssertEqual(decoded.sfSymbol, "sparkles")
        XCTAssertEqual(decoded.shortcuts.count, 2)
        XCTAssertEqual(decoded.shortcuts[0].id, scId)
        XCTAssertEqual(decoded.shortcuts[0].bytes, [0x01])
        XCTAssertEqual(decoded.shortcuts[1].label, "slash")
    }

    func testFreshInstallSeedsClaudeAndTmux() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ShortcutGroupStore(directory: dir)
        let groups = await store.groups

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "Claude")
        XCTAssertEqual(groups[1].label, "TMUX")
        XCTAssertEqual(groups[1].shortcuts.first?.label, "Prefix")
        XCTAssertEqual(groups[1].shortcuts.first?.bytes, [0x02])

        let persisted = dir.appendingPathComponent("shortcut-groups.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted.path))
    }

    func testMigrationFromLegacyFlatShortcuts() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacy = [
            CustomShortcut(label: "/",  bytes: [0x2f]),
            CustomShortcut(label: "#",  bytes: [0x23]),
            CustomShortcut(label: "deploy", text: "deploy")
        ]
        let legacyURL = dir.appendingPathComponent("shortcuts.json")
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        let store = ShortcutGroupStore(directory: dir)
        let groups = await store.groups

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "Custom")
        XCTAssertEqual(groups[0].sfSymbol, "command")
        XCTAssertEqual(groups[0].shortcuts.map(\.label), ["/", "#", "deploy"])
        XCTAssertEqual(groups[1].label, "TMUX")

        // Legacy file must be left untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testEmptyLegacyFallsBackToFreshSeed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacyURL = dir.appendingPathComponent("shortcuts.json")
        try JSONEncoder().encode([CustomShortcut]()).write(to: legacyURL)

        let store = ShortcutGroupStore(directory: dir)
        let groups = await store.groups

        XCTAssertEqual(groups.map(\.label), ["Claude", "TMUX"])
    }

    func testExistingGroupsFileIsLoadedAsIs() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let onlyOneGroup = [
            ShortcutGroup(label: "MyOnly", sfSymbol: nil,
                          shortcuts: [CustomShortcut(label: "x", bytes: [0x78])])
        ]
        let url = dir.appendingPathComponent("shortcut-groups.json")
        try JSONEncoder().encode(onlyOneGroup).write(to: url)

        let store = ShortcutGroupStore(directory: dir)
        let groups = await store.groups

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].label, "MyOnly")
    }

    func testNoReseedAfterTmuxDeletion() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = ShortcutGroupStore(directory: dir)
        let seeded = await store1.groups
        let tmuxId = try XCTUnwrap(seeded.first { $0.label == "TMUX" }?.id)
        try await store1.removeGroup(id: tmuxId)

        let store2 = ShortcutGroupStore(directory: dir)
        let after = await store2.groups

        XCTAssertFalse(after.contains { $0.label == "TMUX" })
    }

    func testAddRemoveUpdateMoveGroup() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ShortcutGroupStore(directory: dir)

        let extra = ShortcutGroup(label: "Extra", sfSymbol: "bolt",
                                  shortcuts: [CustomShortcut(label: "e", bytes: [0x65])])
        try await store.addGroup(extra)
        var after = await store.groups
        XCTAssertEqual(after.last?.label, "Extra")

        var renamed = extra
        renamed.label = "Extra2"
        try await store.updateGroup(renamed)
        after = await store.groups
        XCTAssertEqual(after.last?.label, "Extra2")

        try await store.moveGroup(from: IndexSet(integer: after.count - 1), to: 0)
        after = await store.groups
        XCTAssertEqual(after.first?.label, "Extra2")

        try await store.removeGroup(id: extra.id)
        after = await store.groups
        XCTAssertFalse(after.contains { $0.id == extra.id })
    }

    func testAddUpdateMoveRemoveShortcutInsideGroup() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ShortcutGroupStore(directory: dir)

        var groups = await store.groups
        let group = try XCTUnwrap(groups.first { $0.label == "Claude" })

        let newSC = CustomShortcut(label: "ping", text: "ping")
        try await store.addShortcut(toGroup: group.id, newSC)
        groups = await store.groups
        var fresh = try XCTUnwrap(groups.first { $0.id == group.id })
        XCTAssertEqual(fresh.shortcuts.last?.label, "ping")

        var edited = newSC
        edited.label = "ping!"
        try await store.updateShortcut(inGroup: group.id, edited)
        groups = await store.groups
        fresh = try XCTUnwrap(groups.first { $0.id == group.id })
        XCTAssertEqual(fresh.shortcuts.last?.label, "ping!")

        let endIndex = fresh.shortcuts.count - 1
        try await store.moveShortcut(inGroup: group.id,
                                     from: IndexSet(integer: endIndex),
                                     to: 0)
        groups = await store.groups
        fresh = try XCTUnwrap(groups.first { $0.id == group.id })
        XCTAssertEqual(fresh.shortcuts.first?.id, newSC.id)

        try await store.removeShortcut(fromGroup: group.id, shortcutId: newSC.id)
        groups = await store.groups
        fresh = try XCTUnwrap(groups.first { $0.id == group.id })
        XCTAssertFalse(fresh.shortcuts.contains { $0.id == newSC.id })
    }

    func testHotkeyLayoutOrderMergesGroupsAndIgnoresLegacyIds() async throws {
        let builtin = HotkeyButton.defaults
        let a = ShortcutGroup(label: "A", shortcuts: [])
        let b = ShortcutGroup(label: "B", shortcuts: [])
        let groups = [a, b]

        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HotkeyLayoutStore()
        // The existing HotkeyLayoutStore uses shared application-support dir; its
        // ordered(...) logic is pure given the in-memory `order` array, which we
        // can drive indirectly via setOrder then verify merge behaviour.
        try await store.setOrder([
            "b:Tab",                     // existing builtin id
            "c:\(UUID().uuidString)",    // legacy flat-shortcut id — must be dropped
            "g:\(b.id.uuidString)"       // group b, should jump ahead of a
        ])
        let merged = await store.ordered(builtins: builtin, groups: groups)
        let ids = merged.map(\.id)

        let tabIdx = try XCTUnwrap(ids.firstIndex(of: "b:Tab"))
        let bIdx   = try XCTUnwrap(ids.firstIndex(of: "g:\(b.id.uuidString)"))
        let aIdx   = try XCTUnwrap(ids.firstIndex(of: "g:\(a.id.uuidString)"))
        XCTAssertLessThan(tabIdx, bIdx)
        XCTAssertLessThan(bIdx, aIdx, "group b should appear before a because it is in `order`")
        XCTAssertFalse(ids.contains { $0.hasPrefix("c:") })
    }

    func testParseByteAcceptsHexDecimalAndPrefixed() {
        XCTAssertEqual(ShortcutDisplay.parseByte("0x1b"), 0x1b)
        XCTAssertEqual(ShortcutDisplay.parseByte("0X1B"), 0x1b)
        XCTAssertEqual(ShortcutDisplay.parseByte("1b"),   0x1b)
        XCTAssertEqual(ShortcutDisplay.parseByte("ff"),   0xff)
        XCTAssertEqual(ShortcutDisplay.parseByte("27"),   27)
        XCTAssertEqual(ShortcutDisplay.parseByte("255"),  255)
        XCTAssertEqual(ShortcutDisplay.parseByte(" 0x01 "), 0x01)
    }

    func testParseByteRejectsInvalid() {
        XCTAssertNil(ShortcutDisplay.parseByte(""))
        XCTAssertNil(ShortcutDisplay.parseByte("256"))
        XCTAssertNil(ShortcutDisplay.parseByte("0xgg"))
        XCTAssertNil(ShortcutDisplay.parseByte("hello"))
        XCTAssertNil(ShortcutDisplay.parseByte("0x"))
        XCTAssertNil(ShortcutDisplay.parseByte("100h"))
    }

    func testDisplayBytes() {
        XCTAssertEqual(ShortcutDisplay.display([0x61, 0x62]), "ab")
        XCTAssertEqual(ShortcutDisplay.display([0x1b]), "\\x1b")
        XCTAssertEqual(ShortcutDisplay.display([0x02, 0x7c]), "\\x02\\x7c")
        // UTF-8 é = 0xc3 0xa9 — non-ASCII printable, still displayable as text
        XCTAssertEqual(ShortcutDisplay.display([0xc3, 0xa9]), "é")
    }
}
