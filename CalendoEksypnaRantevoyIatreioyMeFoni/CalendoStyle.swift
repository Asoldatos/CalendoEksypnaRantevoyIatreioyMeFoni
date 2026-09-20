import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum CalendoColor {
    static let teal = Color(red: 0.03, green: 0.50, blue: 0.55)
    static let mint = Color(red: 0.72, green: 0.85, blue: 0.84)
    static let ice = Color(red: 0.92, green: 0.97, blue: 0.97)
    static let navy = Color(red: 0.04, green: 0.15, blue: 0.20)
}

struct CalendoBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [CalendoColor.ice.opacity(0.95), CalendoColor.mint.opacity(0.28), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct ClinicalCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: CalendoColor.navy.opacity(0.07), radius: 16, y: 8)
    }
}

extension View {
    func clinicalCard() -> some View {
        modifier(ClinicalCard())
    }
}

struct PrimaryActionButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    func primaryActionStyle() -> some View {
        modifier(PrimaryActionButtonStyle())
    }
}

extension Date {
    var greekDay: String {
        formatted(.dateTime.locale(Locale(identifier: "el_GR")).weekday(.wide).day().month(.wide))
    }

    var greekTime: String {
        formatted(.dateTime.locale(Locale(identifier: "el_GR")).hour().minute())
    }
}
