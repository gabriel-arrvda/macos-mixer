import AppKit
import SwiftUI

/// A janela do `MenuBarExtra` cresce quando o conteúdo aumenta, mas não encolhe quando ele diminui
/// (ex.: um app para de tocar e sai da lista): sobra espaço vazio e o painel fica centralizado.
/// Este modificador mede a altura ideal do conteúdo e ajusta a janela, mantendo o topo colado na barra de menus.
extension View {
    func sizesMenuWindowToFit() -> some View {
        modifier(MenuWindowSizer())
    }
}

private struct MenuWindowSizer: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(ContentHeightKey.self) { height = $0 }
            .background(WindowResizer(height: height))
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct WindowResizer: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let target = height
        // Espera o ciclo de layout atual terminar antes de mexer na janela.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, target > 1 else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - target) > 0.5 else { return }
            let resized = NSRect(x: content.minX, y: content.maxY - target, width: content.width, height: target)
            window.setFrame(window.frameRect(forContentRect: resized), display: true, animate: false)
        }
    }
}
