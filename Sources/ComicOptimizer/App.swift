import SwiftUI

@main
struct ComicOptimizerApp: App {
    init() { SelfCheck.runIfRequested() }

    var body: some Scene {
        Window("Comic Book Optimizer", id: "main") {
            ContentView().frame(width: 480, height: 440)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor final class Model: ObservableObject {
    @Published var log: [String] = []
    @Published var busy = false
    @Published var askDirection = false
    @Published var askKeep = false
    @Published var manga = false
    @Published var useImageOptim = ImageOptim.available

    var pending: [URL] = []
    var processed: [(input: URL, output: URL)] = []

    private static let archives: Set<String> = ["cbr", "cbz", "cb7", "zip", "rar", "7z"]

    func dropped(_ urls: [URL]) {
        pending = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                || Self.archives.contains(url.pathExtension.lowercased())
        }
        askDirection = !pending.isEmpty
    }

    func start() {
        askDirection = false
        busy = true
        log = []
        processed = []
        let items = pending, manga = self.manga, optim = self.useImageOptim
        Task.detached(priority: .userInitiated) { [weak self] in
            for url in items {
                await self?.append("▸ \(url.lastPathComponent)")
                do {
                    let output = try Pipeline.run(input: url, manga: manga, useImageOptim: optim) { line in
                        Task { @MainActor in self?.log.append("    " + line) }
                    }
                    await self?.finished(url, output)
                } catch {
                    await self?.append("    ⚠︎ \(error.localizedDescription)")
                }
            }
            await self?.done()
        }
    }

    private func append(_ line: String) { log.append(line) }
    private func finished(_ input: URL, _ output: URL) { processed.append((input, output)) }

    private func done() {
        busy = false
        askKeep = !processed.isEmpty
    }

    func trashOriginals() {
        for (input, output) in processed {
            try? FileManager.default.trashItem(at: input, resultingItemURL: nil)
            // If the original occupied the plain name, take it back now that it's gone.
            let plain = input.deletingLastPathComponent()
                .appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".cbz")
            if output != plain, !FileManager.default.fileExists(atPath: plain.path) {
                try? FileManager.default.moveItem(at: output, to: plain)
            }
        }
        log.append("Originali spostati nel Cestino.")
        processed = []
    }
}

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical").font(.system(size: 32))
                    Text("Trascina qui un .cbr, .cbz, .zip\no una cartella di immagini")
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
            .frame(height: 150)
            .dropDestination(for: URL.self) { urls, _ in
                model.dropped(urls)
                return true
            } isTargeted: { targeted = $0 }
            .disabled(model.busy)

            if model.busy { ProgressView().progressViewStyle(.linear) }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .sheet(isPresented: $model.askDirection) { DirectionSheet(model: model) }
        .alert("Conservare i file originali?", isPresented: $model.askKeep) {
            Button("Conserva") { model.processed = [] }
            Button("Sposta nel Cestino", role: .destructive) { model.trashOriginals() }
        } message: {
            Text("I .cbz ottimizzati sono già stati salvati accanto agli originali.")
        }
    }
}

struct DirectionSheet: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(model.pending.count) elemento/i da ottimizzare").font(.headline)

            Picker("Senso di lettura", selection: $model.manga) {
                Text("Occidentale (sinistra → destra)").tag(false)
                Text("Manga (destra → sinistra)").tag(true)
            }
            .pickerStyle(.radioGroup)

            if ImageOptim.available {
                Toggle("Rifinisci con ImageOptim", isOn: $model.useImageOptim)
            }

            HStack {
                Spacer()
                Button("Annulla") { model.askDirection = false }
                Button("Ottimizza") { model.start() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
