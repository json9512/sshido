#if canImport(UIKit)
import SwiftUI
import Charts
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

private let perfHistoryCapacity = 60

private let pseudoFSTypes: Set<String> = [
    "tmpfs", "devtmpfs", "devfs", "overlay", "squashfs", "proc", "sysfs",
    "cgroup", "cgroup2", "debugfs", "tracefs", "mqueue", "hugetlbfs",
    "autofs", "fusectl", "configfs", "securityfs", "pstore", "ramfs",
    "binfmt_misc", "bpf"
]

private struct PerfPoint: Identifiable, Hashable {
    let id = UUID()
    let t: Date
    let value: Double
}

private struct NetPoint: Identifiable, Hashable {
    let id = UUID()
    let t: Date
    let rx: Double
    let tx: Double
}

public struct ServerPerformanceView: View {
    let host: RemoteHost

    @State private var latest: ServerMetricsSample?
    @State private var cpuHistory: [PerfPoint] = []
    @State private var netHistory: [String: [NetPoint]] = [:]
    @State private var showAllDisks = false
    @State private var showAllInterfaces = false
    @State private var ownedChannel: MetricsOnlySSHChannel?
    @State private var ownedChannelError: String?
    @State private var sampleError: String?
    @State private var samplesReceived: Int = 0
    @AppStorage(MetricsSettings.intervalKey) private var intervalSeconds: Int = MetricsSettings.defaultIntervalSeconds
    @Environment(\.scenePhase) private var scenePhase

    private struct StreamKey: Hashable {
        let active: Bool
        let intervalSeconds: Int
    }

    public init(host: RemoteHost) {
        self.host = host
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                hostHeader
                cpuCard
                memoryCard
                diskCard
                networkCard
                footer
                if let msg = ownedChannelError ?? sampleError {
                    PerfCard(title: "Diagnostic") {
                        Text(msg)
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Text("Samples received: \(samplesReceived)")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.Color.surface0)
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: StreamKey(active: scenePhase == .active, intervalSeconds: intervalSeconds)) {
            guard scenePhase == .active else { return }
            await streamSamples(interval: .seconds(intervalSeconds))
        }
        .onDisappear {
            let ch = ownedChannel
            ownedChannel = nil
            Task { await ch?.disconnect() }
        }
    }

    private func streamSamples(interval: Duration) async {
        let streamKey: UUID
        let provider: @Sendable () async -> SSHChannel?
        if let sid = await firstConnectedSessionID(for: host.id) {
            streamKey = sid
            provider = {
                let ch = await SessionStore.shared.channel(for: sid)
                NSLog("[sshido] perf provider via session sid=\(sid.uuidString.prefix(8)) channel=\(ch == nil ? "nil" : "ok")")
                return ch
            }
        } else {
            streamKey = host.id
            if ownedChannel == nil {
                await openOwnedChannel()
            }
            provider = { [weak channel = ownedChannel] in
                let ok = channel != nil
                NSLog("[sshido] perf provider host channel=\(ok ? "ok" : "nil")")
                return channel
            }
        }
        NSLog("[sshido] perf streamSamples start key=\(streamKey.uuidString.prefix(8)) interval=\(interval)")
        let stream = await MetricsStore.shared.samples(
            sessionID: streamKey,
            channelProvider: provider,
            interval: interval
        )
        for await event in stream {
            await MainActor.run {
                switch event {
                case .sample(let sample):
                    samplesReceived += 1
                    sampleError = nil
                    apply(sample)
                case .error(let msg):
                    sampleError = msg
                }
            }
        }
        NSLog("[sshido] perf streamSamples exit key=\(streamKey.uuidString.prefix(8))")
    }

    @MainActor
    private func openOwnedChannel() async {
        do {
            let auth = try await resolveAuth(for: host)
            let channel = await SessionStore.shared.metricsChannel(for: host, auth: auth)
            try await channel.connect()
            ownedChannel = channel
            ownedChannelError = nil
        } catch {
            ownedChannelError = "Could not open metrics channel: \(error)"
        }
    }

