import SwiftUI
import CloudKit

/// Accepting an invitation someone sent. A tapped iCloud share link reaches
/// the app through the scene delegate, which is why the SwiftUI app installs
/// one; it hands the metadata to whoever is listening.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }
}

final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    static let didReceiveShare = Notification.Name("SplitChecks.didReceiveCloudShare")

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: Self.didReceiveShare, object: cloudKitShareMetadata)
    }
}
