import SwiftUI

/// Demo-Modus für Screenshots (Simulator ohne Kamera, PC und Brille).
/// Start mit den Argumenten `-demo`, optional `-demoConfirm` oder `-demoSettings`.
enum DemoMode {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var isActive: Bool { arguments.contains("-demo") }
    static var showSettings: Bool { isActive && arguments.contains("-demoSettings") }
    static var showConfirmation: Bool { isActive && arguments.contains("-demoConfirm") }
}

/// Nachgebautes Kamerabild: Typenschild einer Gastherme mit Störcode
struct DemoSceneView: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(white: 0.22), Color(white: 0.06)], center: .init(x: 0.5, y: 0.35),
                           startRadius: 20, endRadius: 520)
            VStack(alignment: .leading, spacing: 5) {
                Text("THERMAVIA").font(.system(size: 26, weight: .heavy, design: .rounded)).tracking(2)
                Text("CondensPro 24 · Gas-Brennwert").font(.system(size: 13, weight: .medium, design: .monospaced))
                Divider().overlay(.black.opacity(0.3))
                row("Baujahr", "2014")
                row("Nennleistung", "4,8–24 kW")
                row("Gasart", "G20 · 20 mbar")
                row("Serien-Nr.", "2114-0587-6632")
                Text("F28")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.36))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 4)
            }
            .foregroundStyle(Color(white: 0.12))
            .padding(18)
            .frame(width: 290)
            .background(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.62)], startPoint: .topLeading,
                                       endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.6), radius: 18, y: 10)
            .rotationEffect(.degrees(-3))
            .offset(y: -190)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
    }
}
