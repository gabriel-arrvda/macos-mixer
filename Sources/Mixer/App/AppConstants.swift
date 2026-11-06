import Foundation

enum AppConstants {
    /// Nome provisório: trocar aqui basta (o nome do .app e do bundle vêm do build_app.sh).
    static let name = "Mixer"

    static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
    static let audioCapturePrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
    static let securitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!

    static let onboardingDoneKey = "onboardingDone"
    static let appearanceKey = "appearance"
    static let outputNoticeDuration: TimeInterval = 3
    static let silenceThreshold: TimeInterval = 5
    static let maxListHeight: CGFloat = 480
    static let windowWidth: CGFloat = 400
}
