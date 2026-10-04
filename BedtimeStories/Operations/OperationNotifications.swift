import UIKit
import UserNotifications
#if !MZ_LOCAL
@preconcurrency import FirebaseMessaging
#endif

@MainActor
final class OperationNotifications: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var current: OperationNotifications?
    static var deviceID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "operationDeviceID") { return id }
        let id = UUID().uuidString; defaults.set(id, forKey: "operationDeviceID"); return id
    }
    var cloud: CloudNarrationModel?
    private var deviceToken: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Self.current = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func connect(_ cloud: CloudNarrationModel) {
        self.cloud = cloud
        #if !MZ_LOCAL
        if cloud.isConfigured {
            Messaging.messaging().delegate = self
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif
        Task { await OperationCenter.shared.refreshNotificationAuthorization(); await registerDevice() }
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        #if !MZ_LOCAL
        guard cloud?.isConfigured == true else { return }
        Messaging.messaging().apnsToken = token
        #endif
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        AppLog.warning("Remote completion alerts unavailable", error: error, category: "operations")
    }
    func registerDevice() async {
        guard let cloud, cloud.userID != nil, cloud.isConfigured, let deviceToken else { return }
        do { try await cloud.registerDevice(token: deviceToken); OperationCenter.shared.refreshLiveActivityRegistrations() }
        catch { AppLog.warning("Completion alert device registration failed", error: error, category: "operations") }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.content.userInfo["operationId"] as? String
        let owner = notification.request.content.userInfo["ownerID"] as? String
        await MainActor.run {
            if let owner, owner != OperationCenter.shared.currentOwnerID { return }
            if let id { OperationCenter.shared.receivedNotification(operationID: id) }
        }
        return []
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["operationId"] as? String
        let owner = response.notification.request.content.userInfo["ownerID"] as? String
        await MainActor.run {
            if let id { OperationCenter.shared.routeNotification(operationID: id, ownerID: owner) }
        }
    }
}
#if !MZ_LOCAL
extension OperationNotifications: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken token: String?) {
        Task { @MainActor [weak self] in self?.deviceToken = token; await self?.registerDevice() }
    }
}
#endif
