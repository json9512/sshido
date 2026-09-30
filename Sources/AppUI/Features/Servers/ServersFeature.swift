#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ServersFeature: AppFeature {
    let id = "servers"

    var home: [HomeEntry] {
        [HomeEntry(id: "servers", order: 20, title: "Servers") { AnyView(ServersHomeSection()) }]
    }

    var settings: [SettingsEntry] {
        [SettingsEntry(id: "servers", group: .connections, order: 0, icon: "server.rack", title: "Servers & keys",
                       summary: { services in
                           let hosts = await services.hosts.all().count
                           let keys = await services.identities.all().count
                           return "\(hosts) \(hosts == 1 ? "server" : "servers") · \(keys) \(keys == 1 ? "key" : "keys")"
                       },
                       destination: { AnyView(ServersSettingsView()) })]
    }
}

@MainActor
final class ServersHomeModel: ObservableObject {
    @Published private(set) var hosts: [RemoteHost] = []
    @Published private(set) var loaded = false
    @Published private(set) var connected: Set<UUID> = []
    @Published private(set) var sessions: [Session] = []
    private let services: AppServices
    private var observers: [NSObjectProtocol] = []

    init(services: AppServices) {
        self.services = services
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .hostsDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.reload() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task {
                    await self?.refreshConnections()
                    await WaitingSessionsStore.shared.ingestDeliveredNotifications()
                }
            },
        ]
        Task { await reload() }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func reload() async {
        hosts = await services.hosts.all()
        loaded = true
        await refreshConnections()
        await WaitingSessionsStore.shared.ingestDeliveredNotifications()
    }

    func refreshConnections() async {
        connected = await services.sessions.connectedHostIDs()
        sessions = await services.sessions.allSessions()
    }

    func delete(_ host: RemoteHost) async {
        try? await services.hosts.remove(id: host.id)
        services.passwords.deletePassword(hostID: host.id)
        NotificationCenter.default.post(name: .hostsDidChange, object: nil)
    }
}

struct ServersHomeSection: View {
    @Environment(\.services) private var services

    var body: some View {
        ServersHomeContent(model: ServersHomeModel(services: services))
    }
}

private struct ServersHomeContent: View {
    @StateObject var model: ServersHomeModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.homeIsSplit) private var split
    @ObservedObject private var waiting = WaitingSessionsStore.shared
    @State private var pendingDelete: RemoteHost?

    var body: some View {
        Section {
            if model.loaded && model.hosts.isEmpty {
                EmptyStateView(title: "No servers", action: (icon: "plus", label: "Add your first server", run: { router.sheet = .addHost }))
                    .frame(height: 300)
                    .tideRow()
            }
            ForEach(Array(model.hosts.enumerated()), id: \.element.id) { index, host in
                row(host)
                    .listRowBackground(router.selectedHost?.id == host.id && split ? DS.Color.accentMuted : DS.Color.surface1)
                    .listRowSeparatorTint(DS.Color.line)
                    .coachTarget(index == 0 ? .tapHost : nil)
                    .onAppear { Task { await model.refreshConnections() } }
                    .confirmationDialog("Delete \(host.name)?", isPresented: Binding(
                        get: { pendingDelete?.id == host.id }, set: { if !$0 { pendingDelete = nil } }
                    ), titleVisibility: .visible) {
                        Button("Delete server", role: .destructive) {
                            pendingDelete = nil
                            Task { await model.delete(host) }
                        }
                    } message: {
                        Text("Removes it from this device with its saved password.")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { pendingDelete = host } label: { Label("Delete", systemImage: "trash") }
                            .tint(DS.Color.error)
                        Button { router.sheet = .editHost(host) } label: { Label("Edit", systemImage: "pencil") }
                            .tint(DS.Color.accent)
                    }
            }
        } header: {
            if !model.hosts.isEmpty { SectionLabel("Servers") }
        }
    }

    private func row(_ host: RemoteHost) -> some View {
        let waitingIDs = waiting.ledger.waitingHostIDs(among: model.sessions, hosts: model.hosts)
        return Button { router.openHost(host, regular: split) } label: {
            HostRow(host: host, connected: model.connected.contains(host.id), waiting: waitingIDs.contains(host.id))
        }
        .buttonStyle(.plain)
    }
}

struct HostRow: View {
    let host: RemoteHost
    let connected: Bool
    let waiting: Bool

