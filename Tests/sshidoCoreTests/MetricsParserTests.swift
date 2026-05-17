import XCTest
@testable import sshidoCore
import sshidoModels

final class MetricsParserTests: XCTestCase {

    // MARK: /proc/stat

    func testStatParsesCpuJiffies() {
        let raw = "cpu  12345 678 9012 345678 901 23 4567 89 0 0\ncpu0 100 0 200 1000 0 0 0 0 0 0"
        let snap = LinuxMetricsParser.parseStat(raw)
        XCTAssertEqual(snap?.user, 12345)
        XCTAssertEqual(snap?.nice, 678)
        XCTAssertEqual(snap?.system, 9012)
        XCTAssertEqual(snap?.idle, 345678)
        XCTAssertEqual(snap?.iowait, 901)
        XCTAssertEqual(snap?.irq, 23)
        XCTAssertEqual(snap?.softirq, 4567)
        XCTAssertEqual(snap?.steal, 89)
        XCTAssertEqual(snap?.total, 12345 + 678 + 9012 + 345678 + 901 + 23 + 4567 + 89)
    }

    func testStatRejectsNonCpuLine() {
        XCTAssertNil(LinuxMetricsParser.parseStat("intr 1234 0 0 0"))
    }

    func testStatHandlesMissingTrailingFields() {
        let raw = "cpu  100 0 50 900 0"
        let snap = LinuxMetricsParser.parseStat(raw)
        XCTAssertEqual(snap?.user, 100)
        XCTAssertEqual(snap?.idle, 900)
        XCTAssertEqual(snap?.irq, 0)
        XCTAssertEqual(snap?.steal, 0)
    }

    // MARK: /proc/loadavg

    func testLoadAvg() throws {
        let load = try XCTUnwrap(LinuxMetricsParser.parseLoadAvg("0.42 0.31 0.25 1/234 5678\n"))
        XCTAssertEqual(load.one, 0.42, accuracy: 0.001)
        XCTAssertEqual(load.five, 0.31, accuracy: 0.001)
        XCTAssertEqual(load.fifteen, 0.25, accuracy: 0.001)
    }

    func testLoadAvgRejectsGarbage() {
        XCTAssertNil(LinuxMetricsParser.parseLoadAvg("nope"))
    }

    // MARK: /proc/uptime

    func testUptime() throws {
        let uptime = try XCTUnwrap(LinuxMetricsParser.parseUptime("12345.67 9876.54\n"))
        XCTAssertEqual(uptime, 12345.67, accuracy: 0.001)
    }

    // MARK: /proc/meminfo

    func testMeminfoUsesMemAvailableWhenPresent() {
        let raw = """
        MemTotal:       16384000 kB
        MemFree:         2000000 kB
        MemAvailable:    8000000 kB
        Buffers:          500000 kB
        Cached:          3000000 kB
        SwapTotal:       4096000 kB
        SwapFree:        4000000 kB
        """
        let mem = LinuxMetricsParser.parseMeminfo(raw)
        XCTAssertEqual(mem?.totalBytes, 16384000 * 1024)
        XCTAssertEqual(mem?.availableBytes, 8000000 * 1024)
        XCTAssertEqual(mem?.usedBytes, (16384000 - 8000000) * 1024)
        XCTAssertEqual(mem?.swapTotalBytes, 4096000 * 1024)
        XCTAssertEqual(mem?.swapUsedBytes, (4096000 - 4000000) * 1024)
    }

    func testMeminfoFallbackWhenMemAvailableMissing() {
        let raw = """
        MemTotal:       8000000 kB
        MemFree:        1000000 kB
        Buffers:         200000 kB
        Cached:          500000 kB
        """
        let mem = LinuxMetricsParser.parseMeminfo(raw)
        XCTAssertEqual(mem?.totalBytes, 8000000 * 1024)
        XCTAssertEqual(mem?.availableBytes, (1000000 + 200000 + 500000) * 1024)
        XCTAssertEqual(mem?.usedBytes, (8000000 - 1000000 - 200000 - 500000) * 1024)
    }

    func testMeminfoNoTotalReturnsNil() {
        XCTAssertNil(LinuxMetricsParser.parseMeminfo("MemFree: 100 kB"))
    }

    // MARK: /proc/net/dev

