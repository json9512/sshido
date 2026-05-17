import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

enum LinuxMetricsCommands {
    static let probe = """
    { \
    echo '=OS='; uname -s; \
    echo '=KERNEL='; uname -sr; \
    echo '=NPROC='; nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0; \
    echo '=PAGESIZE='; getconf PAGESIZE 2>/dev/null || echo 0; \
    echo '=OSRELEASE='; cat /etc/os-release 2>/dev/null || true; \
    echo '=END='; \
    } 2>/dev/null
    """

    static let sample = """
    { \
    echo '=UPTIME='; cat /proc/uptime 2>/dev/null; \
    echo '=LOADAVG='; cat /proc/loadavg 2>/dev/null; \
    echo '=STAT='; head -n 1 /proc/stat 2>/dev/null; \
    echo '=MEMINFO='; cat /proc/meminfo 2>/dev/null; \
    echo '=NETDEV='; cat /proc/net/dev 2>/dev/null; \
    echo '=DF='; df -PkT 2>/dev/null || df -Pk 2>/dev/null; \
    echo '=END='; \
    } 2>/dev/null
    """
}

struct SentinelBlocks {
    let blocks: [String: String]

    init(_ raw: String) {
        var out: [String: String] = [:]
        var current: String?
        var lines: [String] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if Self.isSentinel(line) {
                if let name = current {
                    out[name] = lines.joined(separator: "\n")
                }
                current = String(line.dropFirst().dropLast())
                lines = []
            } else if current != nil {
                lines.append(line)
            }
        }
        if let name = current, name != "END" {
            out[name] = lines.joined(separator: "\n")
        }
        self.blocks = out
    }

    private static func isSentinel(_ s: String) -> Bool {
        guard s.count >= 3, s.first == "=", s.last == "=" else { return false }
        let inner = s.dropFirst().dropLast()
        return inner.allSatisfy { ch in
            ch.isASCII && (ch.isLetter && ch.isUppercase || ch.isNumber || ch == "_")
        }
    }

    subscript(name: String) -> String? { blocks[name] }
}

enum LinuxMetricsParser {
    struct CPUSnapshot: Equatable, Sendable {
        let user: UInt64
        let nice: UInt64
        let system: UInt64
        let idle: UInt64
        let iowait: UInt64
        let irq: UInt64
        let softirq: UInt64
        let steal: UInt64

        var total: UInt64 { user &+ nice &+ system &+ idle &+ iowait &+ irq &+ softirq &+ steal }
        var nonIdle: UInt64 { user &+ nice &+ system &+ iowait &+ irq &+ softirq &+ steal }
    }

    struct NetCounter: Equatable, Sendable {
        let rxBytes: UInt64
        let txBytes: UInt64
    }

