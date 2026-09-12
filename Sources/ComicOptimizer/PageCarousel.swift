import SwiftUI

/// First stop after the drop: flip through every page and mark the ones to throw away
/// (adverts, scan targets, duplicate covers) before the pipeline touches anything.
struct PageCarousel: View {
    let pages: [CGImage]
    let title: String
    let onDone: (Set<Int>?) -> Void

    @State private var current = 0
    @State private var removed: Set<Int> = []

    private var isRemoved: Bool { removed.contains(current) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(removed.isEmpty
                     ? "\(pages.count) pagine. Segna quelle da eliminare, poi continua."
                     : "\(pages.count) pagine, \(removed.count) da eliminare.")
                    .font(.caption)
                    .foregroundStyle(removed.isEmpty ? Color.secondary : Color.red)
            }

            ZStack {
                Color.black.opacity(0.06)
                Image(decorative: pages[current], scale: 1)
                    .resizable().scaledToFit()
                    .padding(8)
                    .opacity(isRemoved ? 0.25 : 1)
                if isRemoved {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(current == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Text("\(current + 1) / \(pages.count)").monospacedDigit()
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(current == pages.count - 1)
                    .keyboardShortcut(.rightArrow, modifiers: [])

                Button(isRemoved ? "Ripristina" : "Elimina questa pagina") { toggle() }
                    .tint(isRemoved ? .accentColor : .red)

                Spacer()
                Text("\(pages[current].width)×\(pages[current].height) px")
                    .font(.caption).foregroundStyle(.secondary)
            }

            filmstrip

            Divider()

            HStack {
                Button("Annulla") { onDone(nil) }
                Spacer()
                Button("Azzera") { removed.removeAll() }.disabled(removed.isEmpty)
                Button("Continua") { onDone(removed) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 720)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Image(decorative: pages[i], scale: 1)
                            .resizable().scaledToFill()
                            .frame(width: 52, height: 72)
                            .clipped()
                            .opacity(removed.contains(i) ? 0.3 : 1)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .stroke(border(i), lineWidth: i == current ? 3 : 1))
                            .id(i)
                            .onTapGesture { current = i }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 84)
            .onChange(of: current) { proxy.scrollTo($0, anchor: .center) }
        }
    }

    private func border(_ i: Int) -> Color {
        removed.contains(i) ? .red : (i == current ? .accentColor : .secondary.opacity(0.3))
    }

    private func step(_ delta: Int) { current = min(max(current + delta, 0), pages.count - 1) }

    private func toggle() {
        if removed.contains(current) { removed.remove(current) } else { removed.insert(current) }
    }
}