    @MainActor
    private func apply(_ sample: ServerMetricsSample) {
        latest = sample
        if let cpu = sample.cpu {
            cpuHistory.append(PerfPoint(t: sample.timestamp, value: cpu.totalPercent))
            if cpuHistory.count > perfHistoryCapacity {
                cpuHistory.removeFirst(cpuHistory.count - perfHistoryCapacity)
            }
        }
        let presentNames = Set(sample.network.map(\.name))
        for name in netHistory.keys where !presentNames.contains(name) {
            netHistory[name] = nil
        }
        for iface in sample.network {
            var window = netHistory[iface.name] ?? []
            window.append(NetPoint(t: sample.timestamp, rx: iface.rxBytesPerSec, tx: iface.txBytesPerSec))
            if window.count > perfHistoryCapacity {
                window.removeFirst(window.count - perfHistoryCapacity)
            }
            netHistory[iface.name] = window
        }
    }

    @ViewBuilder
    private var hostHeader: some View {
        PerfCard(title: "Host") {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(latest?.host.prettyName ?? host.name)
                    .font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: DS.Spacing.md) {
                    StatPill(title: "Kernel", value: latest?.host.kernel ?? "—")
                    StatPill(title: "CPUs", value: "\(latest?.host.cpuCount ?? 0)")
                    StatPill(title: "Uptime", value: uptimeString(latest?.uptime))
                }
            }
        }
    }

    @ViewBuilder
    private var cpuCard: some View {
        PerfCard(title: "CPU") {
            if let cpu = latest?.cpu {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(cpu.totalPercent.rounded()))%")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    if let load = latest?.load {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Load avg")
                                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            Text(String(format: "%.2f  %.2f  %.2f", load.one, load.five, load.fifteen))
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(loadColor(load: load.one, cpus: latest?.host.cpuCount ?? 1))
                        }
                    }
                }
                HStack(spacing: DS.Spacing.lg) {
                    Subtle("user", "\(percentString(cpu.userPercent))")
                    Subtle("system", "\(percentString(cpu.systemPercent))")
                    if let io = cpu.iowaitPercent {
                        Subtle("iowait", "\(percentString(io))")
                    }
                    Subtle("idle", "\(percentString(cpu.idlePercent))")
                }
                if cpuHistory.count >= 2 {
                    Chart(cpuHistory) { p in
                        AreaMark(x: .value("t", p.t), y: .value("cpu", p.value))
                            .foregroundStyle(DS.Color.accent.opacity(0.18))
                        LineMark(x: .value("t", p.t), y: .value("cpu", p.value))
                            .foregroundStyle(DS.Color.accent)
                            .interpolationMethod(.monotone)
                    }
                    .frame(height: 64)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...100)
                }
            } else {
                Text("Sampling…")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var memoryCard: some View {
        PerfCard(title: "Memory") {
            if let mem = latest?.memory {
                let frac = mem.totalBytes > 0 ? Double(mem.usedBytes) / Double(mem.totalBytes) : 0
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int((frac * 100).rounded()))%")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    Text("\(byteString(mem.usedBytes)) / \(byteString(mem.totalBytes))")
                        .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
                }
                MemoryBar(fraction: frac)
                if mem.swapTotalBytes > 0 {
                    HStack {
                        Text("Swap").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(byteString(mem.swapUsedBytes)) / \(byteString(mem.swapTotalBytes))")
                            .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            } else {
                Text("Sampling…").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var diskCard: some View {
        PerfCard(title: "Disk") {
            let all = latest?.disks ?? []
            let visible = showAllDisks ? all : all.filter { !pseudoFSTypes.contains($0.fsType) }
            if all.isEmpty {
                Text("Sampling…").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            } else if visible.isEmpty {
                Button("Show \(all.count) hidden mounts") { showAllDisks = true }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.accent)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(visible) { disk in
                        DiskRow(disk: disk)
                    }
                }
                if all.count > visible.count {
                    Button(showAllDisks ? "Hide pseudo filesystems" : "Show all (\(all.count))") {
                        showAllDisks.toggle()
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var networkCard: some View {
        PerfCard(title: "Network") {
            let all = latest?.network ?? []
            let visible = showAllInterfaces ? all : all.filter { $0.name != "lo" }
            if all.isEmpty {
                Text("Sampling…").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            } else {
                VStack(spacing: DS.Spacing.md) {
                    ForEach(visible) { iface in
                        NetRow(iface: iface, history: netHistory[iface.name] ?? [])
                    }
                }
                if all.contains(where: { $0.name == "lo" }) {
                    Button(showAllInterfaces ? "Hide loopback" : "Show loopback") {
                        showAllInterfaces.toggle()
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if let ts = latest?.timestamp {
                Text("Updated \(ts.formatted(date: .omitted, time: .standard))")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
            if scenePhase != .active {
                Label("Paused", systemImage: "pause.circle")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            } else {
                Text("Sampling every \(intervalSeconds)s")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }
}

// MARK: subviews

private struct PerfCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title.uppercased())
                .font(DS.Font.caption).tracking(0.8)
                .foregroundStyle(DS.Color.textSecondary)
            content()
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.titaniumDark.opacity(0.4), lineWidth: 0.5)
        )
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(DS.Color.textTertiary)
            Text(value)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
        }
    }
}

private struct Subtle: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .medium)).tracking(0.6)
                .foregroundStyle(DS.Color.textTertiary)
            Text(value).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
        }
    }
}

private struct MemoryBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Color.surface2)
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor(fraction))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }

    private func barColor(_ f: Double) -> Color {
        if f > 0.9 { return DS.Color.error }
        if f > 0.75 { return DS.Color.warning }
        return DS.Color.accent
    }
}