    static func parseStat(_ s: String) -> CPUSnapshot? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 5, parts[0] == "cpu" else { return nil }
        func u(_ i: Int) -> UInt64 { i < parts.count ? (UInt64(parts[i]) ?? 0) : 0 }
        return CPUSnapshot(
            user: u(1), nice: u(2), system: u(3),
            idle: u(4), iowait: u(5),
            irq: u(6), softirq: u(7), steal: u(8)
        )
    }

    static func parseLoadAvg(_ s: String) -> LoadSample? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3,
              let one = Double(parts[0]),
              let five = Double(parts[1]),
              let fifteen = Double(parts[2]) else { return nil }
        return LoadSample(one: one, five: five, fifteen: fifteen)
    }

    static func parseUptime(_ s: String) -> TimeInterval? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return parts.first.flatMap(Double.init)
    }

    static func parseMeminfo(_ s: String) -> MemorySample? {
        var totals: [String: UInt64] = [:]
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let rest = line[line.index(after: colon)...]
            let parts = rest.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = parts.first, let kb = UInt64(first) else { continue }
            totals[key] = kb &* 1024
        }
        guard let total = totals["MemTotal"] else { return nil }
        let derived = (totals["MemFree"] ?? 0) &+ (totals["Buffers"] ?? 0) &+ (totals["Cached"] ?? 0)
        let available = totals["MemAvailable"] ?? min(derived, total)
        let used = total > available ? total &- available : 0
        let swapTotal = totals["SwapTotal"] ?? 0
        let swapFree = totals["SwapFree"] ?? swapTotal
        let swapUsed = swapTotal > swapFree ? swapTotal &- swapFree : 0
        return MemorySample(
            totalBytes: total,
            availableBytes: available,
            usedBytes: used,
            swapTotalBytes: swapTotal,
            swapUsedBytes: swapUsed
        )
    }

    static func parseNetDev(_ s: String) -> [String: NetCounter] {
        var out: [String: NetCounter] = [:]
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            let rest = line[line.index(after: colon)...]
            let parts = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9,
                  let rx = UInt64(parts[0]),
                  let tx = UInt64(parts[8]) else { continue }
            out[name] = NetCounter(rxBytes: rx, txBytes: tx)
        }
        return out
    }

    static func parseDF(_ s: String) -> [DiskSample] {
        var out: [DiskSample] = []
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("Filesystem") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 7,
                  let total = UInt64(parts[2]),
                  let used = UInt64(parts[3]),
                  let avail = UInt64(parts[4]) else { continue }
            let mount = parts[6...].joined(separator: " ")
            out.append(DiskSample(
                mountPoint: mount,
                filesystem: parts[0],
                fsType: parts[1],
                totalBytes: total &* 1024,
                usedBytes: used &* 1024,
                availableBytes: avail &* 1024
            ))
        }
        return out
    }

    static func parseOSRelease(_ s: String) -> String? {
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            guard line.hasPrefix("PRETTY_NAME=") else { continue }
            var value = String(line.dropFirst("PRETTY_NAME=".count))
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    static func parseFirstInt(_ s: String) -> Int? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        return Int(firstLine.trimmingCharacters(in: .whitespaces))
    }

    static func parseOSFamily(_ s: String) -> ServerOSFamily {
        let firstLine = (s.split(separator: "\n").first.map(String.init) ?? s)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        switch firstLine {
        case "linux":   return .linux
        case "darwin":  return .darwin
        case "freebsd": return .freebsd
        case "openbsd": return .openbsd
        case "netbsd":  return .netbsd
        default:        return .unknown
        }
    }
}

enum DarwinMetricsCommands {
    static let probe = """
    { \
    echo '=NPROC='; sysctl -n hw.ncpu 2>/dev/null; \
    echo '=PAGESIZE='; sysctl -n hw.pagesize 2>/dev/null; \
    echo '=PRODUCT='; sw_vers -productName 2>/dev/null || true; \
    echo '=PRODVER='; sw_vers -productVersion 2>/dev/null || true; \
    echo '=END='; \
    } 2>/dev/null
    """

    static let sample = """
    { \
    echo '=LOADAVG='; sysctl -n vm.loadavg 2>/dev/null; \
    echo '=BOOTTIME='; sysctl -n kern.boottime 2>/dev/null; \
    echo '=VMSTAT='; vm_stat 2>/dev/null; \
    echo '=MEMSIZE='; sysctl -n hw.memsize 2>/dev/null; \
    echo '=SWAP='; sysctl -n vm.swapusage 2>/dev/null || true; \
    echo '=CPU='; top -l 2 -s 1 -n 0 2>/dev/null | grep 'CPU usage:' | tail -n 1; \
    echo '=NETSTAT='; netstat -ibn 2>/dev/null; \
    echo '=DF='; df -Pk 2>/dev/null; \
    echo '=END='; \
    } 2>/dev/null
    """
}

