#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

public struct HostListView: View {
    @State private var hosts: [RemoteHost] = []
    @State private var connectedHosts: Set<UUID> = []
    @State private var pendingHostDelete: RemoteHost?
    @EnvironmentObject private var router: AppRouter
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationStack(path: $router.detailPath) {
                        detailRoot
                            .navigationDestination(for: AppRouter.Destination.self, destination: destination)
                    }
                    .background(DS.Color.surface0)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $router.path) {
                    sidebar
                        .navigationDestination(for: AppRouter.Destination.self, destination: destination)
                }
            }
        }
        .task { await reload() }
        .onChange(of: scenePhase) { _, new in
            if new == .active { Task { await refreshConnections() } }
        }
        .onChange(of: router.path) { _, _ in
            Task { await refreshConnections() }
        }
        .onChange(of: deepLinks.pendingSessionRef) { _, _ in
            Task { await handleDeepLink() }
        }
        .modifier(SheetOrFullScreen(item: $router.sheet, sizeClass: sizeClass) { sheet in
            switch sheet {
            case .settings:
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { router.sheet = nil }
                            }
                        }
                }
            case .addHost:
                AddHostView { _ in
                    OnboardingCoach.shared.advance(past: .save)
                    Task { await reload() }
                }
            case .editHost(let host):
                AddHostView(existing: host) { _ in Task { await reload() } }
            }
        })
        .coachmarks()
        .confirmationDialog(
            pendingHostDelete.map { "Delete \($0.name)?" } ?? "Delete server?",
            isPresented: Binding(
                get: { pendingHostDelete != nil },
                set: { if !$0 { pendingHostDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingHostDelete
        ) { host in
            Button("Delete", role: .destructive) {
                let hostID = host.id
                Task {
                    try? await HostStore.shared.remove(id: hostID)
                    KeychainKeyStore().deletePassword(hostID: hostID)
                    await reload()
                }
                pendingHostDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingHostDelete = nil }
        } message: { _ in
            Text("This removes the server from this device and deletes any saved password. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func destination(_ dest: AppRouter.Destination) -> some View {
        switch dest {
        case .host(let host):
            SessionsListView(host: host)
        case .session(let session):
            if let host = hosts.first(where: { $0.id == session.hostID }) {
                SessionView(session: session, host: host)
            } else {
                ContentUnavailableView("Host missing", systemImage: "server.rack")
            }
        case .performance(let host):
            ServerPerformanceView(host: host)
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        if let host = router.selectedHost {
            SessionsListView(host: host)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.surface0)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if hosts.isEmpty {
                ContentUnavailableView(label: {
                    Label("No servers yet", systemImage: "server.rack")
                }, description: {
                    VStack(spacing: DS.Spacing.sm) {
                        Text("Tap + to add a server.")
                        Text("Use a private key or a password. For remote access over LTE, install Tailscale on both devices and use the tailnet hostname.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.xl)
                    }
                }, actions: {
                    Button { router.sheet = .addHost } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .coachTarget(.addHost)
                })
            } else if sizeClass == .regular {
                List(selection: Binding(
                    get: { router.selectedHost },
                    set: { router.selectedHost = $0; router.detailPath.removeAll() }
                )) {
                    ForEach(hosts) { host in
                        hostRow(host).tag(host).dsRow()
                    }
                    .onDelete { offsets in
                        guard let idx = offsets.first else { return }
                        pendingHostDelete = hosts[idx]
                    }
                }
            } else {
                List {
                    ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                        Button {
                            router.push(.host(host))
                        } label: {
                            hostRow(host)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .dsRow()
                        .coachTarget(index == 0 ? .tapHost : nil)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingHostDelete = host
                            } label: { Label("Delete", systemImage: "trash").labelStyle(.iconOnly) }
                            .tint(DS.Color.error)
                            Button {
                                router.sheet = .editHost(host)
                            } label: { Label("Edit", systemImage: "pencil").labelStyle(.iconOnly) }
                            .tint(DS.Color.accent)
                        }
                    }
                }
            }
        }
        .dsFormStyle()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.sheet = .settings } label: {
                    Image(systemName: "gearshape")
                }
                .tint(DS.Color.titaniumLight)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .addHost } label: {
                    Image(systemName: "plus")
                }
                .tint(DS.Color.titaniumLight)
            }
        }
    }

    @ViewBuilder
    private func hostRow(_ host: RemoteHost) -> some View {
        HostRow(host: host, connected: connectedHosts.contains(host.id))
    }

    private func reload() async {
        hosts = await HostStore.shared.all()
        OnboardingCoach.shared.startIfNeeded(hostCount: hosts.count)
        await refreshConnections()
        await handleDeepLink()
    }

    private func refreshConnections() async {
        connectedHosts = await SessionStore.shared.connectedHostIDs()
    }

    private func handleDeepLink() async {
        guard deepLinks.pendingSessionRef != nil else { return }
        let allSessions = await SessionStore.shared.allSessions()
        if let (host, session) = deepLinks.resolve(sessions: allSessions, hosts: hosts) {
            _ = deepLinks.consume()
            router.openSession(session, host: host)
        }
    }
}

