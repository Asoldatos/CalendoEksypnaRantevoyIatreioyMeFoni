import SwiftUI

struct RootView: View {
    let store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        Group {
            if store.hasCompletedOnboarding {
                NavigationStack(path: $store.path) {
                    HomeView(store: store)
                        .navigationDestination(for: AppStore.Route.self) { destination(for: $0) }
                }
            } else {
                OnboardingView(store: store)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.handleShortcutRequest() } }
    }

    @ViewBuilder
    private func destination(for route: AppStore.Route) -> some View {
        switch route {
        case .recording: RecordingView(store: store)
        case .review: if let draft = store.editingDraft { ReviewView(store: store, draft: draft) }
        case .saved: if let draft = store.editingDraft { SavedView(store: store, draft: draft) }
        }
    }
}
