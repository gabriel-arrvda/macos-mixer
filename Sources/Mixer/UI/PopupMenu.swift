import AppKit

/// Menu nativo do macOS aberto na posição do mouse. Usado na escolha de saída e em Ajustes,
/// porque o `Menu` do SwiftUI não deixa personalizar o botão que abre o menu.
@MainActor
enum PopupMenu {
    enum Item {
        case header(String)
        case separator
        case action(title: String, symbol: String? = nil, checked: Bool = false, run: () -> Void)
    }

    static func show(_ items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item {
            case .header(let title):
                menu.addItem(NSMenuItem.sectionHeader(title: title))
            case .separator:
                menu.addItem(.separator())
            case let .action(title, symbol, checked, run):
                let entry = ClosureItem(title: title, run: run)
                entry.state = checked ? .on : .off
                if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
                menu.addItem(entry)
            }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class ClosureItem: NSMenuItem {
        private let run: () -> Void

        init(title: String, run: @escaping () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }

        @available(*, unavailable)
        required init(coder: NSCoder) { fatalError("init(coder:) não é usado") }

        @objc private func fire() { run() }
    }
}
