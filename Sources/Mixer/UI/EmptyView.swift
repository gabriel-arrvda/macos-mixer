import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.zzz")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Nada tocando agora")
                .font(.system(size: 13, weight: .semibold))
            Text("Quando um app tocar som, ele aparece aqui.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .accessibilityElement(children: .combine)
    }
}
