import Foundation
import Combine

@MainActor
final class ModeManager: ObservableObject {
    @Published private(set) var activeMode: VisionMode = VisionMode.general
    @Published private(set) var allModes: [VisionMode] = []
    @Published private(set) var hiddenBuiltInModeIds: Set<String> = []

    private static let customModesKey = "RayBanClaude_CustomModes"
    private static let hiddenModesKey = "RayBanClaude_HiddenBuiltInModes"
    private static let activeModeKey = "RayBanClaude_ActiveModeId"

    init() {
        loadModes()
    }

    /// Modi für die Auswahlleiste (ausgeblendete eingebaute Modi fehlen)
    var visibleModes: [VisionMode] {
        allModes.filter { !($0.isBuiltIn && hiddenBuiltInModeIds.contains($0.id)) }
    }

    var customModes: [VisionMode] {
        allModes.filter { !$0.isBuiltIn }
    }

    // MARK: - Eigene Modi

    func addCustomMode(name: String, icon: String, color: String, prompt: String, quickActions: [String]) {
        let mode = VisionMode(
            id: "custom_\(UUID().uuidString.prefix(8).lowercased())",
            name: String(name.prefix(40)),
            icon: icon,
            color: color,
            systemPrompt: String(prompt.prefix(3000)),
            quickActions: Array(quickActions.prefix(6)),
            isBuiltIn: false
        )
        allModes.append(mode)
        saveCustomModes()
    }

    func deleteCustomMode(id: String) {
        allModes.removeAll { $0.id == id && !$0.isBuiltIn }
        if activeMode.id == id {
            setActiveMode(VisionMode.general)
        }
        saveCustomModes()
    }

    func setActiveMode(_ mode: VisionMode) {
        activeMode = mode
        UserDefaults.standard.set(mode.id, forKey: Self.activeModeKey)
    }

    func toggleBuiltInModeVisibility(id: String) {
        if hiddenBuiltInModeIds.contains(id) {
            hiddenBuiltInModeIds.remove(id)
        } else {
            hiddenBuiltInModeIds.insert(id)
            // Der aktive Modus darf nicht unsichtbar werden
            if activeMode.id == id { setActiveMode(VisionMode.general) }
        }
        UserDefaults.standard.set(Array(hiddenBuiltInModeIds), forKey: Self.hiddenModesKey)
    }

    func isBuiltInModeVisible(_ id: String) -> Bool {
        !hiddenBuiltInModeIds.contains(id)
    }

    // MARK: - Speichern / Laden

    private func loadModes() {
        var modes = VisionMode.builtInModes
        if let data = UserDefaults.standard.data(forKey: Self.customModesKey),
           let custom = try? JSONDecoder().decode([VisionMode].self, from: data) {
            modes.append(contentsOf: custom.filter { !$0.isBuiltIn })
        }
        allModes = modes
        hiddenBuiltInModeIds = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenModesKey) ?? [])
        // „Allgemein“ kann nie ausgeblendet werden
        hiddenBuiltInModeIds.remove(VisionMode.general.id)

        let savedId = UserDefaults.standard.string(forKey: Self.activeModeKey)
        activeMode = modes.first { $0.id == savedId } ?? VisionMode.general
    }

    private func saveCustomModes() {
        if let data = try? JSONEncoder().encode(customModes) {
            UserDefaults.standard.set(data, forKey: Self.customModesKey)
        }
    }
}
