import SwiftUI

enum Estilo {
    static let fondoArriba = Color(red: 0.06, green: 0.07, blue: 0.17)
    static let fondoAbajo = Color(red: 0.15, green: 0.10, blue: 0.29)
    static let acento = Color(red: 0.72, green: 0.66, blue: 0.98)
    static let luna = Color(red: 0.97, green: 0.93, blue: 0.78)
    static let tarjeta = Color.white.opacity(0.07)
    static let borde = Color.white.opacity(0.10)
    static let suave = Color.white.opacity(0.6)

    static var fondo: some View {
        LinearGradient(colors: [fondoArriba, fondoAbajo], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }

    static func hora(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
}

struct Tarjeta<Contenido: View>: View {
    var titulo: String?
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let titulo {
                Text(titulo.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Estilo.suave)
            }
            contenido
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Estilo.tarjeta, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Estilo.borde, lineWidth: 1))
    }
}

/// Una pastilla seleccionable.
struct Chip: View {
    let texto: String
    var icono: String?
    var color: Color = Estilo.acento
    let activo: Bool
    var accion: () -> Void = {}

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                if let icono { Image(systemName: icono).font(.caption) }
                Text(texto).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(activo ? color.opacity(0.28) : Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(activo ? color : Estilo.borde, lineWidth: 1))
            .foregroundStyle(activo ? .white : Estilo.suave)
        }
        .buttonStyle(.plain)
    }
}

/// Coloca las pastillas en líneas, como el texto.
struct Flujo: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            maxX = max(maxX, x - espacio)
            alto = max(alto, t.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + t.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}

/// Anillo con la puntuación de ronquidos (0–100).
struct Anillo: View {
    let valor: Int
    let color: Color
    var tam: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(max(valor, 1)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(valor)").font(.system(size: tam * 0.32, weight: .bold, design: .rounded))
        }
        .frame(width: tam, height: tam)
    }
}

/// Estrellas del 1 al 5.
struct Estrellas: View {
    let valor: Int
    var cambiar: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= valor ? "star.fill" : "star")
                    .foregroundStyle(i <= valor ? Estilo.luna : Estilo.suave)
                    .onTapGesture { cambiar?(i) }
            }
        }
    }
}

/// Onda de niveles (barras).
struct Onda: View {
    let valores: [Double]
    var color: Color = Estilo.acento

    var body: some View {
        Canvas { ctx, size in
            guard !valores.isEmpty else { return }
            let ancho = size.width / CGFloat(valores.count)
            for (i, v) in valores.enumerated() {
                let h = max(2, CGFloat((v - 25) / 60) * size.height)
                let r = CGRect(x: CGFloat(i) * ancho + 1, y: (size.height - min(h, size.height)) / 2,
                               width: max(1, ancho - 2), height: min(h, size.height))
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(color.opacity(0.4 + 0.6 * Double(i) / Double(valores.count))))
            }
        }
    }
}

extension UUID: Identifiable {
    public var id: UUID { self }
}
