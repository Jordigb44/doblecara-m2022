// PrintDuplexIntent.swift — acción de Shortcuts para imprimir un PDF a doble cara.
// Se expone en la app Atajos con la frase «Imprimir a doble cara».

import AppIntents
import SwiftUI

struct PrintDuplexIntent: AppIntent {
    static var title: LocalizedStringResource = "Imprimir a doble cara"
    static var description = IntentDescription("Abre un PDF en Doble Cara M2022 para imprimirlo a doble cara manual.")

    @Parameter(title: "PDF")
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Imprimir \(\.$file) a doble cara")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = file.fileURL else {
            throw IntentError.fileNotFound
        }
        Model.shared.load(url)
        NSApp.activate(ignoringOtherApps: true)
        return .result()
    }
}

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case fileNotFound
    var localizedStringResource: LocalizedStringResource {
        "No se pudo leer el archivo."
    }
}

struct DobleCaraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PrintDuplexIntent(),
            phrases: ["Imprimir a doble cara en \(.applicationName)"],
            shortTitle: "Imprimir a doble cara",
            systemImageName: "printer.fill"
        )
    }
}
