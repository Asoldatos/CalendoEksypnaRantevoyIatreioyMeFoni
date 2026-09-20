import SwiftUI

struct SavedView: View {
    let store: AppStore
    let draft: AppointmentDraft

    var body: some View {
        ZStack {
            CalendoBackground()
            ScrollView {
                VStack(spacing: 22) {
                    statusHero
                    summaryCard
                    privacyNote
                    actions
                }
                .padding(24)
            }
        }
        .navigationBarBackButtonHidden()
    }

    private var statusHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58)).foregroundStyle(CalendoColor.teal)
                .symbolEffect(.bounce, value: draft.id)
            Text("Έτοιμο για αποστολή")
                .font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Το προσχέδιο αποθηκεύτηκε με ασφάλεια σε αυτή τη συσκευή.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 28)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.calendarTitle).font(.title3.bold())
            Divider()
            SummaryRow(icon: "calendar", title: "Ημερομηνία", value: draft.startDate.greekDay)
            SummaryRow(icon: "clock", title: "Ώρα", value: "\(draft.startDate.greekTime)–\(draft.endDate.greekTime)")
            SummaryRow(icon: "hourglass", title: "Διάρκεια", value: "\(draft.durationMinutes) λεπτά")
            SummaryRow(icon: "phone", title: "Τηλέφωνο", value: draft.telephone)
        }
        .clinicalCard()
    }

    private var privacyNote: some View {
        Label {
            Text("Η σύνδεση Gemini και Google Calendar θα προστεθεί στο επόμενο ασφαλές στάδιο. Δεν έγινε απομακρυσμένη αποστολή.")
        } icon: {
            Image(systemName: "lock.shield.fill")
        }
        .font(.footnote).foregroundStyle(.secondary)
        .clinicalCard()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                store.edit(draft)
            } label: {
                Label("Επεξεργασία", systemImage: "pencil")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

            Button {
                store.finishFlow()
            } label: {
                Text("Επιστροφή στην αρχική")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .primaryActionStyle()
        }
    }
}

private struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(CalendoColor.teal).frame(width: 24)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
