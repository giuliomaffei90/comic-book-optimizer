import SwiftUI

/// Shown when the pipeline hits an image it can't classify: keep it, drop it,
/// or crop it and slice it along as many vertical cuts as the foldout needs.
struct PageEditor: View {
    let image: CGImage
    let label: String
    let manga: Bool
    let onDecision: (PageDecision) -> Void

    // Normalised to the image, origin top-left — same convention as CGImage.cropping.
    @State private var cropL: CGFloat = 0
    @State private var cropR: CGFloat = 1
    @State private var cropT: CGFloat = 0
    @State private var cropB: CGFloat = 1
    @State private var cuts: [CGFloat] = []

    private let space = "canvas"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                Text("Fuori formato: \(image.width)×\(image.height) px. "
                     + "Trascina i bordi per ritagliare, aggiungi tagli verticali per dividerla.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let r = fitted(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)

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
                .coordinateSpace(name: space)
            }
            .frame(minHeight: 340)

            HStack {
                Button("Aggiungi taglio") { addCut() }
                Button("Azzera tagli") { cuts.removeAll() }.disabled(cuts.isEmpty)
                Button("Reimposta ritaglio") { cropL = 0; cropR = 1; cropT = 0; cropB = 1 }
                    .disabled(cropL == 0 && cropR == 1 && cropT == 0 && cropB == 1)
                Spacer()
                Text(pieces().count == 1 ? "→ 1 pagina" : "→ \(pieces().count) pagine")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if !cuts.isEmpty {
                Text(manga ? "Ordine di lettura: destra → sinistra"
                           : "Ordine di lettura: sinistra → destra")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Elimina pagina", role: .destructive) { onDecision(.drop) }
                Spacer()
                Button("Tieni invariata") { onDecision(.keep) }
                Button("Applica") { onDecision(.replace(pieces())) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pieces().isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 580)
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
            .position(x: x, y: r.minY + 12)
        }
    }

    // MARK: - geometry

    private func fitted(in size: CGSize) -> CGRect {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let s = min(size.width / iw, size.height / ih)
        return CGRect(x: (size.width - iw * s) / 2, y: (size.height - ih * s) / 2,
                      width: iw * s, height: ih * s)
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
        let W = CGFloat(image.width), H = CGFloat(image.height)
        let xs = ([cropL] + cuts.sorted() + [cropR]).map { $0 * W }
        let y = cropT * H, h = (cropB - cropT) * H
        return (0..<(xs.count - 1)).compactMap { i in
            let rect = CGRect(x: xs[i], y: y, width: xs[i + 1] - xs[i], height: h).integral
            guard rect.width >= 8, rect.height >= 8 else { return nil }
            return image.cropping(to: rect)
        }
    }
}
