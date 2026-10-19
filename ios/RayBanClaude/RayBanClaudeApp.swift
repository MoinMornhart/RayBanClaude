import SwiftUI
import MWDATCore

/// Ob das Meta-SDK bereit ist – ohne erfolgreiche Konfiguration darf Wearables.shared nicht genutzt werden
@MainActor
enum WearablesSupport {
    static var isConfigured = false
}

@main
struct RayBanClaudeApp: App {
    @StateObject private var viewModel: SessionViewModel

    init() {
        // Das DAT SDK muss vor jedem Zugriff auf Wearables.shared konfiguriert sein
        do {
            try Wearables.configure()
            WearablesSupport.isConfigured = true
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