    @State private var sample: ServerMetricsSample?
    @AppStorage(MetricsSettings.intervalKey) private var intervalSeconds: Int = MetricsSettings.defaultIntervalSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            TideRow(icon: "server.rack", title: host.name, subtitle: "\(host.username)@\(host.hostname):\(host.port)",
                    tint: connected ? DS.Color.accent : DS.Color.textTertiary, monoSubtitle: true) {
                HStack(spacing: DS.Spacing.sm) {
                    if waiting {
                        Text("needs you").font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                    }
                    StatusDot(color: statusColor, pulsing: connected || waiting)
                }
            }
            if connected, let sample {
                HostMetricsStrip(sample: sample)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host.name), \(connected ? "connected" : "not connected")\(waiting ? ", a session needs you" : "")")
        .task(id: connected) {
            guard connected else {
                sample = nil
                return
            }
            await stream()
        }
    }

    private var statusColor: Color {
        if waiting { return DS.Color.warning }
        return connected ? DS.Color.success : DS.Color.textTertiary
    }

    private func stream() async {
        guard let sid = await firstConnectedSessionID(for: host.id) else { return }
        let samples = await MetricsStore.shared.samples(
            sessionID: sid,
            channelProvider: { await SessionStore.shared.channel(for: sid) },
            interval: .seconds(intervalSeconds)
        )
        for await event in samples {
            if case .sample(let s) = event { sample = s }
        }
    }
}

struct HostMetricsStrip: View {
    let sample: ServerMetricsSample

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            MetricGauge(label: "CPU", percent: sample.cpu?.totalPercent)
            MetricGauge(label: "MEM", percent: MetricMath.memoryPercent(sample.memory))
            MetricGauge(label: "DISK", percent: MetricMath.rootDiskPercent(sample.disks))
            MetricNet(iface: MetricMath.primaryInterface(sample.network))
        }
        .padding(.leading, 38)
    }
}

private struct MetricGauge: View {
    let label: String
    let percent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(DS.Font.sans(10, .semibold)).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: 0)
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "–").font(DS.Font.mono(11, .medium)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surface2)
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var fraction: CGFloat { CGFloat(max(0, min(1, (percent ?? 0) / 100))) }

    private var color: Color {
        guard let percent else { return DS.Color.textTertiary }
        if percent >= 90 { return DS.Color.error }
        if percent >= 75 { return DS.Color.warning }
        return DS.Color.success
    }
}

private struct MetricNet: View {
    let iface: NetInterfaceSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(MetricMath.rate(iface?.txBytesPerSec), systemImage: "arrow.up")
            Label(MetricMath.rate(iface?.rxBytesPerSec), systemImage: "arrow.down")
        }
        .labelStyle(CompactLabelStyle())
        .font(DS.Font.mono(10))
        .foregroundStyle(DS.Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}

enum MetricMath {
    static func memoryPercent(_ m: MemorySample?) -> Double? {
        guard let m, m.totalBytes > 0 else { return nil }
        return Double(m.usedBytes) / Double(m.totalBytes) * 100
    }

    static func rootDisk(_ disks: [DiskSample]) -> DiskSample? {
        disks.first { $0.mountPoint == "/" }
            ?? disks.filter { !isPseudoFS($0.fsType) && $0.totalBytes > 0 }.max { $0.totalBytes < $1.totalBytes }
    }

    static func rootDiskPercent(_ disks: [DiskSample]) -> Double? {
        guard let d = rootDisk(disks), d.totalBytes > 0 else { return nil }
        return Double(d.usedBytes) / Double(d.totalBytes) * 100
    }

    static func primaryInterface(_ network: [NetInterfaceSample]) -> NetInterfaceSample? {
        network.filter { $0.name != "lo" && $0.name != "lo0" }
            .max { ($0.rxBytesTotal + $0.txBytesTotal) < ($1.rxBytesTotal + $1.txBytesTotal) } ?? network.first
    }

    static func rate(_ bps: Double?) -> String {
        guard let bps else { return "–" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(max(0, bps)), countStyle: .binary))/s"
    }

    private static let pseudoFS: Set<String> = [
        "tmpfs", "devtmpfs", "devfs", "overlay", "squashfs", "proc", "sysfs", "cgroup", "cgroup2", "debugfs", "tracefs",
        "mqueue", "hugetlbfs", "autofs", "fusectl", "configfs", "securityfs", "pstore", "ramfs", "binfmt_misc", "bpf",
    ]

    static func isPseudoFS(_ type: String) -> Bool { pseudoFS.contains(type) }
}
#endif
