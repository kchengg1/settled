import SwiftUI
import CloudKit
import UIKit

/// Apple's own sharing screen: invite people, see who's in, stop sharing.
/// We hand it a share we already saved, so it has nothing to prepare.
struct ShareGroupSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String
    var onEnd: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(title: title, onEnd: onEnd) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String
        private let onEnd: () -> Void

        init(title: String, onEnd: @escaping () -> Void) {
            self.title = title
            self.onEnd = onEnd
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String ?? title
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onEnd()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
    }
}

/// A share the app is ready to present.
struct PendingShare: Identifiable {
    let share: CKShare
    let container: CKContainer
    let title: String
    var id: String { share.recordID.recordName }
}