enum DarwinMetricsParser {
    static func parseLoadAvg(_ s: String) -> LoadSample? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        let cleaned = firstLine.replacingOccurrences(of: "{", with: " ")
            .replacingOccurrences(of: "}", with: " ")
        let parts = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3,
              let one = Double(parts[0]),
              let five = Double(parts[1]),
              let fifteen = Double(parts[2]) else { return nil }
        return LoadSample(one: one, five: five, fifteen: fifteen)
    }

    static func parseBootTime(_ s: String) -> Date? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        guard let secRange = firstLine.range(of: "sec = ") else { return nil }
        let after = firstLine[secRange.upperBound...]
        let numeric = after.prefix { $0.isNumber }
        guard let secs = TimeInterval(numeric) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    static func parseVMStat(_ s: String, pageSize: Int) -> UInt64? {
        var values: [String: UInt64] = [:]
        var headerPageSize: Int?
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("Mach Virtual Memory Statistics:") {
                if let r = line.range(of: "page size of "),
                   let end = line.range(of: " bytes", range: r.upperBound..<line.endIndex) {
                    headerPageSize = Int(line[r.upperBound..<end.lowerBound])
                }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let v = UInt64(rest) {
                values[key] = v
            }
        }
        guard !values.isEmpty else { return nil }
        let ps = UInt64(headerPageSize ?? pageSize)
        let active = values["Pages active"] ?? 0
        let wired = values["Pages wired down"] ?? 0
        let compressor = values["Pages occupied by compressor"]
            ?? values["Pages stored in compressor"] ?? 0
        let totalPages = active &+ wired &+ compressor
        return totalPages &* ps
    }

    static func parseSwap(_ s: String) -> (total: UInt64, used: UInt64)? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        func extractMB(_ key: String) -> Double? {
            guard let r = firstLine.range(of: "\(key) = ") else { return nil }
            let rest = firstLine[r.upperBound...]
            let numeric = rest.prefix { $0.isNumber || $0 == "." }
            return Double(numeric)
        }
        guard let total = extractMB("total"), let used = extractMB("used") else { return nil }
        let mib = 1024.0 * 1024.0
        return (UInt64(total * mib), UInt64(used * mib))
    }

    static func parseTopCPU(_ s: String) -> CPUSample? {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        guard let r = firstLine.range(of: "CPU usage: ") else { return nil }
        let rest = firstLine[r.upperBound...]
        let chunks = rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        func extract(label: String) -> Double? {
            let suffix = "% \(label)"
            for chunk in chunks where chunk.hasSuffix(suffix) {
                let head = chunk.dropLast(suffix.count)
                return Double(head)
            }
            return nil
        }
        guard let user = extract(label: "user"),
              let sys = extract(label: "sys"),
              let idle = extract(label: "idle") else { return nil }
        return CPUSample(
            userPercent: user,
            systemPercent: sys,
            idlePercent: idle,
            iowaitPercent: nil,
            totalPercent: user + sys
        )
    }

    static func parseNetstatIB(_ s: String) -> [String: LinuxMetricsParser.NetCounter] {
        var out: [String: LinuxMetricsParser.NetCounter] = [:]
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("Name") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }
            let netCol = parts[2]
            guard netCol.hasPrefix("<Link#") else { continue }
            let n = parts.count
            guard let ibytes = UInt64(parts[n - 5]),
                  let obytes = UInt64(parts[n - 2]) else { continue }
            let name = parts[0]
            out[name] = LinuxMetricsParser.NetCounter(rxBytes: ibytes, txBytes: obytes)
        }
        return out
    }

    static func parseDF(_ s: String) -> [DiskSample] {
        var out: [DiskSample] = []
        for rawLine in s.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("Filesystem") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 6,
                  let total = UInt64(parts[1]),
                  let used = UInt64(parts[2]),
                  let avail = UInt64(parts[3]) else { continue }
            let mount = parts[5...].joined(separator: " ")
            out.append(DiskSample(
                mountPoint: mount,
                filesystem: parts[0],
                fsType: "",
                totalBytes: total &* 1024,
                usedBytes: used &* 1024,
                availableBytes: avail &* 1024
            ))
        }
        return out
    }
}