private struct HostRow: View {
    let host: RemoteHost
    let connected: Bool

    @State private var summary: ServerMetricsSample?
    @AppStorage(MetricsSettings.intervalKey) private var intervalSeconds: Int = MetricsSettings.defaultIntervalSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            header
            if connected, let s = summary {
                metricsGrid(for: s)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .task(id: connected) {
            guard connected else {
                summary = nil
                return
            }
            await stream()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(DS.Color.titanium)
                    .frame(width: 28, height: 24)
                DSStatusIndicator(style: .dot(active: connected))
                    .scaleEffect(0.7)
                    .offset(x: 6, y: -4)
                    .accessibilityLabel(connected ? "Connected" : "Not connected")
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(host.name).font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    if let pid = host.agentProfileID,
                       let p = AgentProfile.builtins.first(where: { $0.id == pid }) {
                        AgentChip(profile: p)
                    }
                }
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if connected, let s = summary {
                trailingCaptions(for: s)
            }
        }
    }

    @ViewBuilder
    private func trailingCaptions(for s: ServerMetricsSample) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            if let load = s.load {
                HStack(spacing: 3) {
                    Image(systemName: "speedometer").font(.system(size: 10))
                    Text(String(format: "%.2f", load.one))
                }
                .foregroundStyle(loadColor(load.one, cpus: s.host.cpuCount))
            }
            if let up = s.uptime, up > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "power").font(.system(size: 10))
                    Text(shortUptime(up))
                }
                .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
    }

    @ViewBuilder
    private func metricsGrid(for s: ServerMetricsSample) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            MetricRingTile(
                label: "CPU",
                percent: s.cpu?.totalPercent,
                sub: s.host.cpuCount > 0 ? "\(s.host.cpuCount) C" : nil
            )
            MetricRingTile(
                label: "MEM",
                percent: memoryPercent(s.memory),
                sub: s.memory.map { byteShort($0.usedBytes) }
            )
            MetricRingTile(
                label: "DISK",
                percent: rootDiskPercent(s.disks),
                sub: rootDisk(s.disks).map { byteShort($0.usedBytes) }
            )
            MetricNetTile(iface: primaryInterface(s.network))
        }
    }

    private func stream() async {
        guard let sid = await firstConnectedSessionID(for: host.id) else { return }
        let stream = await MetricsStore.shared.samples(
            sessionID: sid,
            channelProvider: { await SessionStore.shared.channel(for: sid) },
            interval: .seconds(intervalSeconds)
        )
        for await event in stream {
            await MainActor.run {
                if case .sample(let s) = event { summary = s }
            }
        }
    }
}

private struct MetricRingTile: View {
    let label: String
    let percent: Double?
    let sub: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(DS.Color.textSecondary)
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(clampedFraction))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ringColor)
            }
            .frame(width: 42, height: 42)
            Text(sub ?? " ")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var clampedFraction: Double {
        guard let p = percent else { return 0 }
        return max(0, min(1, p / 100))
    }

    private var ringColor: Color {
        guard let p = percent else { return DS.Color.titanium }
        if p >= 90 { return DS.Color.error }
        if p >= 75 { return DS.Color.warning }
        return DS.Color.success
    }
}

