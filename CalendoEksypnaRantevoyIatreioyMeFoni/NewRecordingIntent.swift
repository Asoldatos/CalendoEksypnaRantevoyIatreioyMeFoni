import AppIntents
import Foundation

struct NewRecordingIntent: AppIntent {
    static let requestKey = "calendo.startRecordingRequested"
    static let title: LocalizedStringResource = "Νέα εγγραφή"
    static let description = IntentDescription("Ανοίγει το Calendo κατευθείαν σε νέα φωνητική εγγραφή.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: Self.requestKey)
        return .result(dialog: "Ανοίγω μια νέα εγγραφή στο Calendo.")
    }
}

struct CalendoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewRecordingIntent(),
            phrases: [
                "Νέα εγγραφή στο \(.applicationName)",
                "Νέο ραντεβού στο \(.applicationName)",
                "Καταχώρισε ραντεβού με το \(.applicationName)"
            ],
            shortTitle: "Νέα εγγραφή",
            systemImageName: "waveform.badge.mic"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
