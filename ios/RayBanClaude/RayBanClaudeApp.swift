import SwiftUI
import MWDATCore

@main
struct RayBanClaudeApp: App {
    @StateObject private var viewModel: SessionViewModel

    init() {
        // Das DAT SDK muss vor jedem Zugriff auf Wearables.shared konfiguriert sein
        do {
            try Wearables.configure()
        } catch {
            print("[App] Meta-SDK konnte nicht konfiguriert werden: \(error)")
        }
        _viewModel = StateObject(wrappedValue: SessionViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                // Kopplungs-QR-Code (raybanclaude://pair?…) und Rückrufe der Meta-AI-App
                .onOpenURL { url in viewModel.handleIncomingURL(url) }
        }
    }
}
