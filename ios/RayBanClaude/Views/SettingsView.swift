import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var rayBanManager: RayBanManager
    @ObservedObject var modeManager: ModeManager
    @Environment(\.dismiss) private var dismiss

    @State private var portText = ""
    @State private var testResult: (ok: Bool, text: String)?
    @State private var isTesting = false
    @State private var showRayBanInstructions = false
    @State private var showAddCustomMode = false

    private let accent = Color.anthropicOrange

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                directSection
                memorySection
                modesSection
                cameraSection
                rayBanSection
                voiceSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Einstellungen")
            .tint(accent)
            .sheet(isPresented: $showRayBanInstructions) { RayBanInstructionsView() }
            .sheet(isPresented: $showAddCustomMode) { AddCustomModeView(modeManager: modeManager) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isConnected ? "Neu verbinden" : "Verbinden") {
                        Task { await viewModel.connect() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { portText = String(viewModel.config.gatewayPort) }
        }
    }

    // MARK: - Verbindung

    private var connectionSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(viewModel.isConnected ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isConnected ? "Verbunden" : "Nicht verbunden").font(.headline)
                    Text(connectionDetail)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Picker("Verbindungsart", selection: $viewModel.config.connectionMode) {
                ForEach(ConnectionMode.allCases) { Text($0.label).tag($0) }
            }

            if viewModel.config.connectionMode.usesPC {
                LabeledContent("PC-Adresse") {
                    TextField("192.168.178.20", text: $viewModel.config.gatewayHost)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                LabeledContent("Unterwegs (Tailscale)") {
                    TextField("100.x.y.z – optional", text: $viewModel.config.remoteHost)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                LabeledContent("Port") {
                    // Eigener Textzustand: früher sprang das Feld beim Löschen sofort auf 18790 zurück
                    TextField("18790", text: $portText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: portText) { _, text in
                            if let port = Int(text), (1024...65535).contains(port) { viewModel.config.gatewayPort = port }
                        }
                }
                LabeledContent("Token") {
                    SecureField("aus dem Dashboard", text: $viewModel.config.channelToken)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Label("Verbindung testen", systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        } else if let testResult {
                            Text(testResult.text).font(.caption).foregroundStyle(testResult.ok ? .green : .red)
                        }
                    }
                }
            }
        } header: {
            Text("Verbindung")
        } footer: {
            Text(connectionFooter)
        }
    }

    private var connectionDetail: String {
        guard viewModel.isConnected else { return "QR-Code scannen oder Daten eintragen" }
        return viewModel.viaTailscale ? "Unterwegs über Tailscale – läuft über dein Claude-Abo" : "PC erreichbar, Token gültig"
    }

    private var connectionFooter: String {
        switch viewModel.config.connectionMode {
        case .channel:
            return "Am einfachsten: Auf dem PC start.cmd doppelklicken und den QR-Code im Dashboard mit der iPhone-Kamera scannen. Kostenlos mit deinem Claude-Abo, alle PC-Werkzeuge verfügbar. Unterwegs: Tailscale (kostenlos) auf PC und iPhone installieren und neu koppeln – dann fragt die App auch über mobile Daten deinen PC zu Hause, weiter über dein Abo."
        case .gateway:
            return "Gateway-Modus: eigener Server auf dem PC mit Anthropic-API-Key (kostet pro Anfrage). Das Token steht beim Start im Server-Fenster."
        case .direct:
            return "Ohne PC: Das iPhone fragt Claude direkt über das Internet (auch mobile Daten). Braucht einen API-Key, siehe unten."
        }
    }

    // MARK: - Ohne PC

    private var directSection: some View {
        Section {
            LabeledContent("API-Key") {
                SecureField("sk-ant-…", text: $viewModel.config.anthropicAPIKey)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if !viewModel.config.anthropicAPIKey.isEmpty && !viewModel.config.hasDirectKey {
                Label("Das sieht nicht wie ein Anthropic-API-Key aus (beginnt mit sk-ant-)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Picker("Modell", selection: $viewModel.config.directModel) {
                ForEach(DirectClaudeClient.models) { model in
                    VStack(alignment: .leading) {
                        Text(model.name)
                        Text(model.hint).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(model.id)
                }
            }
            if viewModel.config.connectionMode.usesPC {
                Toggle("Automatisch, wenn der PC nicht erreichbar ist", isOn: $viewModel.config.directFallback)
            }
            Toggle("Websuche (Wetter, Öffnungszeiten …)", isOn: $viewModel.config.webSearchEnabled)
            if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                Link(destination: url) { Label("API-Key bei Anthropic erstellen", systemImage: "key") }
            }
        } header: {
            Text("Ohne PC (unterwegs)")
        } footer: {
            Text("Kostet pro Frage – mit Claude Opus 5.5 meist 1–3 Cent, Sonnet etwa die Hälfte, Haiku ein Bruchteil; jede Websuche ca. 1 Cent. Dein Claude-Abo gilt hier nicht – über dein Abo geht es unterwegs nur mit Tailscale (siehe oben). Werkzeuge vom PC (E-Mail, Dateien) gibt es ohne PC nicht – Timer, Anrufe, Navigation und Fotos schon. Der Key liegt nur im Schlüsselbund dieses iPhones.")
        }
    }

    // MARK: - Gedächtnis

    private var memorySection: some View {
        Section {
            NavigationLink {
                MemoryView(memory: viewModel.memory, enabled: $viewModel.config.memoryEnabled)
            } label: {
                LabeledContent {
                    Text(viewModel.config.memoryEnabled ? "\(viewModel.memory.items.count) Einträge" : "aus")
                } label: {
                    Label("Was Claude über dich weiß", systemImage: "brain.head.profile")
                }
            }
        } header: {
            Text("Gedächtnis")
        } footer: {
            Text("„Hey Claude, merk dir …“ – Claude behält es, mit und ohne PC. Aus der Claude-App übernimmst du dein Wissen mit einem Schritt.")
        }
    }

    // MARK: - Modi

    private var modesSection: some View {
        Section {
            ForEach(VisionMode.builtInModes) { mode in
                Toggle(isOn: Binding(
                    get: { modeManager.isBuiltInModeVisible(mode.id) },
                    set: { _ in modeManager.toggleBuiltInModeVisibility(id: mode.id) }
                )) {
                    Label { Text(mode.name) } icon: { Image(systemName: mode.icon).foregroundStyle(mode.swiftColor) }
                }
                .disabled(mode.id == VisionMode.general.id)
            }
            ForEach(modeManager.customModes) { mode in
                Label { Text(mode.name) } icon: { Image(systemName: mode.icon).foregroundStyle(mode.swiftColor) }
            }
            .onDelete { indexSet in
                let modes = modeManager.customModes
                indexSet.map { modes[$0].id }.forEach { modeManager.deleteCustomMode(id: $0) }
            }
            Button {
                showAddCustomMode = true
            } label: {
                Label("Eigenen Modus anlegen", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Experten-Modi")
        } footer: {
            Text("Modi geben Claude Fachwissen und Antwortstil vor. Aktiver Modus: \(modeManager.activeMode.name). Eigene Modi zum Löschen nach links wischen.")
        }
    }

    // MARK: - Kamera

    private var cameraSection: some View {
        Section {
            Picker("Kamera", selection: $viewModel.activeFrameSource) {
                ForEach(FrameSourceType.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)

            LabeledContent("Status", value: viewModel.frameSourceStatus.label)

            VStack(alignment: .leading) {
                LabeledContent("Bild an Claude alle", value: String(format: "%.1f s", viewModel.config.videoFrameInterval))
                Slider(value: $viewModel.config.videoFrameInterval, in: 0.5...5.0, step: 0.5)
            }
            VStack(alignment: .leading) {
                LabeledContent("JPEG-Qualität", value: "\(Int(viewModel.config.videoJPEGQuality * 100)) %")
                Slider(value: $viewModel.config.videoJPEGQuality, in: 0.3...1.0, step: 0.05)
            }
        } header: {
            Text("Kamera")
        } footer: {
            Text("Mit jeder Frage geht das aktuelle Bild an Claude. Höhere Qualität hilft beim Lesen von Text, braucht aber mehr Daten.")
        }
    }

    // MARK: - Brille

    private var rayBanSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "eyeglasses").font(.system(size: 22)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rayBanManager.deviceModel ?? rayBanManager.glassesName).font(.body)
                    if rayBanManager.deviceModel != nil {
                        Text(rayBanManager.glassesName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let battery = rayBanManager.batteryLevel {
                    Label("\(battery) %", systemImage: batteryIcon(battery)).font(.caption)
                }
            }
            LabeledContent("Registrierung", value: rayBanManager.registrationLabel)
            if let open = rayBanManager.hingesOpen {
                LabeledContent("Bügel", value: open ? "offen" : "geschlossen")
            }
            if let hint = rayBanManager.updateHint {
                Label(hint, systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.orange)
            }
            if rayBanManager.isRegistered {
                Button("Brille abmelden", role: .destructive) {
                    Task { await rayBanManager.unregister() }
                }
            } else {
                Button {
                    Task { await viewModel.connectGlasses() }
                } label: {
                    Label("Brille über Meta AI verbinden", systemImage: "link.circle.fill")
                }
            }
            Button {
                showRayBanInstructions = true
            } label: {
                Label("Anleitung Ray-Ban Meta Gen 2", systemImage: "book.closed.fill")
            }
        } header: {
            Text("Ray-Ban Meta")
        } footer: {
            Text("Einmalig registrieren: Die Meta-AI-App öffnet sich zur Bestätigung. Danach unten rechts auf „Brille“ tippen.")
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: - Sprache

    private var voiceSection: some View {
        Section {
            Picker("Sprache", selection: $viewModel.config.speechLanguage) {
                ForEach(ClaudeConfig.supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
            }
            VStack(alignment: .leading) {
                LabeledContent("Senden nach Sprechpause", value: String(format: "%.1f s", viewModel.config.speechPauseThreshold))
                Slider(value: $viewModel.config.speechPauseThreshold, in: 0.5...3.0, step: 0.25)
            }
            Toggle("Weckwort „Hey Claude“ / „Claudi“", isOn: $viewModel.config.wakeWordEnabled)
            Toggle("Nach Antwort kurz weiter zuhören", isOn: $viewModel.config.autoListen)
            Toggle("Bei gesperrtem iPhone weiterhören", isOn: $viewModel.config.listenWhenLocked)
            Toggle("Display anlassen, solange die App offen ist", isOn: $viewModel.config.keepScreenOn)

            if viewModel.config.connectionMode != .channel {
                LabeledContent("ElevenLabs-Key") {
                    SecureField("optional", text: $viewModel.config.elevenLabsAPIKey)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !viewModel.config.elevenLabsAPIKey.isEmpty {
                    Picker("Stimme", selection: $viewModel.config.elevenLabsVoiceId) {
                        ForEach(ElevenLabsVoice.allVoices) { Text("\($0.name) – \($0.description)").tag($0.id) }
                    }
                }
            }
        } header: {
            Text("Sprache & Stimme")
        } footer: {
            Text((viewModel.config.wakeWordEnabled
                  ? "Mit Weckwort hört die App freihändig zu – wie bei Meta AI auch mit gesperrtem iPhone in der Tasche (oben rechts erscheint dann der orange Mikrofon-Punkt). Sag „Hey Claude“ oder „Claudi“ und dann deine Frage. Die Erkennung läuft nur auf dem iPhone. "
                  : "")
                 + (viewModel.config.connectionMode == .channel
                 ? "Standard ist die kostenlose iPhone-Stimme. Eine ElevenLabs-Stimme stellst du im PC-Dashboard ein. Tipp: Unter iOS-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen eine „Premium“-Stimme laden – klingt deutlich natürlicher."
                 : "Ohne ElevenLabs-Key spricht die kostenlose iPhone-Stimme."))
        }
    }

    // MARK: - Über

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            if let url = URL(string: "https://github.com/MoinMornhart/RayBanClaude") {
                Link(destination: url) { Label("Projekt auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
        } header: {
            Text("Über RayBan Claude")
        } footer: {
            Text("Open Source (MIT), Fork von visionclaude. Inoffizielles Projekt – nicht verbunden mit Meta, Ray-Ban/EssilorLuxottica oder Anthropic.")
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                try await viewModel.bridge.checkAuthorized()
                testResult = (true, "OK – Token gültig")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                testResult = (false, error.localizedDescription)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isTesting = false
        }
    }
}

// MARK: - Eigener Modus

struct AddCustomModeView: View {
    @ObservedObject var modeManager: ModeManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "#E87B35"
    @State private var systemPrompt = ""
    @State private var quickActionsText = ""

    private let iconOptions = [
        "star.fill", "heart.fill", "flame.fill", "leaf.fill", "hammer.fill", "paintbrush.fill", "wrench.fill", "scissors",
        "cart.fill", "bag.fill", "house.fill", "car.fill", "cross.case.fill", "stethoscope", "pill.fill", "book.fill",
        "graduationcap.fill", "music.note", "camera.fill", "fork.knife", "cup.and.saucer.fill", "pawprint.fill",
        "map.fill", "lightbulb.fill",
    ]
    private let colorOptions = [
        "#E87B35", "#EF4444", "#F59E0B", "#EAB308", "#22C55E", "#06B6D4",
        "#3B82F6", "#6366F1", "#A855F7", "#EC4899", "#F43F5E", "#84CC16",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. Koch, Gärtner, Nachhilfe", text: $name)
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button { selectedIcon = icon } label: {
                                Image(systemName: icon)
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? (Color(hex: selectedColor) ?? .orange) : Color(.systemGray5)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button { selectedColor = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .orange)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    TextEditor(text: $systemPrompt).frame(minHeight: 110)
                } header: {
                    Text("Anweisung an Claude")
                } footer: {
                    Text("Beschreibe Fachgebiet und Antwortstil, z. B. „Du bist Koch. Erkenne Zutaten und schlage schnelle Gerichte vor.“")
                }
                Section {
                    TextField("Was ist das?, Wie koche ich das?", text: $quickActionsText)
                } header: {
                    Text("Schnellbefehle (mit Komma getrennt)")
                }
            }
            .navigationTitle("Neuer Modus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let actions = quickActionsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        modeManager.addCustomMode(
            name: name.trimmingCharacters(in: .whitespaces),
            icon: selectedIcon,
            color: selectedColor,
            prompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            quickActions: actions
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Anleitung Brille

struct RayBanInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Voraussetzungen") {
                    Text("Ray-Ban Meta (Gen 2 oder Gen 1), Oakley Meta oder Meta Ray-Ban Display")
                    Text("Meta-AI-App (mind. Version 290) – Brille dort gekoppelt")
                    Text("Aktuelle Brillen-Firmware (mind. V128) – die Meta-AI-App fragt nach Updates")
                    linkRow("Meta-AI-App laden", "https://apps.apple.com/app/meta-ai/id1662457680")
                }
                Section("1 · Entwicklermodus einschalten") {
                    step(1, "Meta-AI-App → Einstellungen → deine Brille → Entwicklermodus → an")
                    step(2, "Brille neu starten: Taste 15 Sekunden halten, dann kurz drücken")
                    Text("Der Entwicklermodus kann sich nach Firmware-Updates wieder abschalten – dann erneut aktivieren.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("2 · In RayBan Claude verbinden") {
                    step(3, "Einstellungen → „Brille über Meta AI verbinden“")
                    step(4, "In der Meta-AI-App „Erlauben“ tippen – du landest wieder hier")
                    step(5, "Unten rechts auf „Brille“ umschalten und die Kamera-Freigabe bestätigen")
                }
                Section("Tipps für Gen 2") {
                    Text("Bügel aufklappen – bei geschlossenen Bügeln stoppt der Stream (er startet beim Öffnen automatisch neu).")
                    Text("Ein Tipp auf das Touchpad pausiert den Stream, ein weiterer setzt ihn fort.")
                    Text("Claude kann selbst ein scharfes Foto mit der Brille aufnehmen, z. B. zum Lesen von Text.")
                    Text("Unter 10 % Akku verweigert die Brille den Kamerastream.")
                }
                Section("Probleme?") {
                    Text("Keine Brille gefunden: eingeschaltet, Bügel offen, in der Meta-AI-App verbunden?")
                    Text("„Gerät nicht verfügbar“: Brille aus- und einschalten, dann erneut verbinden.")
                    linkRow("Meta Wearables Doku", "https://wearables.developer.meta.com/docs/develop/")
                }
            }
            .navigationTitle("Ray-Ban Meta einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.anthropicOrange))
            Text(text)
        }
    }

    @ViewBuilder
    private func linkRow(_ title: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) { Label(title, systemImage: "arrow.up.right.square") }
        }
    }
}
