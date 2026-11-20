import SwiftUI

struct BrowserExtensionsPage: View {
    @State private var launchError: String?

    private var launcher: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Chromium/run-preview.sh")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Расширения", systemImage: "puzzlepiece.extension")
                .font(.title2.weight(.semibold))
            Text("Расширения Chromium с Manifest V2 и V3 работают в отдельной Chromium-сборке myBro.")
                .foregroundStyle(.secondary)
            Button("Открыть менеджер расширений Chromium") { openManager() }
            if let launchError {
                Text(launchError).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 680, maxHeight: .infinity, alignment: .topLeading)
    }

    private func openManager() {
        launchError = nil
        guard FileManager.default.isReadableFile(atPath: launcher.path) else {
            launchError = "Откройте myBro из папки проекта, рядом с каталогом Chromium."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [launcher.path, "chrome://extensions/"]
        process.terminationHandler = { process in
            if process.terminationStatus != 0 {
                DispatchQueue.main.async {
                    launchError = "Не удалось запустить Chromium. Проверьте сборку по инструкции в Chromium/README.md."
                }
            }
        }
        do {
            try process.run()
        } catch {
            launchError = error.localizedDescription
        }
    }
}
