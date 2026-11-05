import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
            Text("Antes de começar")
                .font(.system(size: 13, weight: .semibold))
            Text("Para mudar o volume de cada app, o \(AppConstants.name) precisa acessar o som deles. Quando um app começar a tocar, o macOS vai pedir a permissão **Gravação de Áudio do Sistema**. O som é ajustado na hora e não é gravado.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onContinue) {
                Text("Continuar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
}
