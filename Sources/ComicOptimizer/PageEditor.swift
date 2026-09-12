import SwiftUI

/// Shown for every page the pipeline can't ship untouched: spreads (with the cut already
/// placed down the middle) and anything out of format. You can page through the whole book
/// to see the neighbours, zoom in, crop, and slice along as many vertical cuts as you need.
struct PageEditor: View {
    let pages: [CGImage]
    let index: Int
    let manga: Bool
    let onDecision: (PageDecision) -> Void

    // Normalised to the image, origin top-left — same convention as CGImage.cropping.
    @State private var cropL: CGFloat = 0
    @State private var cropR: CGFloat = 1
    @State private var cropT: CGFloat = 0
    @State private var cropB: CGFloat = 1
    @State private var cuts: [CGFloat]

    @State private var viewing: Int
    @State private var zoom: CGFloat = 1
    @State private var zoomAnchor: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAnchor: CGSize = .zero

    private let space = "canvas"
    private let maxZoom: CGFloat = 8

    init(pages: [CGImage], index: Int, suggestedCuts: [CGFloat], manga: Bool,
         onDecision: @escaping (PageDecision) -> Void) {
        self.pages = pages
        self.index = index
        self.manga = manga
        self.onDecision = onDecision
        _cuts = State(initialValue: suggestedCuts)
        _viewing = State(initialValue: index)
    }