private struct MetricNetTile: View {
    let iface: NetInterfaceSample?

    var body: some View {
        VStack(spacing: 4) {
            Text("NET")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(DS.Color.textSecondary)
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up").font(.system(size: 9))
                    Text(rateText(iface?.txBytesPerSec))
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down").font(.system(size: 9))
                    Text(rateText(iface?.rxBytesPerSec))
                }
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(DS.Color.textPrimary)
            .frame(height: 42, alignment: .center)
            Text(iface?.name ?? " ")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func rateText(_ bps: Double?) -> String {
        guard let bps else { return "—" }
        return rateShort(bps)
    }
}

private func memoryPercent(_ m: MemorySample?) -> Double? {
    guard let m, m.totalBytes > 0 else { return nil }
    return Double(m.usedBytes) / Double(m.totalBytes) * 100
}

private func rootDisk(_ disks: [DiskSample]) -> DiskSample? {
    if let root = disks.first(where: { $0.mountPoint == "/" }) { return root }
    return disks
        .filter { !isPseudoFS($0.fsType) && $0.totalBytes > 0 }
        .max(by: { $0.totalBytes < $1.totalBytes })
}

private func rootDiskPercent(_ disks: [DiskSample]) -> Double? {
    guard let d = rootDisk(disks), d.totalBytes > 0 else { return nil }
    return Double(d.usedBytes) / Double(d.totalBytes) * 100
}

private func primaryInterface(_ network: [NetInterfaceSample]) -> NetInterfaceSample? {
    let physical = network.filter { $0.name != "lo" && $0.name != "lo0" }
    return physical.max(by: { ($0.rxBytesTotal + $0.txBytesTotal) < ($1.rxBytesTotal + $1.txBytesTotal) })
        ?? network.first
}

private func isPseudoFS(_ type: String) -> Bool {
    switch type {
    case "tmpfs", "devtmpfs", "devfs", "overlay", "squashfs", "proc", "sysfs",
         "cgroup", "cgroup2", "debugfs", "tracefs", "mqueue", "hugetlbfs",
         "autofs", "fusectl", "configfs", "securityfs", "pstore", "ramfs",
         "binfmt_misc", "bpf":
        return true
    default:
        return false
    }
}

private func byteShort(_ bytes: UInt64) -> String {
    let fmt = ByteCountFormatter()
    fmt.countStyle = .binary
    fmt.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return fmt.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}

private func rateShort(_ bps: Double) -> String {
    let safe = max(0, bps)
    let fmt = ByteCountFormatter()
    fmt.countStyle = .binary
    fmt.allowedUnits = [.useKB, .useMB, .useGB]
    return "\(fmt.string(fromByteCount: Int64(safe)))/s"
}

private func shortUptime(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let days = total / 86400
    let hours = (total % 86400) / 3600
    if days > 0 { return "\(days)d" }
    if hours > 0 { return "\(hours)h" }
    let minutes = (total % 3600) / 60
    return "\(minutes)m"
}

private func loadColor(_ load: Double, cpus: Int) -> Color {
    let ratio = load / Double(max(cpus, 1))
    if ratio > 1.5 { return DS.Color.error }
    if ratio > 1.0 { return DS.Color.warning }
    return DS.Color.textSecondary
}

/// Uses fullScreenCover on iPad (regular width) and sheet on iPhone (compact width).
private struct SheetOrFullScreen<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let sizeClass: UserInterfaceSizeClass?
    @ViewBuilder let content: (Item) -> SheetContent

    func body(content parent: Content) -> some View {
        if sizeClass == .regular {
            parent.fullScreenCover(item: $item) { it in
                content(it)
                    .background(DS.Color.surface0)
            }
        } else {
            parent.sheet(item: $item) { it in
                content(it)
            }
        }
    }
}
#endif
