import SwiftUI
import UIKit

/// Gedächtnis ansehen und verwalten: Einträge löschen, selbst ergänzen, aus der Claude-App übernehmen.
struct MemoryView: View {
    @ObservedObject var memory: MemoryStore
    @Binding var enabled: Bool

    @State private var newFact = ""
    @State private var showImport = false
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                Toggle("Claude merkt sich Dinge über dich", isOn: $enabled)
            } footer: {
                Text("Sag zum Beispiel „Hey Claude, merk dir, dass meine Tochter Mia heißt“ – oder Claude notiert sich von selbst, was dauerhaft wichtig ist. „Vergiss das mit …“ löscht wieder. Die Liste liegt nur auf diesem iPhone und geht zu Beginn jedes Gesprächs an Claude.")
            }

            if enabled {
                Section {
                    Button {
                        showImport = true
                    } label: {
                        Label("Aus der Claude-App übernehmen", systemImage: "square.and.arrow.down.on.square")
                    }
                    HStack {
                        TextField("Selbst eintragen, z. B. „Trinkt Espresso ohne Zucker“", text: $newFact)
                            .submitLabel(.done)
                            .onSubmit(addFact)
                        Button("Merken", action: addFact)
                            .disabled(MemoryStore.clean(newFact).isEmpty)
                    }
                }

                Section {
                    if memory.items.isEmpty {
                        Text("Noch nichts gemerkt.").foregroundStyle(.secondary)
                    }
                    ForEach(memory.items.reversed()) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                            Text(item.created, format: .dateTime.day().month().year())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        // Anzeige ist umgekehrt (neueste oben) → Indizes zurückrechnen
                        let count = memory.items.count
                        memory.remove(at: IndexSet(offsets.map { count - 1 - $0 }))
                    }
                } header: {
                    Text("Gemerkt (\(memory.items.count))")
                } footer: {
                    Text("Zum Löschen nach links wischen.")
                }

                if !memory.items.isEmpty {
                    Section {
                        Button("Alles vergessen", role: .destructive) { confirmClear = true }
                    }
                }
            }
        }
        .navigationTitle("Gedächtnis")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImport) { MemoryImportView(memory: memory) }
        .confirmationDialog("Wirklich alle \(memory.items.count) Einträge löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Alles vergessen", role: .destructive) { memory.clear() }
        }
    }

    private func addFact() {
        guard memory.add(newFact) != nil else { return }
        newFact = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Übernahme aus der offiziellen Claude-App: Dort fragt man Claude nach einer Zusammenfassung
/// und fügt sie hier ein. (Eine Schnittstelle zum direkten Auslesen der Chats gibt es nicht.)
struct MemoryImportView: View {
    @ObservedObject var memory: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var copied = false

    static let prompt = "Fasse in kurzen Stichpunkten zusammen, was du aus unseren bisherigen Chats dauerhaft über mich weißt: Namen, Familie, Beruf, Vorlieben, Pläne, wichtige Termine. Eine Zeile pro Punkt, ohne Einleitung."

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    step(1, "Öffne die Claude-App (oder claude.ai) und schick Claude diese Frage:")
                    Text(Self.prompt)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        UIPasteboard.general.string = Self.prompt
                        copied = true
                    } label: {
                        Label(copied ? "Kopiert ✓" : "Frage kopieren", systemImage: "doc.on.doc")
                    }
                    step(2, "Kopiere Claudes Antwort und füge sie unten ein.")
                } header: {
                    Text("So geht’s")
                } footer: {
                    Text("Noch einfacher am PC: Mit RayBan Claude ist die Claude-Desktop-App verknüpft. Sag dort einfach „Übertrag, was du über mich weißt, an die Brille“ – Claude schreibt es direkt hierher.")
                }

                Section {
                    TextEditor(text: $text).frame(minHeight: 160)
                    // PasteButton fügt ohne die Rückfrage „Einfügen erlauben?“ ein
                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first { text = pasted }
                    }
                } header: {
                    Text("Antwort von Claude")
                } footer: {
                    Text("Jede Zeile wird ein Eintrag. Lies kurz drüber und lösch, was Claude nicht wissen soll – alles bleibt nur auf diesem iPhone.")
                }
            }
            .navigationTitle("Aus der Claude-App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Übernehmen") {
                        _ = memory.importLines(text)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
}