    private var subject: CGImage { pages[index] }
    private var shown: CGImage { pages[viewing] }
    private var editing: Bool { viewing == index }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            canvas
            navigation
            controls
            Divider()
            actions
        }
        .padding(16)
        .frame(minWidth: 1000, minHeight: 780)
    }

    // MARK: - sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Pagina \(index + 1) di \(pages.count) — \(subject.width)×\(subject.height) px")
                .font(.headline)
            Text(editing
                 ? "Trascina i bordi per ritagliare, aggiungi tagli verticali per dividerla."
                 : "Stai sfogliando la pagina \(viewing + 1): le modifiche valgono per la \(index + 1).")
                .font(.caption)
                .foregroundStyle(editing ? Color.secondary : Color.orange)
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let r = displayRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.06)

                Image(decorative: shown, scale: 1)
                    .resizable()
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .gesture(pinch.simultaneously(with: drag(base: baseRect(in: geo.size))))

                if editing {
                    Path { p in
                        p.addRect(r)
                        p.addRect(cropRect(r))
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    Path(cropRect(r)).stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .allowsHitTesting(false)

                    handle(vertical: true, at: cropL, in: r) { cropL = min($0, cropR - 0.05) }
                    handle(vertical: true, at: cropR, in: r) { cropR = max($0, cropL + 0.05) }
                    handle(vertical: false, at: cropT, in: r) { cropT = min($0, cropB - 0.05) }
                    handle(vertical: false, at: cropB, in: r) { cropB = max($0, cropT + 0.05) }

                    ForEach(cuts.indices, id: \.self) { i in cut(i, in: r) }
                }
            }
            .coordinateSpace(name: space)
            .clipped()
        }
        .frame(minHeight: 440)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(viewing == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(viewing + 1) / \(pages.count)").monospacedDigit()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(viewing == pages.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])

            if !editing {
                Button("Torna alla pagina da modificare") { show(index) }
            }

            Spacer()

            Button { setZoom(zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= 1.01)
            Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: 52)
            Button { setZoom(zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom >= maxZoom - 0.01)
            Button("Adatta") { resetZoom() }.disabled(zoom == 1 && pan == .zero)
        }
    }

    @ViewBuilder private var controls: some View {
        if editing {
            HStack {
                Button("Aggiungi taglio") { addCut() }
                Button("Azzera tagli") { cuts.removeAll() }.disabled(cuts.isEmpty)
                Button("Reimposta ritaglio") { cropL = 0; cropR = 1; cropT = 0; cropB = 1 }
                    .disabled(cropL == 0 && cropR == 1 && cropT == 0 && cropB == 1)
                Spacer()
                if !cuts.isEmpty {
                    Text(manga ? "Lettura: destra → sinistra" : "Lettura: sinistra → destra")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(pieces().count == 1 ? "→ 1 pagina" : "→ \(pieces().count) pagine")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Elimina pagina", role: .destructive) { onDecision(.drop) }
            Spacer()
            Button("Tieni invariata") { onDecision(.keep) }
            Button("Applica") { onDecision(.replace(pieces())) }
                .keyboardShortcut(.defaultAction)
                .disabled(pieces().isEmpty)
        }
    }

    // MARK: - overlay pieces

    private func handle(vertical: Bool, at value: CGFloat, in r: CGRect,
                        set: @escaping (CGFloat) -> Void) -> some View {
        let x = vertical ? r.minX + value * r.width : r.midX
        let y = vertical ? r.midY : r.minY + value * r.height
        return ZStack {
            Color.clear.frame(width: vertical ? 22 : r.width, height: vertical ? r.height : 22)
            Rectangle().fill(.white)
                .frame(width: vertical ? 3 : r.width, height: vertical ? r.height : 3)
            Capsule().fill(.white).shadow(radius: 1)
                .frame(width: vertical ? 6 : 38, height: vertical ? 38 : 6)
                .offset(x: vertical ? 0 : -r.width * 0.3)
        }
        .contentShape(Rectangle())
        .position(x: x, y: y)
        .gesture(DragGesture(coordinateSpace: .named(space)).onChanged { g in
            set(clamp(vertical ? (g.location.x - r.minX) / r.width
                               : (g.location.y - r.minY) / r.height))
        })
    }

    private func cut(_ i: Int, in r: CGRect) -> some View {
        let x = r.minX + cuts[i] * r.width
        return ZStack {
            ZStack {
                Color.clear.frame(width: 22, height: r.height)
                Rectangle().fill(Color.orange).frame(width: 2, height: r.height)
            }
            .contentShape(Rectangle())
            .position(x: x, y: r.midY)
            .gesture(DragGesture(coordinateSpace: .named(space)).onChanged { g in
                cuts[i] = min(max((g.location.x - r.minX) / r.width, cropL + 0.02), cropR - 0.02)
            })

            Button { cuts.remove(at: i) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
            .position(x: x, y: r.minY + 14)
        }
    }

    // MARK: - zoom & pan

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { zoom = min(max(zoomAnchor * $0, 1), maxZoom) }
            .onEnded { _ in zoomAnchor = zoom }
    }

    private func drag(base: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { pan = clampPan(CGSize(width: panAnchor.width + $0.translation.width,
                                               height: panAnchor.height + $0.translation.height),
                                        base: base) }
            .onEnded { _ in panAnchor = pan }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 1), maxZoom)
        zoomAnchor = zoom
        if zoom == 1 { pan = .zero; panAnchor = .zero }
    }

    private func resetZoom() {
        zoom = 1; zoomAnchor = 1; pan = .zero; panAnchor = .zero
    }

    private func step(_ delta: Int) { show(min(max(viewing + delta, 0), pages.count - 1)) }

    private func show(_ i: Int) {
        viewing = i
        resetZoom()
    }

    private func clampPan(_ p: CGSize, base: CGRect) -> CGSize {
        let maxX = max(0, (base.width * zoom - base.width) / 2)
        let maxY = max(0, (base.height * zoom - base.height) / 2)
        return CGSize(width: min(max(p.width, -maxX), maxX),
                      height: min(max(p.height, -maxY), maxY))
    }

    // MARK: - geometry

    /// Leaves a margin so the edge handles stay fully visible instead of half-clipped.
    private func baseRect(in size: CGSize) -> CGRect {
        let iw = CGFloat(shown.width), ih = CGFloat(shown.height)
        let s = min((size.width - 36) / iw, (size.height - 36) / ih)
        return CGRect(x: (size.width - iw * s) / 2, y: (size.height - ih * s) / 2,
                      width: iw * s, height: ih * s)
    }

    private func displayRect(in size: CGSize) -> CGRect {
        let base = baseRect(in: size)
        let w = base.width * zoom, h = base.height * zoom
        return CGRect(x: base.midX - w / 2 + pan.width, y: base.midY - h / 2 + pan.height,
                      width: w, height: h)
    }

    private func cropRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX + cropL * r.width, y: r.minY + cropT * r.height,
               width: (cropR - cropL) * r.width, height: (cropB - cropT) * r.height)
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }

    /// New cut lands in the middle of the widest slice, so repeated taps subdivide evenly.
    private func addCut() {
        let xs = [cropL] + cuts.sorted() + [cropR]
        var best = 0, widest: CGFloat = 0
        for i in 0..<(xs.count - 1) where xs[i + 1] - xs[i] > widest {
            widest = xs[i + 1] - xs[i]
            best = i
        }
        cuts.append((xs[best] + xs[best + 1]) / 2)
        cuts.sort()
    }

    private func pieces() -> [CGImage] {
        let W = CGFloat(subject.width), H = CGFloat(subject.height)
        let xs = ([cropL] + cuts.sorted() + [cropR]).map { $0 * W }
        let y = cropT * H, h = (cropB - cropT) * H
        return (0..<(xs.count - 1)).compactMap { i in
            let rect = CGRect(x: xs[i], y: y, width: xs[i + 1] - xs[i], height: h).integral
            guard rect.width >= 8, rect.height >= 8 else { return nil }
            return subject.cropping(to: rect)
        }
    }
}
