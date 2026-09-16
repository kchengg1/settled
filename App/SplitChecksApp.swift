import SwiftUI
import SwiftData
import SplitChecksCore

@main
struct SplitChecksApp: App {
    @State private var model = BillFlowModel()
    private let container: ModelContainer

    init() {
        let screenshots = DemoData.isScreenshotRun
        // Screenshot runs use a throwaway in-memory store seeded with demo
        // data; real launches use the persistent store as before.
        let configuration = ModelConfiguration(isStoredInMemoryOnly: screenshots)
        let container = try! ModelContainer(for: SavedBill.self, SavedTrip.self,
                                            configurations: configuration)
        if screenshots {
            DemoData.seed(into: container.mainContext)
            _model = State(initialValue: DemoData.receiptModel())
        }
        self.container = container
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .modelContainer(container)
    }
}

/// Two modes side by side: split a single receipt, or track a trip's shared
/// expenses. Each is its own navigation stack so switching tabs preserves
/// where you were.
struct RootView: View {
    @Bindable var model: BillFlowModel

    var body: some View {
        TabView {
            NavigationStack(path: $model.path) {
                ItemsEntryView()
            }
            .environment(model)
            .tabItem { Label("Receipt", systemImage: "doc.viewfinder") }

            NavigationStack {
                TripsListView()
            }
            .tabItem { Label("Trips", systemImage: "airplane") }
        }
        .tint(Palette.accent)
    }
}

/// The linear steps after item entry, plus history. Item entry is the
/// stack root.
enum BillStep: Hashable {
    case people
    case assign
    case tipTax
    case summary
    case history
}
