import SwiftUI

// Cores e componentes compartilhados; sem imagens, bibliotecas ou efeitos contínuos.
enum ProFinStyle {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.055)
    static let surface = Color(red: 0.065, green: 0.085, blue: 0.12)
    static let blue = Color(red: 0.36, green: 0.65, blue: 1)
}

extension View {
    func proFinScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(ProFinStyle.background)
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .toolbarBackground(ProFinStyle.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct ProFinFeatureLabel: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ProFinStyle.blue)
                .frame(width: 42, height: 42)
                .background(ProFinStyle.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.white)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .padding(.vertical, 5)
    }
}

struct ProFinBalanceCard: View {
    let title: String
    let value: String
    let explanation: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ProFinStyle.blue)
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation).font(.subheadline).foregroundStyle(Color.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(LinearGradient(colors: [Color(red: 0.055, green: 0.15, blue: 0.29), ProFinStyle.surface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(ProFinStyle.blue.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

struct ProFinIntro: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        ProFinFeatureLabel(title: title, subtitle: message, symbol: symbol)
            .listRowBackground(ProFinStyle.surface)
    }
}
