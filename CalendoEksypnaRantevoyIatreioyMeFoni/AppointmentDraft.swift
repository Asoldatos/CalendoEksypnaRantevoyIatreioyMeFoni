import Foundation

struct AppointmentDraft: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case draft
        case ready
        var title: String { self == .ready ? "Στο Google Calendar" : "Προσχέδιο" }
    }

    let id: UUID
    var patientName: String
    var startDate: Date
    var durationMinutes: Int
    var telephone: String
    var status: Status
    let createdAt: Date
    var updatedAt: Date
    var audioFileName: String?

    var endDate: Date { Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate }
    var calendarTitle: String {
        let name = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = telephone.trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, phone].filter { !$0.isEmpty }.joined(separator: " ").uppercased(with: Locale(identifier: "el_GR"))
    }
    var phoneDigits: String { telephone.filter(\.isNumber) }
    var hasValidTelephone: Bool { (10...15).contains(phoneDigits.count) }
    var canSave: Bool { !patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasValidTelephone }
    var audioURL: URL? { guard let audioFileName else { return nil }; return LocalDraftRepository.recordingsDirectory.appendingPathComponent(audioFileName) }

    static var blank: AppointmentDraft {
        let calendar = Calendar.current
        let rounded = calendar.date(bySetting: .minute, value: 0, of: .now.addingTimeInterval(3600)) ?? .now
        return AppointmentDraft(id: UUID(), patientName: "", startDate: rounded, durationMinutes: 30, telephone: "", status: .draft, createdAt: .now, updatedAt: .now, audioFileName: nil)
    }
    static var sample: AppointmentDraft {
        let start = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return AppointmentDraft(id: UUID(), patientName: "Ελένη Παπαδοπούλου", startDate: start, durationMinutes: 30, telephone: "694 123 4567", status: .ready, createdAt: .now, updatedAt: .now, audioFileName: nil)
    }
}

protocol AppointmentDraftRepository: Sendable {
    func load() -> [AppointmentDraft]
    func save(_ draft: AppointmentDraft) throws
    func delete(_ draft: AppointmentDraft) throws
    func removeAudio(for draft: AppointmentDraft) throws
}

struct LocalDraftRepository: AppointmentDraftRepository {
    static let recordingsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Recordings", isDirectory: true)
    }()
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("appointment-drafts.json")
    }
    func load() -> [AppointmentDraft] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([AppointmentDraft].self, from: data)) ?? []
    }
    func save(_ draft: AppointmentDraft) throws {
        var drafts = load(); drafts.removeAll { $0.id == draft.id }; drafts.append(draft)
        try prepareDirectory(); try JSONEncoder().encode(drafts).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
    func delete(_ draft: AppointmentDraft) throws {
        var drafts = load(); drafts.removeAll { $0.id == draft.id }
        try prepareDirectory(); try JSONEncoder().encode(drafts).write(to: fileURL, options: [.atomic, .completeFileProtection]); try removeAudio(for: draft)
    }
    func removeAudio(for draft: AppointmentDraft) throws {
        guard let audioURL = draft.audioURL, FileManager.default.fileExists(atPath: audioURL.path) else { return }
        try FileManager.default.removeItem(at: audioURL)
    }
    private func prepareDirectory() throws {
        let base = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.recordingsDirectory, withIntermediateDirectories: true)
    }
}
