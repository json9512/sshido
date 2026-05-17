import Foundation

public enum ServerOSFamily: String, Codable, Sendable, Hashable {
    case linux
    case darwin
    case freebsd
    case openbsd
    case netbsd
    case unknown
}

public struct HostInfo: Codable, Sendable, Hashable {
    public let os: ServerOSFamily
    public let kernel: String
    public let prettyName: String?
    public let cpuCount: Int
    public let pageSize: Int
    public let bootTime: Date?

    public init(
        os: ServerOSFamily,
        kernel: String,
        prettyName: String?,
        cpuCount: Int,
        pageSize: Int,
        bootTime: Date?
    ) {
        self.os = os
        self.kernel = kernel
        self.prettyName = prettyName
        self.cpuCount = cpuCount
        self.pageSize = pageSize
        self.bootTime = bootTime
    }
}

public struct CPUSample: Codable, Sendable, Hashable {
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let iowaitPercent: Double?
    public let totalPercent: Double

    public init(
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double,
        iowaitPercent: Double?,
        totalPercent: Double
    ) {
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.iowaitPercent = iowaitPercent
        self.totalPercent = totalPercent
    }
}

public struct LoadSample: Codable, Sendable, Hashable {
    public let one: Double
    public let five: Double
    public let fifteen: Double

    public init(one: Double, five: Double, fifteen: Double) {
        self.one = one
        self.five = five
        self.fifteen = fifteen
    }
}

public struct MemorySample: Codable, Sendable, Hashable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let usedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64

    public init(
        totalBytes: UInt64,
        availableBytes: UInt64,
        usedBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64
    ) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.usedBytes = usedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct DiskSample: Codable, Sendable, Hashable, Identifiable {
    public var id: String { mountPoint }
    public let mountPoint: String
    public let filesystem: String
    public let fsType: String
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64

    public init(
        mountPoint: String,
        filesystem: String,
        fsType: String,
        totalBytes: UInt64,
        usedBytes: UInt64,
        availableBytes: UInt64
    ) {
        self.mountPoint = mountPoint
        self.filesystem = filesystem
        self.fsType = fsType
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }
}

public struct NetInterfaceSample: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
    public let rxBytesTotal: UInt64
    public let txBytesTotal: UInt64

    public init(
        name: String,
        rxBytesPerSec: Double,
        txBytesPerSec: Double,
        rxBytesTotal: UInt64,
        txBytesTotal: UInt64
    ) {
        self.name = name
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
        self.rxBytesTotal = rxBytesTotal
        self.txBytesTotal = txBytesTotal
    }
}

public struct ServerMetricsSample: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let host: HostInfo
    public let cpu: CPUSample?
    public let load: LoadSample?
    public let memory: MemorySample?
    public let disks: [DiskSample]
    public let network: [NetInterfaceSample]
    public let uptime: TimeInterval?

    public init(
        timestamp: Date,
        host: HostInfo,
        cpu: CPUSample?,
        load: LoadSample?,
        memory: MemorySample?,
        disks: [DiskSample],
        network: [NetInterfaceSample],
        uptime: TimeInterval?
    ) {
        self.timestamp = timestamp
        self.host = host
        self.cpu = cpu
        self.load = load
        self.memory = memory
        self.disks = disks
        self.network = network
        self.uptime = uptime
    }
}
