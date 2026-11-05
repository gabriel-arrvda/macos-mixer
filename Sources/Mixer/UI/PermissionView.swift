import SwiftUI

struct PermissionView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Falta uma permissão")
                .font(.system(size: 13, weight: .semibold))
            Text("Ative o \(AppConstants.name) em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Settings.open(AppConstants.audioCapturePrivacyURL, fallback: AppConstants.securitySettingsURL)
            } label: {
                Text("Abrir Ajustes do Sistema").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Já ativei, tentar de novo", action: onRetry)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
        .padding(20)
    }
}
