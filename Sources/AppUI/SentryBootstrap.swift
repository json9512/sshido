#if canImport(Sentry)
import Foundation
import Sentry

enum SentryBootstrap {
    private static let installIDKey = "sshido.installID"

    static func start() {
        guard let hostPath = Bundle.main.object(forInfoDictionaryKey: "SentryDSNHostPath") as? String,
              !hostPath.isEmpty else {
            return
        }
        let dsn = "https://" + hostPath

        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "debug"
            options.debug = false
            #else
            options.environment = "production"
            #endif
            options.tracesSampleRate = 0.0
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.maxBreadcrumbs = 20
            options.enableAutoSessionTracking = true
            options.enableUserInteractionTracing = false
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.beforeSend = Self.scrub(event:)
            options.beforeBreadcrumb = Self.filter(breadcrumb:)
        }

        SentrySDK.configureScope { scope in
            let user = User()
            user.userId = Self.installID()
            scope.setUser(user)
        }
    }

    private static func installID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIDKey) { return existing }
        let new = UUID().uuidString
        defaults.set(new, forKey: installIDKey)
        return new
    }

    private static let sensitiveCategories: Set<String> = ["http", "ssh", "terminal"]

    private static func filter(breadcrumb: Breadcrumb) -> Breadcrumb? {
        let category = breadcrumb.category.lowercased()
        if sensitiveCategories.contains(where: { category.hasPrefix($0) }) {
            return nil
        }
        if let message = breadcrumb.message, message.count > 200 {
            return nil
        }
        breadcrumb.data = nil
        return breadcrumb
    }

    private static func scrub(event: Event) -> Event? {
        event.request = nil
        if let user = event.user {
            user.email = nil
            user.ipAddress = nil
            user.username = nil
        }
        if var device = event.context?["device"] {
            device["name"] = nil
            event.context?["device"] = device
        }
        if let crumbs = event.breadcrumbs {
            event.breadcrumbs = crumbs.compactMap(filter(breadcrumb:))
        }
        if let exceptions = event.exceptions {
            for exception in exceptions {
                if exception.value.count > 200 {
                    exception.value = "<scrubbed \(exception.value.count) chars>"
                }
                exception.stacktrace?.frames.forEach { $0.vars = nil }
            }
        }
        return event
    }
}
#else
enum SentryBootstrap {
    static func start() {}
}
#endif
