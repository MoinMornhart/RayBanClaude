import Foundation
import Contacts
import CoreLocation
import EventKit
import MessageUI
import Photos
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Modelle

/// Aktion, die Claude per Tool `phone_action` auf dem iPhone auslöst
struct PhoneAction: Identifiable {
    enum Kind: String {
        case timer, alarm, cancel_timer, call, message, navigate, reminder, save_photo, location
    }

    let id: String
    let kind: Kind
    var durationSeconds: Int?
    var time: String?
    /// Erinnerung: Tag als JJJJ-MM-TT
    var date: String?
    var label: String?
    var contact: String?
    var number: String?
    var text: String?
    var destination: String?
}

struct RunningTimer: Identifiable, Equatable {
    let id: String
    let label: String
    let fireDate: Date
    let isAlarm: Bool
}

/// Rückfrage vor Anruf, Nachricht oder Navigation (nie ohne Bestätigung)
struct ActionConfirmation: Identifiable, Equatable {
    struct Option: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: String
    }

    enum Kind: Equatable {
        case call
        case message(text: String)
        case navigate
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let options: [Option]

    static func == (lhs: ActionConfirmation, rhs: ActionConfirmation) -> Bool { lhs.id == rhs.id }
}

struct MessageDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let text: String
}

struct ActionResult {
    let ok: Bool
    let message: String
}

// MARK: - Ausführung

/// Führt Handy-Aktionen aus. Kontakte werden nur lokal gesucht – an Claude gehen
/// nie Telefonnummern, nur Name und Art („Mama (Mobil)“).
@MainActor
final class PhoneActionHandler: NSObject, ObservableObject {
    @Published private(set) var timers: [RunningTimer] = []
    @Published var confirmation: ActionConfirmation?
    @Published var messageDraft: MessageDraft?

    /// Timer/Wecker abgelaufen, während die App offen ist → ansagen
    var onTimerFired: ((RunningTimer) -> Void)?
    /// Liefert das Foto, das Claude gerade gesehen hat (oder macht ein neues) – für save_photo
    var latestPhoto: (() async -> Data?)?
    /// Gedächtnis für „Merk dir, wo ich geparkt habe“
    weak var memory: MemoryStore?

    private let center = UNUserNotificationCenter.current()
    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()
    private let locator = LocationProvider()
    private var fallbackTasks: [String: Task<Void, Never>] = [:]
    private static let idPrefix = "raybanclaude.timer."

    override init() {
        super.init()
        center.delegate = self
        Task { await refreshTimers() }
    }

