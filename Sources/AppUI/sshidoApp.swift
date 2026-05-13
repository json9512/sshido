import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        SentryBootstrap.start()
        let callback = HostKeyChallengeBroker.shared.makeCallback()
        Task { await SessionStore.shared.setHostKeyConfirm(callback) }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let event = Self.agentEvent(for: notification)
        Task { @MainActor in
            if let event { AgentEventFeedback.shared.fire(event) }
        }
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Map an incoming push into an AgentEvent. Priority is the primary
    /// signal (agent setup prompt sets 'high' for Notification + StopFailure,
    /// 'normal' for Stop). Title substring refines high-priority pushes
    /// between "needs input" and "error".
    private static func agentEvent(for notification: UNNotification) -> AgentEvent? {
        let info = notification.request.content.userInfo
        let aps = info["aps"] as? [String: Any]
        let priority = (info["priority"] as? String) ?? (aps?["priority"] as? String)
        let title = notification.request.content.title.lowercased()
        if priority == "high" {
            return title.contains("error") ? .finishedError : .needsInput
        }
        return .finishedOk
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in DeepLinkRouter.shared.handleNotification(userInfo: info) }
        completionHandler()
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PushService.shared.update(deviceToken: token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

@main
struct sshidoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var router = AppRouter.shared
    @StateObject private var hostKeyBroker = HostKeyChallengeBroker.shared
    @State private var showConsent = false

    init() {
        // Navigation bar — dark metallic, no border
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(DS.Color.surface0)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(DS.Color.textPrimary)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(DS.Color.textPrimary)]
        navAppearance.shadowColor = .clear
        navAppearance.shadowImage = UIImage()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(DS.Color.accent)

        // Segmented control — accent on surface2
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(DS.Color.accent)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(DS.Color.surface0)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(DS.Color.textSecondary)], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor(DS.Color.surface2)

        // Switch/Toggle tint
        UISwitch.appearance().onTintColor = UIColor(DS.Color.accent)
    }

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $showConsent) {
                    ConsentView { showConsent = false }
                }
                .presentingHostKeyChallenge()
                .onAppear {
                    if !UserDefaults.standard.bool(forKey: "sshido.privacyAccepted") {
                        showConsent = true
                    }
                }
        }
    }
}
#endif
