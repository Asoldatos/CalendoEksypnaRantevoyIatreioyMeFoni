import Observation
import SwiftUI

@main
struct CalendoApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(nil)
                .tint(CalendoColor.teal)
        }
    }
}

@MainActor
@Observable
final class AppStore {
    enum Route: Hashable { case recording, review, saved }

    var path: [Route] = []
    var editingDraft: AppointmentDraft?
    var drafts: [AppointmentDraft] = []
    var hasCompletedOnboarding: Bool
    var selectedCalendarID: String
    let google = GoogleSession()
    private let repository: any AppointmentDraftRepository

    init(repository: any AppointmentDraftRepository = LocalDraftRepository()) {
        self.repository = repository
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "calendo.onboarding.complete")
        selectedCalendarID = UserDefaults.standard.string(forKey: "calendo.calendar.id") ?? ""
        drafts = repository.load()
        if drafts.isEmpty { let sample = AppointmentDraft.sample; try? repository.save(sample); drafts = [sample] }
        handleShortcutRequest()
    }

    var latestDraft: AppointmentDraft? { drafts.sorted { $0.updatedAt > $1.updatedAt }.first }

    func completeOnboarding(calendarID: String) {
        selectedCalendarID = calendarID
        UserDefaults.standard.set(calendarID, forKey: "calendo.calendar.id")
        UserDefaults.standard.set(true, forKey: "calendo.onboarding.complete")
        hasCompletedOnboarding = true
    }

    func startRecording() { editingDraft = .blank; path = [.recording] }

    func reviewRecording(audioURL: URL, transcript: String) {
        var draft = editingDraft ?? .blank
        draft.audioFileName = audioURL.lastPathComponent
        draft.transcript = transcript
        editingDraft = draft
        path = [.review]
    }

    func reviewManually() {
        var draft = editingDraft ?? .blank
        draft.transcript = nil
        editingDraft = draft
        path = [.review]
    }

    func applyAI(_ result: AIAppointmentResult, to draft: inout AppointmentDraft) {
        if !result.patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.patientName = result.patientName }
        if !result.telephone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.telephone = result.telephone }
        if let date = Self.appointmentDate(day: result.dateISO, time: result.time) { draft.startDate = date }
        if (5...240).contains(result.durationMinutes) { draft.durationMinutes = result.durationMinutes }
    }

    func createCalendarEvent(_ draft: AppointmentDraft) async throws {
        guard draft.canSave else { return }
        try await google.createEvent(draft, calendarID: selectedCalendarID)
        var saved = draft
        try repository.removeAudio(for: saved)
        saved.audioFileName = nil
        saved.status = .ready
        saved.updatedAt = .now
        try repository.save(saved)
        drafts = repository.load()
        editingDraft = saved
        path = [.saved]
    }

    func edit(_ draft: AppointmentDraft) { editingDraft = draft; path = [.review] }
    func delete(_ draft: AppointmentDraft) { try? repository.delete(draft); drafts = repository.load() }
    func finishFlow() { editingDraft = nil; path.removeAll() }

    func handleShortcutRequest() {
        guard UserDefaults.standard.bool(forKey: NewRecordingIntent.requestKey), hasCompletedOnboarding else { return }
        UserDefaults.standard.set(false, forKey: NewRecordingIntent.requestKey); startRecording()
    }

    private static func appointmentDate(day: String, time: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Europe/Athens"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(day) \(time)")
    }
}
