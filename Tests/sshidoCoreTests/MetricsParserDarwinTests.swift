import XCTest
@testable import sshidoCore
import sshidoModels

final class MetricsParserDarwinTests: XCTestCase {

    func testLoadAvg() throws {
        let load = try XCTUnwrap(DarwinMetricsParser.parseLoadAvg("{ 1.23 1.45 1.67 }\n"))
        XCTAssertEqual(load.one, 1.23, accuracy: 0.001)
        XCTAssertEqual(load.five, 1.45, accuracy: 0.001)
        XCTAssertEqual(load.fifteen, 1.67, accuracy: 0.001)
    }

    func testLoadAvgRejectsGarbage() {
        XCTAssertNil(DarwinMetricsParser.parseLoadAvg("nope"))
    }

    func testBootTime() throws {
        let raw = "{ sec = 1700000000, usec = 0 } Thu Mar  5 12:34:56 2024"
        let bt = try XCTUnwrap(DarwinMetricsParser.parseBootTime(raw))
        XCTAssertEqual(bt.timeIntervalSince1970, 1700000000, accuracy: 0.001)
    }

    func testBootTimeMinimal() throws {
        let bt = try XCTUnwrap(DarwinMetricsParser.parseBootTime("{ sec = 1234567890, usec = 0 }"))
        XCTAssertEqual(bt.timeIntervalSince1970, 1234567890, accuracy: 0.001)
    }

    func testBootTimeRejectsGarbage() {
        XCTAssertNil(DarwinMetricsParser.parseBootTime("nope"))
    }

    func testVMStatUsesHeaderPageSize() throws {
        let raw = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                               1000.
        Pages active:                             2000.
        Pages inactive:                            500.
        Pages speculative:                         100.
        Pages throttled:                             0.
        Pages wired down:                          800.
        Pages purgeable:                            50.
        Pages occupied by compressor:              200.
        """
        let used = try XCTUnwrap(DarwinMetricsParser.parseVMStat(raw, pageSize: 4096))
        // active(2000) + wired(800) + compressor(200) = 3000 pages * 16384 bytes
        XCTAssertEqual(used, 3000 * 16384)
    }

    func testVMStatFallsBackToProvidedPageSize() throws {
        let raw = """
        Pages active:                             2000.
        Pages wired down:                          800.
        Pages occupied by compressor:              200.
        """
        let used = try XCTUnwrap(DarwinMetricsParser.parseVMStat(raw, pageSize: 4096))
        XCTAssertEqual(used, 3000 * 4096)
    }

    func testVMStatLegacyCompressorKey() throws {
        let raw = """
        Mach Virtual Memory Statistics: (page size of 4096 bytes)
        Pages active:                             1000.
        Pages wired down:                          500.
        Pages stored in compressor:                100.
        """
        let used = try XCTUnwrap(DarwinMetricsParser.parseVMStat(raw, pageSize: 4096))
        XCTAssertEqual(used, 1600 * 4096)
    }

    func testSwap() throws {
        let raw = "total = 4096.00M  used = 1024.00M  free = 3072.00M  (encrypted)"
        let sw = try XCTUnwrap(DarwinMetricsParser.parseSwap(raw))
        XCTAssertEqual(sw.total, UInt64(4096.0 * 1024 * 1024))
        XCTAssertEqual(sw.used, UInt64(1024.0 * 1024 * 1024))
    }

    func testSwapEmpty() throws {
        let sw = try XCTUnwrap(DarwinMetricsParser.parseSwap("total = 0.00M  used = 0.00M  free = 0.00M  (encrypted)"))
        XCTAssertEqual(sw.total, 0)
        XCTAssertEqual(sw.used, 0)
    }

    func testTopCPU() throws {
        let cpu = try XCTUnwrap(DarwinMetricsParser.parseTopCPU("CPU usage: 5.12% user, 3.45% sys, 91.43% idle"))
        XCTAssertEqual(cpu.userPercent, 5.12, accuracy: 0.001)
        XCTAssertEqual(cpu.systemPercent, 3.45, accuracy: 0.001)
        XCTAssertEqual(cpu.idlePercent, 91.43, accuracy: 0.001)
        XCTAssertEqual(cpu.totalPercent, 5.12 + 3.45, accuracy: 0.001)
        XCTAssertNil(cpu.iowaitPercent)
    }

    func testTopCPURejectsMissingFields() {
        XCTAssertNil(DarwinMetricsParser.parseTopCPU("CPU usage: 5% user"))
    }

    func testNetstatIBAggregatesByLinkRow() {
        let raw = """
        Name  Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0   16384 <Link#1>                          1234     0      12345     1234     0      12345     0
        lo0   16384 127           localhost            1234     -      12345     1234     -      12345     -
        en0   1500  <Link#5>      aa:bb:cc:dd:ee:ff    5678     0     567890     1234     0     123456     0
        en0   1500  192.168.1     192.168.1.5          5678     -     567890     1234     -     123456     -
        """
        let counters = DarwinMetricsParser.parseNetstatIB(raw)
        XCTAssertEqual(counters.count, 2)
        XCTAssertEqual(counters["lo0"]?.rxBytes, 12345)
        XCTAssertEqual(counters["lo0"]?.txBytes, 12345)
        XCTAssertEqual(counters["en0"]?.rxBytes, 567890)
        XCTAssertEqual(counters["en0"]?.txBytes, 123456)
    }

    func testNetstatIBHandlesEmptyAddressColumn() {
        // Loopback has no Address token; collapses to 10 whitespace-separated fields.
        let raw = """
        Name  Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0   16384 <Link#1>                          1234     0      12345     1234     0      12345     0
        """
        let counters = DarwinMetricsParser.parseNetstatIB(raw)
        XCTAssertEqual(counters["lo0"]?.rxBytes, 12345)
        XCTAssertEqual(counters["lo0"]?.txBytes, 12345)
    }

    func testDFParsesWithoutTypeColumn() {
        let raw = """
        Filesystem    1024-blocks      Used Available Capacity  Mounted on
        /dev/disk1s1    480000000 200000000 280000000     42%   /
        /dev/disk1s5    480000000   1000000 479000000      1%   /System/Volumes/Data
        """
        let disks = DarwinMetricsParser.parseDF(raw)
        XCTAssertEqual(disks.count, 2)
        XCTAssertEqual(disks[0].mountPoint, "/")
        XCTAssertEqual(disks[0].fsType, "")
        XCTAssertEqual(disks[0].filesystem, "/dev/disk1s1")
        XCTAssertEqual(disks[0].totalBytes, 480000000 * 1024)
        XCTAssertEqual(disks[0].usedBytes, 200000000 * 1024)
        XCTAssertEqual(disks[0].availableBytes, 280000000 * 1024)
        XCTAssertEqual(disks[1].mountPoint, "/System/Volumes/Data")
    }
}
