import AppKit
import MixerCore
import SwiftUI

/// Tema escolhido em Ajustes › Aparência. Guardado no `UserDefaults`.
enum AppearanceMode: String, CaseIterable {
    case light, dark, system

    var title: String {
        switch self {
        case .light: return "Claro"
        case .dark: return "Escuro"
        case .system: return "Automático (sistema)"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: AppConstants.appearanceKey) ?? "") ?? .system
    }

    /// Salva e aplica no app inteiro (a janela do menu segue o `NSApp.appearance`).
    @MainActor static func select(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: AppConstants.appearanceKey)
        mode.apply()
    }

    /// Só chamar depois que o app subiu (no `init` do `App` o `NSApp` ainda é nil).
    @MainActor func apply() {
        guard let app = NSApp else { return }
        switch self {
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        case .system: app.appearance = nil
        }
    }
}

enum Palette {
    static let boost = Color(nsColor: .systemOrange)
    static let clip = Color(nsColor: .systemRed)
    static let mic = Color(nsColor: .systemGreen)
}

/// Cor dominante do ícone de cada app, usada no slider, no medidor e no foco da caixa de porcentagem.
/// Escolhe a cor mais viva (e não a mais comum): fundo branco ou cinza do ícone não conta.
@MainActor
enum IconPalette {
    private static var cache: [String: NSColor] = [:]

    static func color(for owner: AppOwner, scheme: ColorScheme) -> Color {
        let base = cache[owner.key] ?? {
            let found = NSRunningApplication(processIdentifier: owner.pid)?.icon.flatMap(dominant) ?? fallback(owner.key)
            cache[owner.key] = found
            return found
        }()
        return Color(nsColor: readable(base, dark: scheme == .dark))
    }

    /// Agrupa os pixels por faixa de matiz, pesando por saturação e brilho, e devolve a média da faixa mais forte.
    private static func dominant(_ icon: NSImage) -> NSColor? {
        let side = 32
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        let bins = 18
        var weight = [CGFloat](repeating: 0, count: bins)
        var sums = [(r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: bins)
        for x in 0..<side {
            for y in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
                let saturation = color.saturationComponent, brightness = color.brightnessComponent
                guard saturation > 0.28, brightness > 0.22 else { continue }
                let bin = min(Int(color.hueComponent * CGFloat(bins)), bins - 1)
                let w = saturation * brightness
                weight[bin] += w
                sums[bin].r += color.redComponent * w
                sums[bin].g += color.greenComponent * w
                sums[bin].b += color.blueComponent * w
            }
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.5 else { return nil }
        let w = weight[best]
        return NSColor(deviceRed: sums[best].r / w, green: sums[best].g / w, blue: sums[best].b / w, alpha: 1)
    }

    /// Sem ícone colorido (ferramenta de linha de comando, ícone cinza): cor estável a partir do nome.
    private static func fallback(_ key: String) -> NSColor {
        let colors: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemTeal, .systemIndigo, .systemOrange, .systemGreen]
        let hash = key.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return colors[Int(hash % UInt32(colors.count))]
    }

    /// Clareia no escuro e escurece no claro, pra a cor nunca sumir no fundo.
    private static func readable(_ color: NSColor, dark: Bool) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        brightness = dark ? max(brightness, 0.72) : min(max(brightness, 0.38), 0.82)
        if dark { saturation = min(saturation, 0.85) }
        return NSColor(deviceHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }
}

/// Símbolo e descrição de cada tipo de saída.
enum DeviceSymbol {
    static func name(for device: OutputDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        switch device.transport {
        case .bluetooth: return "headphones"
        case .builtIn: return "laptopcomputer"
        case .usb: return "hifispeaker"
        case .hdmi: return "tv"
        case .airPlay: return "airplayaudio"
        case .other: return "speaker.wave.2"
        }
    }

    static func kind(of device: OutputDevice) -> String {
        switch device.transport {
        case .builtIn: return "Integrado"
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .hdmi: return "HDMI"
        case .airPlay: return "AirPlay"
        case .other: return "Outro"
        }
    }
}
