import Foundation
import os

/// Thin wrapper around `os.Logger` with a fixed subsystem and categorized loggers.
/// Use in place of `print` and to replace silent `try?` sites so errors show in Console.app.
public enum Log {
    private static let subsystem = "com.sshido"

    public static let ssh = Logger(subsystem: subsystem, category: "ssh")
    public static let push = Logger(subsystem: subsystem, category: "push")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let voice = Logger(subsystem: subsystem, category: "voice")
    public static let oauth = Logger(subsystem: subsystem, category: "oauth")
    public static let store = Logger(subsystem: subsystem, category: "store")
}
