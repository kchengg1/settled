import SwiftUI
import UIKit

/// The system share sheet for files we generate (CSV, PDF).
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// A generated file to hand to the share sheet.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

enum Exports {
    /// Writes text to a temp file with the given name and returns it.
    static func write(_ text: String, named name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