private struct DiskRow: View {
    let disk: DiskSample
    var body: some View {
        let frac = disk.totalBytes > 0 ? Double(disk.usedBytes) / Double(disk.totalBytes) : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(disk.mountPoint).font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(byteString(disk.usedBytes)) / \(byteString(disk.totalBytes))")
                    .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
            }
            MemoryBar(fraction: frac)
            Text(disk.fsType).font(.system(size: 10))
                .foregroundStyle(DS.Color.textTertiary)
        }
    }
}

private struct NetRow: View {
    let iface: NetInterfaceSample
    let history: [NetPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(iface.name).font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("↓ \(rateString(iface.rxBytesPerSec))  ↑ \(rateString(iface.txBytesPerSec))")
                    .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
            }
            if history.count >= 2 {
                Chart {
                    ForEach(history) { p in
                        LineMark(
                            x: .value("t", p.t),
                            y: .value("rx", p.rx),
                            series: .value("dir", "rx")
                        )
                        .foregroundStyle(DS.Color.accent)
                        .interpolationMethod(.monotone)
                        LineMark(
                            x: .value("t", p.t),
                            y: .value("tx", p.tx),
                            series: .value("dir", "tx")
                        )
                        .foregroundStyle(DS.Color.spark)
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 40)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
            HStack(spacing: DS.Spacing.md) {
                Text("Total ↓ \(byteString(iface.rxBytesTotal))")
                Text("↑ \(byteString(iface.txBytesTotal))")
            }
            .font(.system(size: 10))
            .foregroundStyle(DS.Color.textTertiary)
        }
    }
}

// MARK: helpers

private func byteString(_ bytes: UInt64) -> String {
    let fmt = ByteCountFormatter()
    fmt.countStyle = .binary
    fmt.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return fmt.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}

private func rateString(_ bytesPerSec: Double) -> String {
    let safe = max(0, bytesPerSec)
    let fmt = ByteCountFormatter()
    fmt.countStyle = .binary
    fmt.allowedUnits = [.useKB, .useMB, .useGB]
    return "\(fmt.string(fromByteCount: Int64(safe)))/s"
}

private func percentString(_ p: Double) -> String {
    String(format: "%.1f%%", max(0, p))
}

private func uptimeString(_ seconds: TimeInterval?) -> String {
    guard let s = seconds, s > 0 else { return "—" }
    let total = Int(s)
    let days = total / 86400
    let hours = (total % 86400) / 3600
    let minutes = (total % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

private func loadColor(load: Double, cpus: Int) -> Color {
    let ratio = load / Double(max(cpus, 1))
    if ratio > 1.5 { return DS.Color.error }
    if ratio > 1.0 { return DS.Color.warning }
    return DS.Color.textPrimary
}

func firstConnectedSessionID(for hostID: UUID) async -> UUID? {
    let sids = await SessionStore.shared.connectedSessionIDs(for: hostID)
    return sids.sorted(by: { $0.uuidString < $1.uuidString }).first
}

private func resolveAuth(for host: RemoteHost) async throws -> SSHAuth {
    switch host.authMethod {
    case .password:
        let pw = try KeychainKeyStore().loadPassword(hostID: host.id)
        return .password(pw)
    case .key:
        guard let identityID = host.identityID else {
            throw SSHError.invalidKey("host has no identity attached")
        }
        let pem = try await IdentityStore.shared.loadPEM(for: identityID)
        return .privateKeyPEM(pem, passphrase: nil)
    }
}
#endif