    func handle(_ action: PhoneAction) async -> ActionResult {
        switch action.kind {
        case .timer:
            guard let seconds = action.durationSeconds, seconds > 0 else { return ActionResult(ok: false, message: "Dauer fehlt") }
            return await schedule(label: action.label ?? "Timer", fireDate: Date().addingTimeInterval(TimeInterval(seconds)),
                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false),
                                  isAlarm: false)
        case .alarm:
            guard let next = Self.nextOccurrence(of: action.time) else {
                return ActionResult(ok: false, message: "Uhrzeit nicht verstanden")
            }
            return await schedule(label: action.label ?? "Wecker", fireDate: next.date,
                                  trigger: UNCalendarNotificationTrigger(dateMatching: next.components, repeats: false),
                                  isAlarm: true)
        case .cancel_timer:
            return await cancelTimers(matching: action.label)
        case .call:
            return await prepareContactAction(action, kind: .call, verb: "Anruf an")
        case .message:
            guard let text = action.text, !text.isEmpty else { return ActionResult(ok: false, message: "Nachrichtentext fehlt") }
            return await prepareContactAction(action, kind: .message(text: text), verb: "Nachricht an")
        case .navigate:
            guard let destination = action.destination, !destination.isEmpty else {
                return ActionResult(ok: false, message: "Ziel fehlt")
            }
            confirmation = ActionConfirmation(kind: .navigate, title: "Route nach „\(destination)“ starten?",
                                              options: [.init(label: "Route starten", value: destination)])
            return ActionResult(ok: true, message: "Rückfrage auf dem iPhone angezeigt: Route nach \(destination)")
        case .reminder:
            guard let text = action.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return ActionResult(ok: false, message: "Woran soll ich erinnern?")
            }
            return await addReminder(title: text, date: action.date, time: action.time)
        case .save_photo:
            return await savePhoto()
        case .location:
            return await locate(label: action.label)
        }
    }

    // MARK: Erinnerungen (App „Erinnerungen“)

    private func addReminder(title: String, date: String?, time: String?) async -> ActionResult {
        let granted = (try? await eventStore.requestFullAccessToReminders()) ?? false
        guard granted else {
            return ActionResult(ok: false, message: "Kein Zugriff auf Erinnerungen – in den iOS-Einstellungen für RayBan Claude erlauben")
        }
        guard let list = eventStore.defaultCalendarForNewReminders() else {
            return ActionResult(ok: false, message: "Keine Erinnerungsliste gefunden")
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = String(title.prefix(200))
        reminder.calendar = list
        let due = Self.dueDate(date: date, time: time)
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            print("[Aktion] Erinnerung nicht gespeichert: \(error.localizedDescription)")
            return ActionResult(ok: false, message: "Erinnerung konnte nicht gespeichert werden")
        }
        let when = due.map { " für \(Self.dueFormatter.string(from: $0)) Uhr" } ?? ""
        return ActionResult(ok: true, message: "Erinnerung „\(reminder.title ?? title)“\(when) gespeichert")
    }

    /// Fälligkeit aus „JJJJ-MM-TT“ und/oder „HH:MM“ (nur Datum → 9 Uhr, nur Uhrzeit → nächstes Vorkommen)
    static func dueDate(date: String?, time: String?) -> Date? {
        let clock = (time ?? "").split(separator: ":").compactMap { Int($0) }
        let hasTime = clock.count == 2 && (0...23).contains(clock[0]) && (0...59).contains(clock[1])
        guard let date, !date.isEmpty else {
            return hasTime ? nextOccurrence(of: time)?.date : nil
        }
        let day = date.split(separator: "-").compactMap { Int($0) }
        guard day.count == 3 else { return nil }
        let components = DateComponents(year: day[0], month: day[1], day: day[2],
                                        hour: hasTime ? clock[0] : 9, minute: hasTime ? clock[1] : 0)
        return Calendar.current.date(from: components)
    }

    private static let dueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM, HH:mm"
        return f
    }()

    // MARK: Foto in der Mediathek sichern

    private func savePhoto() async -> ActionResult {
        guard let data = await latestPhoto?() else {
            return ActionResult(ok: false, message: "Kein Foto vorhanden – ist die Kamera bereit?")
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return ActionResult(ok: false, message: "Kein Zugriff auf Fotos – in den iOS-Einstellungen für RayBan Claude erlauben")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return ActionResult(ok: true, message: "Foto in der Mediathek gespeichert")
        } catch {
            print("[Aktion] Foto nicht gespeichert: \(error.localizedDescription)")
            return ActionResult(ok: false, message: "Foto konnte nicht gespeichert werden")
        }
    }

    // MARK: Standort („Wo bin ich?“, „Merk dir, wo ich geparkt habe“)

    private func locate(label: String?) async -> ActionResult {
        let place: String
        do {
            place = try await locator.currentAddress()
        } catch {
            return ActionResult(ok: false, message: error.localizedDescription)
        }
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return ActionResult(ok: true, message: "Aktueller Standort: \(place)")
        }
        let stamp = Self.stampFormatter.string(from: Date())
        guard memory?.add("\(label): \(place) (\(stamp))") != nil else {
            return ActionResult(ok: true, message: "Standort: \(place) – Gedächtnis ist aus, nicht gespeichert")
        }
        return ActionResult(ok: true, message: "Gemerkt – \(label): \(place)")
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d.M., HH:mm 'Uhr'"
        return f
    }()

    // MARK: Timer und Wecker

    private func schedule(label: String, fireDate: Date, trigger: UNNotificationTrigger, isAlarm: Bool) async -> ActionResult {
        let id = Self.idPrefix + UUID().uuidString
        let timer = RunningTimer(id: id, label: label, fireDate: fireDate, isAlarm: isAlarm)
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if allowed {
            let content = UNMutableNotificationContent()
            content.title = isAlarm ? "⏰ \(label)" : "⏱ \(label)"
            content.body = isAlarm ? "Es ist \(Self.timeFormatter.string(from: fireDate)) Uhr." : "Der Timer ist abgelaufen."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch {
                return ActionResult(ok: false, message: "Timer konnte nicht gestellt werden")
            }
        } else {
            // Ohne Mitteilungen: nur solange die App offen ist
            fallbackTasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, fireDate.timeIntervalSinceNow) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.fire(id: id)
            }
        }
        timers.append(timer)
        timers.sort { $0.fireDate < $1.fireDate }
        let when = isAlarm ? "um \(Self.timeFormatter.string(from: fireDate)) Uhr" : Self.describe(duration: fireDate.timeIntervalSinceNow)
        let note = allowed ? "" : " (Mitteilungen sind aus – klingelt nur bei offener App)"
        return ActionResult(ok: true, message: "\(isAlarm ? "Wecker" : "Timer") „\(label)“ \(when) gestellt\(note)")
    }

    func cancelTimers(matching label: String?) async -> ActionResult {
        let query = label?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let matching = timers.filter { query.isEmpty || $0.label.lowercased().contains(query) }
        guard !matching.isEmpty else { return ActionResult(ok: false, message: "Kein passender Timer läuft") }
        let ids = matching.map(\.id)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        ids.forEach { fallbackTasks.removeValue(forKey: $0)?.cancel() }
        timers.removeAll { ids.contains($0.id) }
        return ActionResult(ok: true, message: "\(matching.count) Timer/Wecker gelöscht")
    }

    /// Einen bestimmten Timer löschen (Tipp auf den Timer in der App)
    func cancel(_ timer: RunningTimer) {
        center.removePendingNotificationRequests(withIdentifiers: [timer.id])
        fallbackTasks.removeValue(forKey: timer.id)?.cancel()
        timers.removeAll { $0.id == timer.id }
    }

    private func fire(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        timers.removeAll { $0.id == id }
        fallbackTasks.removeValue(forKey: id)
        onTimerFired?(timer)
    }

    /// Abgelaufene Einträge entfernen (z. B. nachdem die App im Hintergrund war)
    func refreshTimers() async {
        guard !DemoMode.isActive else { return }
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        timers.removeAll { !pending.contains($0.id) && fallbackTasks[$0.id] == nil }
    }

    /// Nächstes Vorkommen einer Uhrzeit „HH:MM“ (heute oder morgen)
    static func nextOccurrence(of time: String?) -> (components: DateComponents, date: Date)? {
        let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        let components = DateComponents(hour: parts[0], minute: parts[1])
        guard let date = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return nil }
        return (components, date)
    }

    static func describe(duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        let parts = [
            hours > 0 ? "\(hours) Std" : nil,
            minutes > 0 ? "\(minutes) Min" : nil,
            hours == 0 && seconds > 0 ? "\(seconds) Sek" : nil,
        ].compactMap { $0 }
        return "für " + (parts.isEmpty ? "0 Sek" : parts.joined(separator: " "))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: Anruf und Nachricht

    private func prepareContactAction(_ action: PhoneAction, kind: ActionConfirmation.Kind, verb: String) async -> ActionResult {
        if let number = action.number, !number.isEmpty {
            confirmation = ActionConfirmation(kind: kind, title: "\(verb) \(number)?", options: [.init(label: number, value: number)])
            return ActionResult(ok: true, message: "Rückfrage auf dem iPhone angezeigt: \(verb) die genannte Nummer")
        }
        guard let name = action.contact, !name.isEmpty else { return ActionResult(ok: false, message: "Kontakt fehlt") }

        let granted = (try? await contactStore.requestAccess(for: .contacts)) ?? false
        guard granted else {
            return ActionResult(ok: false, message: "Kein Zugriff auf Kontakte – in den iOS-Einstellungen für RayBan Claude erlauben")
        }
        let options = await Self.findNumbers(for: name, in: contactStore)
        guard !options.isEmpty else { return ActionResult(ok: false, message: "Kein Kontakt „\(name)“ mit Telefonnummer gefunden") }

        confirmation = ActionConfirmation(kind: kind, title: "\(verb) \(name)?", options: options)
        // Nur Namen und Art der Nummer an Claude – keine Telefonnummern
        let summary = options.count == 1 ? options[0].label : "\(options.count) Nummern zur Auswahl"
        return ActionResult(ok: true, message: "Rückfrage auf dem iPhone angezeigt: \(verb) \(summary)")
    }

    /// Kontaktsuche abseits des Main-Threads (CNContactStore blockiert)
    private static func findNumbers(for name: String, in store: CNContactStore) async -> [ActionConfirmation.Option] {
        await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            let contacts = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)) ?? []
            return contacts.prefix(5).flatMap { contact -> [ActionConfirmation.Option] in
                let display = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.nickname
                return contact.phoneNumbers.prefix(4).map { labeled in
                    let kind = labeled.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "Telefon"
                    return ActionConfirmation.Option(label: "\(display) (\(kind))", value: labeled.value.stringValue)
                }
            }
        }.value
    }

    // MARK: Bestätigen

    func confirm(_ option: ActionConfirmation.Option) {
        guard let pending = confirmation else { return }
        confirmation = nil
        switch pending.kind {
        case .call:
            let digits = option.value.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel://\(digits)") { UIApplication.shared.open(url) }
        case .message(let text):
            if MFMessageComposeViewController.canSendText() {
                messageDraft = MessageDraft(recipient: option.value, text: text)
            } else if let url = URL(string: "sms:\(option.value.filter { $0.isNumber || $0 == "+" })") {
                UIApplication.shared.open(url)
            }
        case .navigate:
            var comps = URLComponents(string: "https://maps.apple.com/")
            comps?.queryItems = [URLQueryItem(name: "daddr", value: option.value)]
            if let url = comps?.url { UIApplication.shared.open(url) }
        }
    }

    func dismissConfirmation() {
        confirmation = nil
    }

    /// Nur für den Demo-Modus (Screenshots)
    func showDemo(timerLabel: String, seconds: TimeInterval, confirmation: ActionConfirmation?) {
        timers = [RunningTimer(id: "demo", label: timerLabel, fireDate: Date().addingTimeInterval(seconds), isAlarm: false)]
        self.confirmation = confirmation
    }
}

// MARK: - Mitteilungen im Vordergrund

extension PhoneActionHandler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        Task { @MainActor in self.fire(id: id) }
        completionHandler([.banner, .sound])
    }
}

// MARK: - Nachrichten-Fenster

/// Systemfenster zum Senden einer SMS/iMessage – der Nutzer tippt selbst auf „Senden“.
struct MessageComposeView: UIViewControllerRepresentable {
    let draft: MessageDraft
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [draft.recipient]
        controller.body = draft.text
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}
