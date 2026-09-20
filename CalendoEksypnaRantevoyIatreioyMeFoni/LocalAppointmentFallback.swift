import Foundation
import Speech

struct LocalAppointmentFallback {
    enum FallbackError: LocalizedError {
        case speechPermissionDenied
        case unavailable
        case noTranscript

        var errorDescription: String? {
            switch self {
            case .speechPermissionDenied: "Δώστε πρόσβαση στην Αναγνώριση ομιλίας από τις Ρυθμίσεις για την τοπική εναλλακτική ανάλυση."
            case .unavailable: "Η ελληνική αναγνώριση ομιλίας δεν είναι διαθέσιμη αυτή τη στιγμή στη συσκευή."
            case .noTranscript: "Δεν προέκυψε αναγνώσιμο κείμενο από την ηχογράφηση."
            }
        }
    }

    func analyze(audioURL: URL) async throws -> AIAppointmentResult {
        let transcript = try await transcribe(audioURL: audioURL)
        return GreekAppointmentParser.parse(transcript: transcript, referenceDate: .now)
    }

    private func transcribe(audioURL: URL) async throws -> String {
        let authorization = await speechAuthorization()
        guard authorization == .authorized else { throw FallbackError.speechPermissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "el_GR")), recognizer.isAvailable else {
            throw FallbackError.unavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = ["ραντεβού", "ασθενής", "γιατρός", "λεπτά", "αύριο", "μεθαύριο"]
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !completed else { return }
                if let result, result.isFinal {
                    completed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    completed = true
                    NSLog("Calendo local speech fallback failed: %@", error.localizedDescription)
                    continuation.resume(throwing: FallbackError.noTranscript)
                }
            }
        }
    }

    private func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum GreekAppointmentParser {
    static func parse(transcript: String, referenceDate: Date) -> AIAppointmentResult {
        let normalized = transcript.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "el_GR"))
        let date = date(in: normalized, referenceDate: referenceDate) ?? referenceDate
        let time = time(in: normalized) ?? "09:00"
        let duration = duration(in: normalized) ?? 30
        let name = patientName(in: transcript)
        let components = time.split(separator: ":").compactMap { Int($0) }
        let start = Calendar.athens.date(bySettingHour: components.first ?? 9, minute: components.dropFirst().first ?? 0, second: 0, of: date) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Athens")
        formatter.dateFormat = "yyyy-MM-dd"
        return AIAppointmentResult(patientName: name, dateISO: formatter.string(from: start), time: time, durationMinutes: duration, confidence: name.isEmpty ? 0.35 : 0.62)
    }

    private static func date(in text: String, referenceDate: Date) -> Date? {
        if text.contains("μεθαυριο") { return Calendar.athens.date(byAdding: .day, value: 2, to: referenceDate) }
        if text.contains("αυριο") { return Calendar.athens.date(byAdding: .day, value: 1, to: referenceDate) }
        if text.contains("σημερα") { return referenceDate }
        let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let day = Int((text as NSString).substring(with: match.range(at: 1))),
              let month = Int((text as NSString).substring(with: match.range(at: 2))) else { return nil }
        let yearText = match.range(at: 3).location == NSNotFound ? nil : (text as NSString).substring(with: match.range(at: 3))
        let year = yearText.flatMap(Int.init).map { $0 < 100 ? $0 + 2000 : $0 } ?? Calendar.athens.component(.year, from: referenceDate)
        return Calendar.athens.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func time(in text: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?:[:.](\d{2}))?\b"#)
        let range = NSRange(text.startIndex..., in: text)
        for match in regex?.matches(in: text, range: range) ?? [] {
            let hour = Int((text as NSString).substring(with: match.range(at: 1))) ?? 0
            guard hour <= 23 else { continue }
            let minute = match.range(at: 2).location == NSNotFound ? 0 : Int((text as NSString).substring(with: match.range(at: 2))) ?? 0
            guard minute < 60 else { continue }
            return String(format: "%02d:%02d", hour, minute)
        }
        return nil
    }

    private static func duration(in text: String) -> Int? {
        let regex = try? NSRegularExpression(pattern: #"\b(\d{1,3})\s*(?:λεπτα|λεπτο|minutes?)\b"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range) else { return nil }
        let value = Int((text as NSString).substring(with: match.range(at: 1))) ?? 30
        return (5...240).contains(value) ? value : 30
    }

    private static func patientName(in transcript: String) -> String {
        let markers = ["ονομα", "ασθενης", "λεγετε", "για τον", "για τη"]
        let lower = transcript.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "el_GR"))
        for marker in markers where lower.contains(marker) {
            guard let range = lower.range(of: marker) else { continue }
            let suffix = transcript[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let words = suffix.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "." }).prefix(3)
            let candidate = words.filter { $0.count > 1 && !$0.allSatisfy(\.isNumber) }.joined(separator: " ")
            if candidate.count > 2 { return candidate.capitalized }
        }
        return ""
    }
}

private extension Calendar {
    static var athens: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Athens") ?? .current
        return calendar
    }
}
