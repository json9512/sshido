import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor ServerMetricsCollector {
    public typealias ChannelProvider = @Sendable () async -> SSHChannel?

    private let channelProvider: ChannelProvider
    private var hostInfo: HostInfo?
    private var previousCPU: LinuxMetricsParser.CPUSnapshot?
    private var previousNet: [String: LinuxMetricsParser.NetCounter] = [:]
    private var previousSampleAt: Date?

    public init(channelProvider: @escaping ChannelProvider) {
        self.channelProvider = channelProvider
    }

    public func sample() async throws -> ServerMetricsSample {
        guard let channel = await channelProvider() else { throw SSHError.notConnected }
        let info = try await ensureHostInfo(channel: channel)
        switch info.os {
        case .linux:
            return try await sampleLinux(host: info, channel: channel)
        case .darwin:
            return try await sampleDarwin(host: info, channel: channel)
        default:
            throw SSHError.transport("metrics sampler for \(info.os.rawValue) not yet implemented")
        }
    }

    private func ensureHostInfo(channel: SSHChannel) async throws -> HostInfo {
        if let info = hostInfo { return info }
        let raw = try await channel.executeCommand(LinuxMetricsCommands.probe)
        let blocks = SentinelBlocks(String(decoding: raw, as: UTF8.self))
        let os = blocks["OS"].map(LinuxMetricsParser.parseOSFamily) ?? .unknown
        let kernel = (blocks["KERNEL"]?.split(separator: "\n").first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
        let genericCPU = blocks["NPROC"].flatMap(LinuxMetricsParser.parseFirstInt)
        let genericPS = blocks["PAGESIZE"].flatMap(LinuxMetricsParser.parseFirstInt)

        if os == .darwin {
            let rawDarwin = try await channel.executeCommand(DarwinMetricsCommands.probe)
            let darwinBlocks = SentinelBlocks(String(decoding: rawDarwin, as: UTF8.self))
            let cpuCount = darwinBlocks["NPROC"].flatMap(LinuxMetricsParser.parseFirstInt)
                ?? genericCPU ?? 1
            let pageSize = darwinBlocks["PAGESIZE"].flatMap(LinuxMetricsParser.parseFirstInt)
                ?? genericPS ?? 16384
            let product = (darwinBlocks["PRODUCT"]?.split(separator: "\n").first).map(String.init) ?? ""
            let version = (darwinBlocks["PRODVER"]?.split(separator: "\n").first).map(String.init) ?? ""
            let combined = [product, version].filter { !$0.isEmpty }.joined(separator: " ")
            let info = HostInfo(
                os: .darwin,
                kernel: kernel,
                prettyName: combined.isEmpty ? nil : combined,
                cpuCount: cpuCount,
                pageSize: pageSize,
                bootTime: nil
            )
            hostInfo = info
            return info
        }

        let info = HostInfo(
            os: os,
            kernel: kernel,
            prettyName: blocks["OSRELEASE"].flatMap(LinuxMetricsParser.parseOSRelease),
            cpuCount: genericCPU ?? 1,
            pageSize: genericPS ?? 4096,
            bootTime: nil
        )
        hostInfo = info
        return info
    }

    private func sampleLinux(host: HostInfo, channel: SSHChannel) async throws -> ServerMetricsSample {
        let raw = try await channel.executeCommand(LinuxMetricsCommands.sample)
        let now = Date()
        let blocks = SentinelBlocks(String(decoding: raw, as: UTF8.self))

        let uptime = blocks["UPTIME"].flatMap(LinuxMetricsParser.parseUptime)
        let load = blocks["LOADAVG"].flatMap(LinuxMetricsParser.parseLoadAvg)
        let memory = blocks["MEMINFO"].flatMap(LinuxMetricsParser.parseMeminfo)
        let disks = blocks["DF"].map(LinuxMetricsParser.parseDF) ?? []
        let cpuRaw = blocks["STAT"].flatMap(LinuxMetricsParser.parseStat)
        let netRaw = blocks["NETDEV"].map(LinuxMetricsParser.parseNetDev) ?? [:]

        let cpu = cpuRaw.flatMap { cur -> CPUSample? in
            guard let prev = previousCPU, cur.total > prev.total else { return nil }
            let dTotal = Double(cur.total &- prev.total)
            let dUser = Double((cur.user &+ cur.nice) &- (prev.user &+ prev.nice))
            let dSystem = Double(cur.system &- prev.system)
            let dIdle = Double(cur.idle &- prev.idle)
            let dIowait = Double(cur.iowait &- prev.iowait)
            let dNonIdle = Double(cur.nonIdle &- prev.nonIdle)
            return CPUSample(
                userPercent: 100.0 * dUser / dTotal,
                systemPercent: 100.0 * dSystem / dTotal,
                idlePercent: 100.0 * dIdle / dTotal,
                iowaitPercent: 100.0 * dIowait / dTotal,
                totalPercent: 100.0 * dNonIdle / dTotal
            )
        }
        if let cur = cpuRaw { previousCPU = cur }

        var resolvedHost = host
        if resolvedHost.bootTime == nil, let up = uptime {
            resolvedHost = HostInfo(
                os: host.os,
                kernel: host.kernel,
                prettyName: host.prettyName,
                cpuCount: host.cpuCount,
                pageSize: host.pageSize,
                bootTime: now.addingTimeInterval(-up)
            )
            hostInfo = resolvedHost
        }

        let dt = previousSampleAt.map { max(now.timeIntervalSince($0), 0.001) } ?? 0
        var netSamples: [NetInterfaceSample] = []
        for (name, cur) in netRaw {
            let rate: (rx: Double, tx: Double)
            if dt > 0,
               let prev = previousNet[name],
               cur.rxBytes >= prev.rxBytes,
               cur.txBytes >= prev.txBytes {
                rate = (Double(cur.rxBytes &- prev.rxBytes) / dt,
                        Double(cur.txBytes &- prev.txBytes) / dt)
            } else {
                rate = (0, 0)
            }
            netSamples.append(NetInterfaceSample(
                name: name,
                rxBytesPerSec: rate.rx,
                txBytesPerSec: rate.tx,
                rxBytesTotal: cur.rxBytes,
                txBytesTotal: cur.txBytes
            ))
        }
        netSamples.sort { $0.name < $1.name }
        previousNet = netRaw
        previousSampleAt = now

        return ServerMetricsSample(
            timestamp: now,
            host: resolvedHost,
            cpu: cpu,
            load: load,
            memory: memory,
            disks: disks,
            network: netSamples,
            uptime: uptime
        )
    }

    private func sampleDarwin(host: HostInfo, channel: SSHChannel) async throws -> ServerMetricsSample {
        let raw = try await channel.executeCommand(DarwinMetricsCommands.sample)
        let now = Date()
        let blocks = SentinelBlocks(String(decoding: raw, as: UTF8.self))

        let load = blocks["LOADAVG"].flatMap(DarwinMetricsParser.parseLoadAvg)
        let bootTime = blocks["BOOTTIME"].flatMap(DarwinMetricsParser.parseBootTime)
        let uptime = bootTime.map { now.timeIntervalSince($0) }

        let totalBytes: UInt64 = blocks["MEMSIZE"]
            .flatMap(LinuxMetricsParser.parseFirstInt)
            .map(UInt64.init) ?? 0
        let usedBytes = blocks["VMSTAT"]
            .flatMap { DarwinMetricsParser.parseVMStat($0, pageSize: host.pageSize) } ?? 0
        let availableBytes = totalBytes > usedBytes ? totalBytes &- usedBytes : 0
        let swap = blocks["SWAP"].flatMap(DarwinMetricsParser.parseSwap)
            ?? (total: UInt64(0), used: UInt64(0))
        let memory: MemorySample? = totalBytes > 0 ? MemorySample(
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            usedBytes: usedBytes,
            swapTotalBytes: swap.total,
            swapUsedBytes: swap.used
        ) : nil

        let cpu = blocks["CPU"].flatMap(DarwinMetricsParser.parseTopCPU)
        let disks = blocks["DF"].map(DarwinMetricsParser.parseDF) ?? []
        let netRaw = blocks["NETSTAT"].map(DarwinMetricsParser.parseNetstatIB) ?? [:]

        let dt = previousSampleAt.map { max(now.timeIntervalSince($0), 0.001) } ?? 0
        var netSamples: [NetInterfaceSample] = []
        for (name, cur) in netRaw {
            let rate: (rx: Double, tx: Double)
            if dt > 0,
               let prev = previousNet[name],
               cur.rxBytes >= prev.rxBytes,
               cur.txBytes >= prev.txBytes {
                rate = (Double(cur.rxBytes &- prev.rxBytes) / dt,
                        Double(cur.txBytes &- prev.txBytes) / dt)
            } else {
                rate = (0, 0)
            }
            netSamples.append(NetInterfaceSample(
                name: name,
                rxBytesPerSec: rate.rx,
                txBytesPerSec: rate.tx,
                rxBytesTotal: cur.rxBytes,
                txBytesTotal: cur.txBytes
            ))
        }
        netSamples.sort { $0.name < $1.name }
        previousNet = netRaw
        previousSampleAt = now

        var resolvedHost = host
        if resolvedHost.bootTime == nil, let bt = bootTime {
            resolvedHost = HostInfo(
                os: host.os,
                kernel: host.kernel,
                prettyName: host.prettyName,
                cpuCount: host.cpuCount,
                pageSize: host.pageSize,
                bootTime: bt
            )
            hostInfo = resolvedHost
        }

        return ServerMetricsSample(
            timestamp: now,
            host: resolvedHost,
            cpu: cpu,
            load: load,
            memory: memory,
            disks: disks,
            network: netSamples,
            uptime: uptime
        )
    }
}
