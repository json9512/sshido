import Foundation
import os

public enum Log {
    private static let subsystem = "com.sshido"

    public static let ssh = Logger(subsystem: subsystem, category: "ssh")
    public static let push = Logger(subsystem: subsystem, category: "push")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let oauth = Logger(subsystem: subsystem, category: "oauth")
    public static let store = Logger(subsystem: subsystem, category: "store")
}