    func testNetDevParsesRxTxBytes() {
        let raw = """
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo:   12345    100    0    0    0     0          0         0   12345     100    0    0    0     0       0          0
         eth0:  987654   1234    0    0    0     0          0         0  543210     567    0    0    0     0       0          0
        """
        let counters = LinuxMetricsParser.parseNetDev(raw)
        XCTAssertEqual(counters["lo"]?.rxBytes, 12345)
        XCTAssertEqual(counters["lo"]?.txBytes, 12345)
        XCTAssertEqual(counters["eth0"]?.rxBytes, 987654)
        XCTAssertEqual(counters["eth0"]?.txBytes, 543210)
        XCTAssertEqual(counters.count, 2)
    }

    // MARK: df -PkT

    func testDFParsesExt4AndTmpfs() {
        let raw = """
        Filesystem     Type     1024-blocks      Used Available Capacity Mounted on
        /dev/sda1      ext4         8123344   3456789   4123456      46% /
        tmpfs          tmpfs          512000         0    512000       0% /tmp
        """
        let disks = LinuxMetricsParser.parseDF(raw)
        XCTAssertEqual(disks.count, 2)
        XCTAssertEqual(disks[0].mountPoint, "/")
        XCTAssertEqual(disks[0].filesystem, "/dev/sda1")
        XCTAssertEqual(disks[0].fsType, "ext4")
        XCTAssertEqual(disks[0].totalBytes, 8123344 * 1024)
        XCTAssertEqual(disks[0].usedBytes, 3456789 * 1024)
        XCTAssertEqual(disks[0].availableBytes, 4123456 * 1024)
        XCTAssertEqual(disks[1].mountPoint, "/tmp")
        XCTAssertEqual(disks[1].fsType, "tmpfs")
    }

    func testDFHandlesMultiWordMountPath() {
        let raw = """
        Filesystem     Type     1024-blocks      Used Available Capacity Mounted on
        /dev/sdb1      ext4         100000     50000     50000     50% /mnt/my drive
        """
        let disks = LinuxMetricsParser.parseDF(raw)
        XCTAssertEqual(disks.first?.mountPoint, "/mnt/my drive")
    }

    // MARK: /etc/os-release

    func testOSReleasePrettyName() {
        let raw = """
        PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
        NAME="Debian GNU/Linux"
        VERSION_ID="12"
        """
        XCTAssertEqual(LinuxMetricsParser.parseOSRelease(raw), "Debian GNU/Linux 12 (bookworm)")
    }

    func testOSReleaseUnquoted() {
        XCTAssertEqual(LinuxMetricsParser.parseOSRelease("PRETTY_NAME=Alpine"), "Alpine")
    }

    func testOSReleaseMissingReturnsNil() {
        XCTAssertNil(LinuxMetricsParser.parseOSRelease("NAME=foo\nVERSION=1"))
    }

    // MARK: OS family detection

    func testOSFamily() {
        XCTAssertEqual(LinuxMetricsParser.parseOSFamily("Linux\n"), .linux)
        XCTAssertEqual(LinuxMetricsParser.parseOSFamily("Darwin"), .darwin)
        XCTAssertEqual(LinuxMetricsParser.parseOSFamily("FreeBSD"), .freebsd)
        XCTAssertEqual(LinuxMetricsParser.parseOSFamily("Plan9"), .unknown)
    }

    // MARK: SentinelBlocks

    func testSentinelBlocksSplit() {
        let raw = """
        =OS=
        Linux
        =NPROC=
        4
        =OSRELEASE=
        PRETTY_NAME="Test 1.0"
        NAME=Test
        =END=
        """
        let blocks = SentinelBlocks(raw)
        XCTAssertEqual(blocks["OS"], "Linux")
        XCTAssertEqual(blocks["NPROC"], "4")
        XCTAssertEqual(blocks["OSRELEASE"], "PRETTY_NAME=\"Test 1.0\"\nNAME=Test")
        XCTAssertNil(blocks["END"])
        XCTAssertNil(blocks["MISSING"])
    }

    func testSentinelBlocksIgnoresEqualsInData() {
        let raw = """
        =KV=
        a=1
        b=2
        =END=
        """
        let blocks = SentinelBlocks(raw)
        XCTAssertEqual(blocks["KV"], "a=1\nb=2")
    }
}
