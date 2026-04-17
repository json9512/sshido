import XCTest
@testable import sshidoModels
@testable import sshidoCore

@MainActor
final class AppRouterTests: XCTestCase {
    func testPushAppends() {
        let r = AppRouter()
        let host = RemoteHost(name: "t", hostname: "h", username: "u")
        r.push(.host(host))
        XCTAssertEqual(r.path.count, 1)
        if case .host(let h) = r.path[0] {
            XCTAssertEqual(h.id, host.id)
        } else { XCTFail("expected .host destination") }
    }

    func testPopToRootClearsBothStacks() {
        let r = AppRouter()
        let host = RemoteHost(name: "t", hostname: "h", username: "u")
        let session = Session(hostID: host.id, title: "s")
        r.path = [.host(host), .session(session)]
        r.detailPath = [.session(session)]
        r.popToRoot()
        XCTAssertTrue(r.path.isEmpty)
        XCTAssertTrue(r.detailPath.isEmpty)
    }

    func testOpenSessionReplacesAtomically() {
        let r = AppRouter()
        let host = RemoteHost(name: "t", hostname: "h", username: "u")
        let session = Session(hostID: host.id, title: "s")
        r.path = [.host(host)]
        r.openSession(session, host: host)
        XCTAssertEqual(r.path.count, 2)
        XCTAssertEqual(r.detailPath.count, 1)
        XCTAssertEqual(r.selectedHost?.id, host.id)
    }

    func testSheetIdIsStable() {
        let h = RemoteHost(name: "t", hostname: "h", username: "u")
        XCTAssertEqual(AppRouter.Sheet.settings.id, "settings")
        XCTAssertEqual(AppRouter.Sheet.addHost.id, "addHost")
        XCTAssertEqual(AppRouter.Sheet.editHost(h).id, "editHost-\(h.id.uuidString)")
    }
}
